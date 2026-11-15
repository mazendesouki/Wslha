-- =====================================================================
--  وصّلها — Security #183: كراش إنهاء الرحلة بسبب نقط الولاء
--
--  البلاغ: سائق بلّغ إن إنهاء الرحلة بيطلع PostgrestException ويوقف
--  العملية: "insert or update on table point_transactions violates
--  foreign key constraint point_transactions_phone_fkey ... Key is not
--  present in table accounts".
--
--  السبب: _award_loyalty_points() (security-110) تريجر بيشتغل بعد أي
--  UPDATE على rides/orders، وبيحاول يسجّل نقط لـ new.customer_phone
--  مباشرة من غير ما يتأكد إن الرقم ده أصلاً عنده حساب في accounts —
--  وpoint_transactions.phone عليه FK حقيقي على accounts(phone)
--  (اتضاف في security-89). لو الرقم مش موجود (رحلة تجريبية، رقم ضيف،
--  أو حساب اتمسح بعد الرحلة) الـ insert بيفشل، والتريجر بيشتغل جوه نفس
--  transaction بتاع تحديث rides/orders، فالـ UPDATE كله (تأكيد إنهاء
--  الرحلة) بيترجع فاشل مع العميل.
--
--  تأكيد مباشر من قاعدة البيانات الحية: 5 صفوف في rides حاليًا
--  customer_phone فيها مالوش حساب في accounts (من ضمنها الرحلة اللي
--  البلاغ ده جه منها — رقم تجريبي 01099999944).
--
--  الإصلاح على مستويين، زي نمط get_my_points_balance نفسه:
--   1) قبل أي insert، نتأكد إن الرقم (أو نسخته المحلية/الدولية) فعلاً
--      له حساب في accounts؛ لو مفيش، نتجاهل الكسب بهدوء (مفيش حساب =
--      مفيش رصيد نقط ممكن أصلاً).
--   2) حماية إضافية: الجزء اللي بيكتب في point_transactions/points
--      ملفوف في EXCEPTION WHEN OTHERS — أي مشكلة تانية مستقبلية في
--      الميزة دي (اختيارية وجانبية) متقدرش تمنع إنهاء رحلة أو توصيل
--      طلب تاني أبدًا.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public._award_loyalty_points()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_enabled text;
  v_rate numeric;
  v_amount numeric;
  v_phone text;
  v_id text;
  v_points int;
  v_inserted text;
begin
  select value into v_enabled from public.app_settings where key = 'feature_loyalty_enabled';
  if coalesce(v_enabled, 'true') <> 'true' then return new; end if;

  if tg_table_name = 'rides' then
    if new.status <> 'completed' or old.status = 'completed' then return new; end if;
    v_amount := new.fare;
    v_phone := new.customer_phone;
    v_id := 'pts-ride-' || new.id;
  elsif tg_table_name = 'orders' then
    if new.status <> 'delivered' or old.status = 'delivered' then return new; end if;
    v_amount := new.total;
    v_phone := new.customer_phone;
    v_id := 'pts-order-' || new.id;
  else
    return new;
  end if;

  if v_phone is null or coalesce(v_amount, 0) <= 0 then return new; end if;

  -- point_transactions.phone has a real FK to accounts(phone) — resolve
  -- to whichever stored format (as-is / local 0xxxxxxxxxx / intl
  -- +20xxxxxxxxxx) actually has an account, same lookup convention as
  -- get_my_points_balance/list_my_point_transactions below. No match at
  -- all (test ride, guest phone, deleted account) means there is no
  -- points balance to credit — skip quietly instead of inserting a
  -- phone with no account and blowing up the FK.
  select phone into v_phone from public.accounts
   where phone in (v_phone,
                   case when v_phone like '+20%' then '0'||substr(v_phone,4) else v_phone end,
                   case when v_phone like '0%'   then '+2'||v_phone           else v_phone end)
   limit 1;
  if v_phone is null then return new; end if;

  v_rate := public._pricing_setting_num('loyalty_earn_rate', 0.1, 0);
  v_points := floor(v_amount * v_rate)::int;
  if v_points <= 0 then return new; end if;

  -- Belt-and-suspenders: this is a side-effect, optional feature riding
  -- on the same transaction as the actual ride/order completion update.
  -- It must never be able to fail that update again, for any reason.
  begin
    insert into public.point_transactions (id, phone, points, type, reference_id, created_at)
    values (v_id, v_phone, v_points, 'earned', (case when tg_table_name = 'rides' then new.id else new.id end)::text, now())
    on conflict (id) do nothing
    returning id into v_inserted;

    if v_inserted is not null then
      perform public.add_points_balance(v_phone, v_points);
    end if;
  exception when others then
    null;
  end;

  return new;
end;
$$;
