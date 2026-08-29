-- =====================================================================
--  وصّلها — Security #44: إغلاق ثغرة add_wallet_balance المفتوحة للجميع
--
--  اكتُشف أثناء مراجعة أمنية للباك إند: add_wallet_balance(phone, amount)
--  كانت SECURITY DEFINER ومُتاحة مباشرة لـ anon/authenticated بلا أي
--  تحقق من هوية المتصل — أي حد معاه الـ anon key (مُضمّن في كل تطبيقات
--  العميل) يقدر ينادي عليها مباشرة برقم أي حساب ومبلغ أي رقم (حتى سالب)
--  ويشحن/يفرّغ أي محفظة فورًا:
--    POST /rest/v1/rpc/add_wallet_balance {"p_phone":"<أي رقم>","p_amount":999999999}
--  ده أخطر ثغرة في المشروع — تلاعب كامل بالسجل المالي بلا أي حماية.
--
--  السبب: استُخدمت مباشرة من الكود نفسه في مكانين:
--    • admin.astro (شحن/خصم يدوي من لوحة الأدمن) — execAdminWalletOp()
--    • driver-dashboard.astro (تغذية محفظة التاجر بقيمة الطلب بعد التسليم)
--  فمكانش ممكن نقفلها من غير ما نستبدل الاستخدامين دول بدوال محكومة.
--
--  الحل في الملف ده:
--   1) admin_adjust_wallet — بديل محكوم لعملية الأدمن، يتحقق من باسورد
--      أدمن حقيقي (bcrypt) بنفس نمط grant_admin/admin_delete_account،
--      وهو اللي بيسجّل المعاملة ويعدّل الرصيد سوا (مش خطوتين منفصلتين).
--   2) settle_order_merchant_credit — بديل محكوم لتغذية محفظة التاجر،
--      بيتحقق إن الطلب فعلاً delivered ومسلَّم من نفس السائق المتصل،
--      وبيحسب قيمة الطلب من الداتابيز نفسها (مش من رقم جايّ من العميل)،
--      مع حارس idempotency يمنع التغذية المزدوجة لو اتنادت أكتر من مرة.
--   3) سحب صلاحية التنفيذ المباشر لـ add_wallet_balance من anon/authenticated
--      — تفضل شغالة زي ما هي من جوه أي دالة SECURITY DEFINER تانية (زي
--      settle_ride_commission/settle_order_commission) لأن فحص الصلاحيات
--      للنداء الداخلي بيتم كمالك الدالة مش كـ anon.
--
--  ملاحظة: لازم تحدّث الكود بعد تشغيل الملف ده (admin.astro +
--  driver-dashboard.astro) — موجود في نفس الكوميت.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) admin_adjust_wallet — شحن/خصم من لوحة الأدمن، محكوم بباسورد أدمن.
-- ---------------------------------------------------------------------
create or replace function public.admin_adjust_wallet(
  p_admin_phone text, p_admin_password text,
  p_phone text, p_amount numeric, p_type text, p_note text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_id text;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then return false; end if;
  if v_admin.password is null
     or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    return false;
  end if;

  if p_phone is null or length(trim(p_phone)) = 0 then return false; end if;
  if p_amount is null or p_amount = 0 then return false; end if;
  if p_type not in ('admin_credit', 'admin_debit') then return false; end if;
  if p_note is null or length(trim(p_note)) < 5 then return false; end if;

  v_id := 'adm-' || (case when p_type = 'admin_credit' then 'cr' else 'db' end)
          || '-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6);

  -- السجل أولاً، وبعدين تعديل الرصيد — نفس ترتيب execAdminWalletOp
  -- الأصلي، بس دلوقتي في معاملة واحدة ذرّية بدل خطوتين منفصلتين
  -- ممكن التانية تفشل والأولى تنجح.
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values (v_id, p_phone, p_amount, p_type, p_note, now());

  perform public.add_wallet_balance(p_phone, p_amount);

  return true;
end;
$$;

revoke all on function public.admin_adjust_wallet(text, text, text, numeric, text, text) from public;
grant execute on function public.admin_adjust_wallet(text, text, text, numeric, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) settle_order_merchant_credit — تغذية محفظة التاجر بقيمة الطلب،
--    بحساب سيرفر-سايد بالكامل + حارس تكرار.
-- ---------------------------------------------------------------------
alter table public.orders add column if not exists merchant_credited boolean not null default false;

create or replace function public.settle_order_merchant_credit(
  p_order_id     text,
  p_driver_phone text
)
returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order      public.orders%rowtype;
  v_owner      text;
  v_subtotal   numeric;
begin
  if p_driver_phone is null or length(trim(p_driver_phone)) = 0 then
    raise exception 'driver_phone_required';
  end if;

  select * into v_order from public.orders where id = p_order_id::uuid for update;
  if not found then raise exception 'order_not_found'; end if;

  if v_order.driver_phone is distinct from p_driver_phone then
    raise exception 'not_your_order';
  end if;
  if v_order.status <> 'delivered' then
    raise exception 'order_not_delivered';
  end if;

  -- تم التغذية قبل كده لنفس الطلب — مايتكررش (سواء اتنادت الدالة مرتين
  -- بالغلط أو حصل ريتراي من الشبكة).
  if v_order.merchant_credited then
    return 0;
  end if;

  if v_order.store_id is null then
    update public.orders set merchant_credited = true where id = v_order.id;
    return 0;
  end if;

  select owner_phone into v_owner from public.stores where id = v_order.store_id;
  if v_owner is null then
    update public.orders set merchant_credited = true where id = v_order.id;
    return 0;
  end if;

  v_subtotal := greatest(0, coalesce(v_order.subtotal, v_order.total, 0) - coalesce(v_order.delivery_fee, 0));

  if v_subtotal > 0 then
    perform public.add_wallet_balance(v_owner, v_subtotal);
    insert into public.wallet_transactions (id, phone, amount, type, reference_id, note, created_at)
    values (
      'wtx-mc-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text), 1, 6),
      v_owner, v_subtotal, 'earning', p_order_id,
      'أرباح طلب #' || coalesce(v_order.code, p_order_id), now()
    );
  end if;

  update public.orders set merchant_credited = true where id = v_order.id;

  return v_subtotal;
end;
$$;

grant execute on function public.settle_order_merchant_credit(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) wallet_transfer — لازم يتحقق إن اللي بيحوّل هو فعلاً صاحب الرقم
--    p_from (باسوورد حسابه)، مش أي حد يكتب أي رقم جوال. من غير التحقق
--    ده أي حد معاه الـ anon key يقدر يفرّغ محفظة أي حساب لحسابه هو.
-- ---------------------------------------------------------------------
drop function if exists public.wallet_transfer(text, text, numeric, text);
create or replace function public.wallet_transfer(
  p_from text, p_from_password text, p_to text, p_amount numeric, p_note text default null
) returns numeric
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_from_acct record;
  v_from_bal numeric;
  v_to_exists boolean;
  v_amt numeric := round(p_amount::numeric, 2);
  v_note text := coalesce(nullif(trim(p_note),''),'تحويل');
begin
  if v_amt is null or v_amt < 1 then raise exception 'amount_too_small'; end if;
  if p_from = p_to then raise exception 'same_account'; end if;

  -- صاحب p_from فعلاً — نفس فحص verify_login (bcrypt أو legacy plaintext).
  select * into v_from_acct from public.accounts where phone = p_from limit 1;
  if v_from_acct.phone is null
     or v_from_acct.password is null
     or (v_from_acct.password <> extensions.crypt(p_from_password, v_from_acct.password)
         and v_from_acct.password <> p_from_password) then
    raise exception 'invalid_credentials';
  end if;

  -- recipient must be a real account
  select exists(select 1 from public.accounts where phone = p_to) into v_to_exists;
  if not v_to_exists then raise exception 'recipient_not_found'; end if;

  select balance into v_from_bal from public.wallets where phone = p_from for update;
  if v_from_bal is null then v_from_bal := 0; end if;
  if v_amt > v_from_bal then raise exception 'insufficient_funds'; end if;

  update public.wallets set balance = balance - v_amt, updated_at = now() where phone = p_from;

  insert into public.wallets (phone, balance, updated_at)
  values (p_to, v_amt, now())
  on conflict (phone) do update set balance = public.wallets.balance + excluded.balance, updated_at = now();

  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-out-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_from, -v_amt, 'transfer_out', v_note || ' → ' || p_to, now());
  insert into public.wallet_transactions (id, phone, amount, type, note, created_at)
  values ('wtx-in-' || extract(epoch from now())::bigint || '-' || substr(md5(random()::text),1,5),
          p_to, v_amt, 'transfer_in', v_note || ' ← ' || p_from, now());

  return v_from_bal - v_amt;
end;
$$;

grant execute on function public.wallet_transfer(text, text, text, numeric, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) إقفال add_wallet_balance عن الاستدعاء المباشر بالـ anon key. تفضل
--    شغالة من جوّه أي دالة SECURITY DEFINER تانية زي settle_ride_commission
--    (النداء الداخلي بيتفحص كصلاحيات مالك الدالة، مش المتصل الأصلي).
-- ---------------------------------------------------------------------
-- Postgres grants EXECUTE to the PUBLIC pseudo-role automatically when a
-- function is created, and that PUBLIC grant applies to every role
-- (including anon/authenticated) independently of any per-role
-- revoke — so PUBLIC must be revoked explicitly too, or the function
-- stays fully callable via the API despite the line below it.
revoke execute on function public.add_wallet_balance(text, numeric) from public;
revoke execute on function public.add_wallet_balance(text, numeric) from anon, authenticated;

-- =====================================================================
--  Done. Quick self-test (optional):
--    Running `select public.add_wallet_balance('any', 5);` INSIDE the SQL
--    Editor still succeeds — the SQL Editor connects as the function's
--    owner, who always bypasses grants on their own objects. The revoke
--    only blocks the anon/authenticated ROLES used by PostgREST, so test
--    it from the REST API instead:
--      POST /rest/v1/rpc/add_wallet_balance {"p_phone":"any","p_amount":5}
--      with the anon apikey header ⇒ should now return 401/403 ✅
--    select public.wallet_transfer('<phone>', 'wrong-password', '<other>', 5, null);
--      -- ⇒ exception invalid_credentials ✅ (this one still works from the
--      SQL Editor since it's a plain logic check, not a grant)
-- =====================================================================
