-- =====================================================================
--  وصّلها — مفتاح أمان ثانٍ منفصل عن كلمة مرور تسجيل الدخول، مطلوب لأي
--  إجراء خطر (حذف حساب، ترقية/إنشاء أدمن) — بيتطلب في كل مرة، بلا حفظ.
--
--  ⚠️ قبل التشغيل: غيّر 'AdminEG2310' في آخر الملف لمفتاح الأمان اللي
--  عايز تستخدمه أنت (نص عادي، أي طول). ده هو المفتاح اللي هتدخله في
--  المتصفح عند أي عملية حذف/ترقية — منفصل تمامًا عن باسورد حسابك.
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل (تغيير
--  المفتاح لاحقًا: عدّل السطر الأخير وشغّله تاني بس).
-- =====================================================================
set search_path = public, extensions;

-- 1) دالة التحقق من مفتاح الأمان (مقارنة bcrypt، مش نص صريح)
create or replace function public.verify_action_key(p_key text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_hash text;
begin
  select value into v_hash from public.app_settings where key = 'action_security_key';
  if v_hash is null or p_key is null then return false; end if;
  return v_hash = extensions.crypt(p_key, v_hash);
end;
$$;

-- 2) admin_delete_account — يتطلب الآن مفتاح الأمان بالإضافة لباسورد الأدمن
drop function if exists public.admin_delete_account(text, text, text);
create or replace function public.admin_delete_account(
  p_admin_phone text, p_admin_password text, p_target_phone text, p_action_key text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin  record;
  v_local  text;
  v_intl   text;
  v_rows   int;
begin
  if not public.verify_action_key(p_action_key) then return false; end if;

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

  v_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_intl  := case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end;

  delete from public.driver_applications  where phone         in (v_local, v_intl);
  delete from public.merchant_applications where phone        in (v_local, v_intl);
  delete from public.driver_locations     where driver_phone  in (v_local, v_intl);
  delete from public.wallet_transactions  where phone         in (v_local, v_intl);
  delete from public.rides                where driver_phone  in (v_local, v_intl);
  delete from public.rides                where customer_phone in (v_local, v_intl);
  delete from public.orders               where customer_phone in (v_local, v_intl);
  delete from public.points               where phone         in (v_local, v_intl);
  delete from public.point_transactions   where phone         in (v_local, v_intl);
  delete from public.wallets              where phone         in (v_local, v_intl);
  delete from public.push_subscriptions   where phone         in (v_local, v_intl);

  perform set_config('app.privileged', 'on', true);
  delete from public.accounts where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);

  return v_rows > 0;
end;
$$;
grant execute on function public.admin_delete_account(text, text, text, text) to anon, authenticated;

-- 3) grant_admin — يتطلب الآن مفتاح الأمان أيضًا
drop function if exists public.grant_admin(text, text, text);
create or replace function public.grant_admin(
  p_admin_phone text, p_admin_password text, p_target_phone text, p_action_key text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record; v_local text; v_intl text; v_rows int;
begin
  if not public.verify_action_key(p_action_key) then return false; end if;

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

  v_local := case when p_target_phone like '+20%' then '0'||substr(p_target_phone,4) else p_target_phone end;
  v_intl  := case when p_target_phone like '0%'   then '+2'||p_target_phone           else p_target_phone end;

  perform set_config('app.privileged', 'on', true);
  update public.accounts set role = 'admin', status = 'active' where phone in (v_local, v_intl);
  get diagnostics v_rows = row_count;
  perform set_config('app.privileged', 'off', true);
  return v_rows > 0;
end;
$$;
grant execute on function public.grant_admin(text, text, text, text) to anon, authenticated;

-- 4) create_admin — يتطلب الآن مفتاح الأمان أيضًا
drop function if exists public.create_admin(text, text, text, text, text);
create or replace function public.create_admin(
  p_admin_phone text, p_admin_password text, p_name text, p_phone text, p_password text, p_action_key text
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  if not public.verify_action_key(p_action_key) then return false; end if;

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
  insert into public.accounts (phone, name, password, role, status, created_at)
  values (p_phone, p_name, p_password, 'admin', 'active', now());
  perform set_config('app.privileged', 'off', true);
  return true;
end;
$$;
grant execute on function public.create_admin(text, text, text, text, text, text) to anon, authenticated;

-- 5) اضبط مفتاح الأمان — غيّر النص ده لمفتاحك الخاص قبل التشغيل!
insert into public.app_settings (key, value, updated_at)
values ('action_security_key', extensions.crypt('__CHANGE_ME__', extensions.gen_salt('bf')), now())
on conflict (key) do update set value = excluded.value, updated_at = now();
