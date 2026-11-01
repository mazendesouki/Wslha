-- =====================================================================
--  وصّلها — Security #155: بث لحظي (Realtime) لتحديث "صافي ربح المنصة"
--  فور تسوية أي عمولة أو سحب أرباح — بدون كشف أي بيانات حساسة.
--
--  الطلب: تحديث فوري للوحة الأدمن فور اكتمال أي رحلة/طلب توصيل (أي
--  نشاط يولّد عمولة منصة)، بدل الاعتماد فقط على التحديث الدوري كل 30
--  ثانية. الحل الآمن: استخدام realtime.send() (بث Supabase الرسمي) —
--  مش الاشتراك في postgres_changes على wallet_transactions مباشرة،
--  لأن الجدول ده اتقفل عمدًا في security-124 (revoke all from anon/
--  authenticated) بعد ما كان بيسرّب سجل معاملات كل المستخدمين بدون
--  فلتر. البث هنا بيحمل إشارة فاضية بس ("في تحديث") من غير أي أرقام
--  أو بيانات شخصية، فمفيش داعي لإعادة فتح الجدول ولا لصلاحيات RLS
--  إضافية — العميل (لوحة الأدمن) بياخد الإشارة ويعيد تحميل الأرقام من
--  get_platform_finance_summary المحمية بكلمة مرور الأدمن زي العادة.
--
--  نفس شكل/باراميترات الدوال التلاتة بالظبط (CREATE OR REPLACE آمن):
--  settle_ride_commission، settle_order_commission (إضافة سطر بث واحد
--  فور تسجيل عمولة المنصة)، admin_withdraw_platform_profit (إضافة سطر
--  بث واحد فور تسجيل السحب — جسم الدالة هنا هو نفسه بعد تصحيح
--  security-154 زائد سطر البث فقط).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) settle_ride_commission
-- ---------------------------------------------------------------------
create or replace function public.settle_ride_commission(p_ride_id text, p_driver_phone text)
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

  perform public.add_wallet_balance('platform', v_commission);

  insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
  values (
    'pcom-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
    'platform', v_commission, 'commission', p_ride_id,
    'عمولة رحلة — ' || v_note_pct || '% من ' || coalesce(v_ride.fare, 0)::text || ' ج.م', now()
  );

  -- بث لحظي فاضٍ (بدون مبالغ ولا بيانات شخصية) — security-155.
  perform realtime.send(jsonb_build_object('source', 'ride'), 'update', 'platform-finance', false);

  update public.rides set commission_settled = true where id::text = p_ride_id;

  return query select v_commission, v_earn, v_rate;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) settle_order_commission
-- ---------------------------------------------------------------------
create or replace function public.settle_order_commission(p_order_id text, p_driver_phone text)
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

  -- بث لحظي فاضٍ (بدون مبالغ ولا بيانات شخصية) — security-155.
  perform realtime.send(jsonb_build_object('source', 'order'), 'update', 'platform-finance', false);

  update public.orders set commission_settled = true where id::text = p_order_id;

  return query select v_commission, v_earn, v_rate;
end;
$$;

-- ---------------------------------------------------------------------
-- 3) admin_withdraw_platform_profit — جسم security-154 + سطر بث واحد.
-- ---------------------------------------------------------------------
create or replace function public.admin_withdraw_platform_profit(
  p_admin_phone text, p_admin_password text, p_action_key text,
  p_amount numeric, p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin record;
  v_balance numeric;
  v_id text;
begin
  if not public.verify_action_key(p_action_key) then
    raise exception 'مفتاح الأمان غير صحيح' using errcode = '28000';
  end if;

  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;

  if v_admin.phone is null or v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'كلمة مرور المشرف غير صحيحة' using errcode = '28000';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'المبلغ غير صالح';
  end if;

  select coalesce(sum(case when type = 'commission' then amount when type = 'withdrawal' then amount else 0 end), 0)
    into v_balance
    from public.wallet_transactions where phone = 'platform' and type in ('commission', 'withdrawal');

  if p_amount > v_balance then
    raise exception 'المبلغ المطلوب أكبر من الرصيد المتاح (%.2f ج.م)', v_balance;
  end if;

  v_id := 'plat-wd-' || extract(epoch from clock_timestamp())::bigint || '-' || substr(md5(random()::text), 1, 6);

  perform public.add_wallet_balance('platform', -p_amount);

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_id, 'platform', -p_amount, 'withdrawal', coalesce(p_note, 'سحب أرباح المنصة — ' || v_admin.name), now());

  insert into public.platform_withdrawals (id, admin_phone, admin_name, amount, note, balance_before, balance_after)
  values (v_id, v_admin.phone, v_admin.name, p_amount, p_note, v_balance, v_balance - p_amount);

  -- بث لحظي فاضٍ (بدون مبالغ ولا بيانات شخصية) — security-155.
  perform realtime.send(jsonb_build_object('source', 'withdrawal'), 'update', 'platform-finance', false);

  return jsonb_build_object('ok', true, 'balance_after', v_balance - p_amount);
end;
$$;
grant execute on function public.admin_withdraw_platform_profit(text, text, text, numeric, text) to anon, authenticated;
grant execute on function public.settle_ride_commission(text, text) to anon, authenticated;
grant execute on function public.settle_order_commission(text, text) to anon, authenticated;
