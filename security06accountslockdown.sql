-- =====================================================================
--  وصّلها — Security #6: إغلاق تسريب بيانات الحسابات الجماعي
--
--  الثغرة: جدول accounts كان قابلاً للقراءة الجماعية الكاملة عبر مفتاح
--  anon العام (الظاهر في كود الموقع لأي زائر) — أي طلب مثل:
--    GET /rest/v1/accounts?select=phone,name,email,username
--  كان يُرجع كل أرقام هواتف وأسماء وبريد كل المستخدمين المسجّلين دفعة واحدة.
--
--  الحل: قفل القراءة المباشرة نهائياً، واستبدالها بدوال ضيّقة:
--    • lookup_account: صف واحد بمطابقة رقم هاتف حصرية (لا قوائم)
--    • check_field_availability: فحص توفّر (بدون إرجاع بيانات)
--    • assign_random_driver_to_ride: يُرجع سائقاً واحداً فقط للعميل
--      (بدل كشف كل قائمة السائقين له كما كان يحدث)
--    • admin_list_accounts: القائمة الكاملة، بكلمة مرور مشرف فقط
--
--  ⚠️ يجب نشر تعديلات الكود المرفقة معه في نفس الدفعة — وإلا ستتعطّل كل
--  صفحة تقرأ accounts مباشرة (تسجيل الدخول، الملف الشخصي، لوحة الأدمن...).
--
--  شغّله كاملاً مرة واحدة في SQL Editor. آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

-- ---------------------------------------------------------------------
-- 1) lookup_account — صف واحد فقط بمطابقة رقم هاتف حصرية
-- ---------------------------------------------------------------------
create or replace function public.lookup_account(p_phone text)
returns table(
  id uuid, phone text, name text, role text, city text,
  email text, username text, status text, created_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select a.id, a.phone, a.name, a.role, a.city, a.email, a.username, a.status, a.created_at
  from public.accounts a
  where a.phone in (
    p_phone,
    case when p_phone like '+20%' then '0'||substr(p_phone,4) else p_phone end,
    case when p_phone like '0%'   then '+2'||p_phone           else p_phone end
  )
  limit 1;
$$;
grant execute on function public.lookup_account(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) check_field_availability — فحص توفّر بلا إرجاع أي بيانات
-- ---------------------------------------------------------------------
create or replace function public.check_field_availability(p_field text, p_value text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare v_exists boolean;
begin
  if p_field = 'phone' then
    select exists(select 1 from public.accounts where phone = p_value) into v_exists;
  elsif p_field = 'email' then
    select exists(select 1 from public.accounts where email ilike p_value) into v_exists;
  elsif p_field = 'username' then
    select exists(select 1 from public.accounts where username ilike p_value) into v_exists;
  else
    raise exception 'bad_field';
  end if;
  return v_exists;
end;
$$;
grant execute on function public.check_field_availability(text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 3) assign_random_driver_to_ride — يُعيد سائقاً واحداً فقط (وليس القائمة)
--    ويُسند الرحلة له ذرّياً على الخادم
-- ---------------------------------------------------------------------
create or replace function public.assign_random_driver_to_ride(p_ride_id text)
returns table(driver_name text, driver_phone text)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_driver record;
begin
  select a.name, a.phone into v_driver
  from public.accounts a
  where a.role = 'driver' and a.status in ('active','approved')
  order by random()
  limit 1;

  if v_driver.phone is null then
    return; -- لا يوجد سائقون متاحون
  end if;

  update public.rides
     set driver_name = v_driver.name, driver_phone = v_driver.phone, status = 'accepted'
   where id = p_ride_id;

  driver_name  := v_driver.name;
  driver_phone := v_driver.phone;
  return next;
end;
$$;
grant execute on function public.assign_random_driver_to_ride(text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) admin_list_accounts — القائمة الكاملة، بكلمة مرور مشرف موثّق فقط
-- ---------------------------------------------------------------------
create or replace function public.admin_list_accounts(
  p_admin_phone text, p_admin_password text, p_role text default null
) returns table(
  id uuid, phone text, name text, role text, city text,
  email text, username text, status text, created_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_admin record;
begin
  select * into v_admin from public.accounts
   where role = 'admin'
     and phone in (p_admin_phone,
                   case when p_admin_phone like '+20%' then '0'||substr(p_admin_phone,4) else p_admin_phone end,
                   case when p_admin_phone like '0%'   then '+2'||p_admin_phone           else p_admin_phone end)
   limit 1;
  if v_admin.phone is null then raise exception 'not_admin'; end if;
  if v_admin.password is null or v_admin.password <> extensions.crypt(p_admin_password, v_admin.password) then
    raise exception 'bad_password';
  end if;

  return query
    select a.id, a.phone, a.name, a.role, a.city, a.email, a.username, a.status, a.created_at
    from public.accounts a
    where p_role is null or a.role = p_role
    order by a.created_at desc
    limit 2000;
end;
$$;
grant execute on function public.admin_list_accounts(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) القفل النهائي: منع القراءة المباشرة لجدول accounts بالكامل
-- ---------------------------------------------------------------------
revoke select on public.accounts from anon, authenticated;

-- =====================================================================
--  اختبار (يجب أن يفشل — يغلق التسريب):
--    GET /rest/v1/accounts?select=phone,name,email  → permission denied
--  اختبار (يجب أن ينجح):
--    select * from public.lookup_account('01102667324');
-- =====================================================================
