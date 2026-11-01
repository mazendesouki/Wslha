-- =====================================================================
--  وصّلها — Security #154: تصحيح باگين حقيقيين في "صافي ربح المنصة"
--  وسحب الأرباح
--
--  اتكشفوا وقت مراجعة "قواعد عمليات سحب الأرباح والربط الشامل بينها":
--
--  1) get_platform_finance_summary كانت بتصنّف العمولة حسب نص الملاحظة
--     (note ilike '%رحلة%'/'%توصيل%'/'%مطار%') بدل ما تربط فعليًا
--     بمصدر العملية. المشكلة: settle_ride_commission (security-07)
--     بيكتب "عمولة رحلة — X% من Y ج.م" لكل أنواع الرحلات (محلية/
--     خارجية/مطار) من غير ما يذكر كلمة "مطار" خالص — فبند "✈️ عمولة
--     مطار" في اللوحة كان بيطلع 0 ج.م دايمًا، رغم وجود 17 عملية عمولة
--     رحلات مطار حقيقية ومسجّلة فعلاً (اتأكد ده بفحص مباشر على
--     البيانات الحية). الحل: الربط بمصدر العملية فعليًا
--     (wallet_transactions.reference_id → rides.ride_type /
--     orders.id) بدل تخمين النوع من نص حر.
--
--  2) admin_withdraw_platform_profit كانت بتسجّل عملية السحب في
--     wallet_transactions بس (عشان "صافي الربح" المحسوب من دفتر
--     الحركات يتظبط)، لكن من غير ما تنقص فعليًا من رصيد محفظة
--     'platform' (wallets.balance) — نفس فئة باگ security-147 بالظبط
--     (بس في الاتجاه المعاكس: هناك كانت العمولة بتتسجّل من غير ما
--     تتضاف للرصيد، وهنا السحب بيتسجّل من غير ما يتخصم من الرصيد).
--     لو السحب ده اتسيب من غير تصحيح، كل عملية سحب جديدة كانت هتخلّي
--     wallets.balance زيادة عن الحقيقة بمقدار المبلغ المسحوب — ومطابقة
--     المحفظة اليومية (security-148) كانت هتمسكها بعد كده على أي حال،
--     لكن الأصح نصلّحها من المصدر.
--
--  نفس شكل/باراميترات الدالتين بالظبط (CREATE OR REPLACE آمن، مفيش
--  تغيير في التوقيع ولا خطر overload).
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) get_platform_finance_summary — تصنيف حسب المصدر الفعلي، مش نص حر.
-- ---------------------------------------------------------------------
create or replace function public.get_platform_finance_summary(p_admin_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_is_admin boolean;
  v_total_revenue numeric;
  v_total_withdrawn numeric;
  v_ride numeric; v_deliv numeric; v_air numeric;
begin
  select exists(
    select 1 from public.accounts
     where role = 'admin'
       and phone in (p_admin_phone,
                     case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                     case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
  ) into v_is_admin;
  if not v_is_admin then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select coalesce(sum(amount), 0) into v_total_revenue
    from public.wallet_transactions where phone = 'platform' and type = 'commission';
  select coalesce(sum(-amount), 0) into v_total_withdrawn
    from public.wallet_transactions where phone = 'platform' and type = 'withdrawal';

  -- ربط فعلي بمصدر العملية بدل تخمين النوع من نص الملاحظة الحر —
  -- عمولة رحلة مطار كانت بتتسجّل بنفس نص عمولة أي رحلة تانية
  -- (security-07 ما كانتش بتفرّق في نص الملاحظة نفسه).
  select coalesce(sum(wt.amount), 0) into v_ride
    from public.wallet_transactions wt
    join public.rides r on r.id::text = wt.reference_id
   where wt.phone = 'platform' and wt.type = 'commission'
     and coalesce(r.ride_type, 'local') <> 'airport';

  select coalesce(sum(wt.amount), 0) into v_air
    from public.wallet_transactions wt
    join public.rides r on r.id::text = wt.reference_id
   where wt.phone = 'platform' and wt.type = 'commission'
     and r.ride_type = 'airport';

  select coalesce(sum(wt.amount), 0) into v_deliv
    from public.wallet_transactions wt
    join public.orders o on o.id::text = wt.reference_id
   where wt.phone = 'platform' and wt.type = 'commission';

  return jsonb_build_object(
    'total_revenue',   v_total_revenue,
    'total_withdrawn', v_total_withdrawn,
    'balance',          v_total_revenue - v_total_withdrawn,
    'by_type', jsonb_build_object('ride', v_ride, 'delivery', v_deliv, 'airport', v_air)
  );
end;
$$;
grant execute on function public.get_platform_finance_summary(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) admin_withdraw_platform_profit — تخصم فعليًا من رصيد المحفظة.
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

  -- كانت ناقصة: السحب كان بيتسجّل في wallet_transactions بس من غير ما
  -- يتخصم فعليًا من wallets.balance (security-154).
  perform public.add_wallet_balance('platform', -p_amount);

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_id, 'platform', -p_amount, 'withdrawal', coalesce(p_note, 'سحب أرباح المنصة — ' || v_admin.name), now());

  insert into public.platform_withdrawals (id, admin_phone, admin_name, amount, note, balance_before, balance_after)
  values (v_id, v_admin.phone, v_admin.name, p_amount, p_note, v_balance, v_balance - p_amount);

  return jsonb_build_object('ok', true, 'balance_after', v_balance - p_amount);
end;
$$;
grant execute on function public.admin_withdraw_platform_profit(text, text, text, numeric, text) to anon, authenticated;
