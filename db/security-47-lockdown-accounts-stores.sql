-- =====================================================================
--  وصّلها — Security #47: قفل أعمدة خطيرة في accounts/stores عن التعديل المباشر
--
--  مراجعة أمنية موسّعة لقت إن accounts وstores مفتوحين بالكامل للـ
--  UPDATE المباشر (FOR ALL USING(true) WITH CHECK(true) من
--  security07rlslockdown.sql) — الـ RLS بيتحكم في الصفوف بس، مش
--  الأعمدة، فأي عمود مالوش قفل عمود صريح يفضل قابل للتعديل من anon.
--  ده فتح تلاتة ثغرات خطيرة:
--
--   1) PATCH /rest/v1/accounts?phone=eq.<نفس رقمك> {"status":"approved"}
--      — أي سائق/تاجر معلّق يقدر يعتمد نفسه فورًا، من غير أي مراجعة
--      إدارية (يلغي غرض security-15-driver-approval-gate بالكامل).
--   2) PATCH /rest/v1/accounts?phone=eq.<رقم ضحية> {"email":"attacker@x.com"}
--      ثم طلب "نسيت كلمة المرور" لنفس الرقم — الإيميل الجديد (بتاع
--      المهاجم) هو اللي يوصله الـ OTP، فيقدر يستولي على أي حساب.
--   3) PATCH /rest/v1/stores?id=eq.<أي متجر> {"owner_phone":"<رقمه>"}
--      — سرقة ملكية أي متجر، وبالتبعية أرباحه (settle_order_merchant_credit
--      بيثق في stores.owner_phone).
--
--  الحل: قفل الأعمدة الخطيرة دي تحديدًا بـ column-level REVOKE (مش قفل
--  الجدول كله — باقي الأعمدة اللي فعلاً بتتعدّل مباشرة من الكود الحالي
--  زي name/city/username/avatar_url وباقي بيانات المتجر تفضل شغالة زي
--  ما هي، من غير أي تعديل على الكود). password/role كانوا محميين
--  بالفعل (role بتريجر guard_account_privilege، password بمساره
--  الخاص عبر reset_password) لكن بنقفلهم كمان كطبقة حماية إضافية.
--
--  الإيميل بقى ليه دالة مخصصة (update_account_email) بتتحقق من كلمة
--  مرور الحساب قبل التغيير — لازم تحدّث الكود (profile.astro +
--  flutter account_repository.dart) بعد تشغيل الملف ده، موجود في نفس
--  الكوميت.
--
--  آمن لإعادة التشغيل. شغّله كاملاً مرة واحدة في SQL Editor.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) accounts — قفل status/role/password/email عن التعديل المباشر.
-- ---------------------------------------------------------------------
revoke update (status)   on public.accounts from anon, authenticated;
revoke update (role)     on public.accounts from anon, authenticated;
revoke update (password) on public.accounts from anon, authenticated;
revoke update (email)    on public.accounts from anon, authenticated;

create or replace function public.update_account_email(
  p_phone text, p_password text, p_new_email text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_acct record; v_rows int;
begin
  select * into v_acct from public.accounts where phone = p_phone limit 1;
  if v_acct.phone is null then return false; end if;
  if v_acct.password is null
     or (v_acct.password <> extensions.crypt(p_password, v_acct.password)
         and v_acct.password <> p_password) then
    return false;
  end if;

  perform set_config('app.privileged', 'on', true);
  update public.accounts set email = nullif(trim(p_new_email), '') where phone = p_phone;
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);

  return v_rows > 0;
end;
$$;

grant execute on function public.update_account_email(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 1b) لوحة الأدمن (admin.astro) بتغيّر status/role مباشرة لأي حساب —
--     changeUserStatus()/changeUserRole() — لازم يبقوا عبر دالة محمية
--     بباسورد الأدمن بعد قفل العمودين دول، زي باقي إجراءات الأدمن.
-- ---------------------------------------------------------------------
create or replace function public.admin_set_user_status(
  p_admin_phone text, p_admin_password text, p_target_phone text, p_status text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_rows int;
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

  perform set_config('app.privileged', 'on', true);
  update public.accounts set status = p_status where phone = p_target_phone;
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;
grant execute on function public.admin_set_user_status(text, text, text, text) to anon, authenticated;

-- p_role is never allowed to be 'admin' here — promoting to admin stays
-- exclusively behind grant_admin (extra action-key confirmation on top
-- of the admin password, since it's the most sensitive privilege change).
create or replace function public.admin_set_user_role(
  p_admin_phone text, p_admin_password text, p_target_phone text, p_role text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_rows int;
begin
  if p_role = 'admin' then
    raise exception 'use_grant_admin_instead';
  end if;

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

  perform set_config('app.privileged', 'on', true);
  update public.accounts
     set role = p_role, status = case when p_role = 'driver' then 'approved' else status end
   where phone = p_target_phone;
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;
grant execute on function public.admin_set_user_role(text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) stores — قفل owner_phone عن التعديل المباشر (مفيش أي مسار حالي في
--    الكود بيعدّله مباشرة، فمفيش أي كسر متوقع).
-- ---------------------------------------------------------------------
revoke update (owner_phone) on public.stores from anon, authenticated;

-- =====================================================================
--  Done. Quick self-test (from the REST API with the anon key):
--    PATCH /rest/v1/accounts?phone=eq.<any> {"status":"approved"}
--      ⇒ 403/column privilege error ✅ (previously would have succeeded)
--    PATCH /rest/v1/stores?id=eq.<any> {"owner_phone":"<any>"}
--      ⇒ 403/column privilege error ✅
-- =====================================================================
