-- =====================================================================
--  وصّلها — Security #91: عدد السائقين المتاحين الآن (بدون كشف بيانات)
--
--  الهدف: بطاقة "حالة حية" في شاشة الرحلات (طلب المستخدم بعد تجربة
--  خيار "ب" من تصميم الهوية البصرية) — تعرض عدد السائقين المتاحين
--  فعليًا الآن، رقم حقيقي من قاعدة البيانات مش تقديري.
--
--  ملاحظة أمنية جانبية: anon كان أصلاً عنده SELECT مباشر على
--  driver_locations (بما فيها driver_phone/driver_name/lat/lng — بيانات
--  حساسة). الدالة دي بترجع رقم إجمالي بس (count)، من غير كشف أي صف خام،
--  اتباعًا لنفس نمط الدوال الضيقة (narrow RPC) المتبع في باقي المشروع،
--  بدل الاعتماد على SELECT المباشر المفتوح أصلاً.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.get_available_drivers_count()
returns integer
language sql
stable
security definer
set search_path = public, extensions
as $$
  select count(*)::integer
  from public.driver_locations
  where is_online = true
    and ride_id is null
    and current_order_id is null
    and updated_at > now() - interval '10 minutes';
$$;
grant execute on function public.get_available_drivers_count() to anon, authenticated;
