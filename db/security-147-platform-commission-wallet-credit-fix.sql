-- =====================================================================
--  وصّلها — Security #147: عمولة المنصة متسجّلة بس في wallet_transactions
--  من غير ما تتضاف فعليًا لرصيد محفظة platform
--
--  اتكشف وقت بناء أتمتة "مطابقة المحفظة/العمولات" الجديدة: settle_
--  ride_commission و settle_order_commission (security-07، بآخر تعديل
--  security-07b لمشكلة type mismatch في id) بيضيفوا أرباح السائق
--  لمحفظته (add_wallet_balance) وبرضه بيسجّلوا نفس العملية في
--  wallet_transactions — لكن لعمولة المنصة نفسها، بيسجّلوا صف في
--  wallet_transactions بس من غير ما يضيفوه فعليًا لرصيد محفظة
--  'platform' (مفيش استدعاء add_wallet_balance('platform', ...) خالص).
--
--  النتيجة: دفتر الحركات بيقول إن المنصة كسبت فلوس (110 عملية عمولة =
--  4468 ج.م)، لكن رصيد محفظتها الفعلي (public.wallets) ما زادش بنفس
--  القيمة — فجوة حقيقية، اتأكّدت بتشغيل مطابقة فعلية على الداتا الحية
--  (مش فرضية):
--    select w.balance - sum(t.amount) from wallets w join
--    wallet_transactions t on t.phone=w.phone where w.phone='platform'
--    → -4468 بالضبط، ومطابق تمامًا لمجموع صفوف type='commission'.
--
--  الحل جزئين — الدالتين هنا نفس النص الحي بالظبط (for update، نفس
--  idempotency guard، نفس ::text casts من security-07b) زائد سطر
--  add_wallet_balance('platform', ...) الناقص بس:
--  (أ) تصحيح الدالتين تضيف فعليًا لرصيد platform من دلوقتي فصاعدًا.
--  (ب) تصحيح لمرة واحدة بس (one-time backfill) يسوّي الفجوة الحالية —
--      آمن لإعادة التشغيل لأنه بيتأكد الأول إن التصحيح ده ما حصلش
--      قبل كده (id ثابت معروف في wallet_transactions).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- (أ) الدالتين — إضافة add_wallet_balance('platform', ...) الناقصة.
--     باقي النص نفسه الحي بالظبط (منقول من pg_get_functiondef مباشرة).
-- ---------------------------------------------------------------------
create or replace function public.settle_ride_commission(
  p_ride_id      text,
  p_driver_phone text
)
returns table(commission numeric, driver_earn numeric, rate numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ride       public.rides%rowtype;
  v_rate_key   text;
  v_rate_raw   text;
  v_rate       numeric;
  v_commission numeric;
  v_earn       numeric;
  v_note_pct   text;
begin
  if p_driver_phone is null or length(trim(p_driver_phone)) = 0 then
    raise exception 'driver_phone_required';
  end if;

  select * into v_ride from public.rides where id::text = p_ride_id for update;
  if not found then
    raise exception 'ride_not_found';
  end if;

  if v_ride.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_ride';
  end if;

  if v_ride.status <> 'completed' then
    raise exception 'ride_not_completed';
  end if;

  if v_ride.commission_settled then
    select abs(amount) into v_commission
      from public.wallet_transactions
      where reference_id = p_ride_id and type = 'commission'
      order by created_at desc limit 1;
    select amount into v_earn
      from public.wallet_transactions
      where reference_id = p_ride_id and type = 'earning'
      order by created_at desc limit 1;
    return query select coalesce(v_commission, 0), coalesce(v_earn, 0), 0::numeric;
    return;
  end if;

  v_rate_key := case
    when v_ride.ride_type = 'airport'  then 'commission_airport'
    when v_ride.ride_type = 'external' then 'commission_external'
    else 'commission_ride'
  end;

  select value into v_rate_raw from public.app_settings where key = v_rate_key;
  v_rate := nullif(v_rate_raw, '')::numeric;
  if v_rate is null or v_rate < 0 or v_rate >= 100 then
    v_rate := 15;
  end if;

  v_commission := round(coalesce(v_ride.fare, 0) * v_rate / 100);
  v_earn       := coalesce(v_ride.fare, 0) - v_commission;
  v_note_pct   := round(v_rate)::text;

  perform public.add_wallet_balance(p_driver_phone, v_earn);

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    p_driver_phone, v_earn, 'earning', p_ride_id,
    'أرباح رحلة — بعد خصم العمولة ' || v_note_pct || '%', now()
  );

  -- كانت ناقصة: العمولة اتسجلت كـ transaction بس من غير ما تتضاف
  -- فعليًا لرصيد محفظة platform (security-147).
  perform public.add_wallet_balance('platform', v_commission);

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'pcom-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    'platform', v_commission, 'commission', p_ride_id,
    'عمولة رحلة — ' || v_note_pct || '% من ' || coalesce(v_ride.fare, 0)::text || ' ج.م', now()
  );

  update public.rides set commission_settled = true where id::text = p_ride_id;

  return query select v_commission, v_earn, v_rate;
end;
$$;

create or replace function public.settle_order_commission(
  p_order_id     text,
  p_driver_phone text
)
returns table(commission numeric, driver_earn numeric, rate numeric)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order      public.orders%rowtype;
  v_rate_raw   text;
  v_rate       numeric;
  v_commission numeric;
  v_earn       numeric;
  v_note_pct   text;
begin
  if p_driver_phone is null or length(trim(p_driver_phone)) = 0 then
    raise exception 'driver_phone_required';
  end if;

  select * into v_order from public.orders where id::text = p_order_id for update;
  if not found then
    raise exception 'order_not_found';
  end if;

  if v_order.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_order';
  end if;

  if v_order.status <> 'delivered' then
    raise exception 'order_not_delivered';
  end if;

  if v_order.commission_settled then
    select abs(amount) into v_commission
      from public.wallet_transactions
      where reference_id = p_order_id and type = 'commission'
      order by created_at desc limit 1;
    select amount into v_earn
      from public.wallet_transactions
      where reference_id = p_order_id and type = 'earning'
      order by created_at desc limit 1;
    return query select coalesce(v_commission, 0), coalesce(v_earn, 0), 0::numeric;
    return;
  end if;

  select value into v_rate_raw from public.app_settings where key = 'commission_delivery';
  v_rate := nullif(v_rate_raw, '')::numeric;
  if v_rate is null or v_rate < 0 or v_rate >= 100 then
    v_rate := 15;
  end if;

  v_commission := round(coalesce(v_order.delivery_fee, 0) * v_rate / 100);
  v_earn       := coalesce(v_order.delivery_fee, 0) - v_commission;
  v_note_pct   := round(v_rate)::text;

  perform public.add_wallet_balance(p_driver_phone, v_earn);

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'wtx-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    p_driver_phone, v_earn, 'earning', p_order_id,
    'أرباح توصيل — بعد خصم العمولة ' || v_note_pct || '%', now()
  );

  perform public.add_wallet_balance('platform', v_commission);

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'pcom-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    'platform', v_commission, 'commission', p_order_id,
    'عمولة توصيل — ' || v_note_pct || '% من ' || coalesce(v_order.delivery_fee, 0)::text || ' ج.م', now()
  );

  update public.orders set commission_settled = true where id::text = p_order_id;

  return query select v_commission, v_earn, v_rate;
end;
$$;

grant execute on function public.settle_ride_commission(text, text)  to anon, authenticated;
grant execute on function public.settle_order_commission(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- (ب) تصحيح لمرة واحدة بس — يسوّي الفجوة التاريخية. id ثابت يمنع
--     التكرار لو الملف اتشغّل تاني.
-- ---------------------------------------------------------------------
do $$
declare
  v_fix_id text := 'reconcile-fix-security147-platform-commission-backfill';
  v_gap numeric;
begin
  if exists (select 1 from public.wallet_transactions where id = v_fix_id) then
    return; -- already applied
  end if;

  select w.balance - coalesce(t.sum_amount, 0)
    into v_gap
    from public.wallets w
    left join (select phone, sum(amount) as sum_amount from public.wallet_transactions group by phone) t
      on t.phone = w.phone
   where w.phone = 'platform';

  if v_gap is null or v_gap = 0 then
    return; -- nothing to fix (gap already closed or no platform wallet row)
  end if;

  perform public.add_wallet_balance('platform', -v_gap);

  -- amount=0 عمدًا، مش -v_gap: الصفوف الـ110 الأصلية بتاعة type='commission'
  -- موجودة فعلاً في الدفتر وبتفسّر الفلوس دي تمامًا — سطر تصحيح بمبلغ
  -- حقيقي هنا هيكرر نفس المبلغ في المجموع (balance يتصحّح، لكن tx_sum
  -- يزيد بنفس القيمة كمان، فالفجوة تفضل موجودة من غير ما تقفل أبدًا).
  -- السطر ده بس للتوثيق (إمتى حصل التصحيح وليه)، من غير أي تأثير مالي.
  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    v_fix_id, 'platform', 0, 'reconciliation_correction', null,
    'تصحيح لمرة واحدة (بدون قيمة في الدفتر) — عمولات security-07 القديمة كانت متسجّلة في wallet_transactions فعلاً (110 صف = ' || v_gap::text || ' ج.م) من غير ما تتضاف لرصيد المحفظة؛ الرصيد اتصحّح ليطابق الدفتر الموجود، مفيش داعي لسطر تصحيح بقيمة حقيقية (security-147)',
    now()
  );
end $$;
