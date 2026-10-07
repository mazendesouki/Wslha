-- =====================================================================
--  وصّلها — Security #114: دالة تنظيف حسابات اختبار التحميل فقط
--
--  اختبار تحميل التسجيل (load-test-register.yml) بقى شغّال بعد إصلاح
--  security-113، لكن خطوة التنظيف فشلت: anon عنده INSERT بس على
--  accounts (بعد الإصلاح) — من غير SELECT أو DELETE، فمقدرش يحذف
--  الحسابات اللي سجّلها هو نفسه.
--
--  الحل: دالة SECURITY DEFINER محصورة جدًا — تحذف فقط صفوف من
--  accounts بشرط صريح ومكتوب في جسم الدالة نفسها (مش بارامتر):
--  phone like '01590000%' AND name like 'LOADTEST_%' — نفس العلامة
--  اللي اختبار التحميل بيستخدمها، مش قابلة للتغيير من الخارج، فمينفعش
--  تُستخدم لحذف أي حساب حقيقي.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.cleanup_loadtest_accounts()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_count integer;
begin
  delete from public.accounts
  where phone like '01590000%' and name like 'LOADTEST\_%';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.cleanup_loadtest_accounts() to anon, authenticated;
