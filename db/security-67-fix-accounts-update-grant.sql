-- =====================================================================
--  وصّلها — Security #67: تصحيح فشل تحديث accounts (رفع الصورة/تعديل البيانات)
--
--  UPDATE public.accounts SET avatar_url=... WHERE phone=... كان بيفشل
--  دايمًا بـ "permission denied for table accounts" — مش مشكلة في
--  الكاميرا زي ما اتقال في البداية. السبب: تحديث Postgres لأي عمود
--  بشرط WHERE على عمود تاني (هنا phone) محتاج صلاحية SELECT على عمود
--  الـ WHERE ده كمان، مش بس UPDATE على العمود المتغيّر — وaccounts
--  مالهاش أي GRANT SELECT لـ anon/authenticated على أي عمود خالص
--  (قصدًا، لمنع قراءة الحسابات مباشرة — accounts.astro بيستخدم
--  lookup_account RPC بدل ما يعمل SELECT مباشر). النتيجة كانت إن رفع
--  صورة البروفايل و"تعديل بياناتي" الاتنين كانوا بيفشلوا بصمت من
--  الأول، مش حاجة جديدة سببها إضافة خيار الكاميرا.
--
--  الحل: دالتين security definer بيتعدّى بيهم قيد الصلاحيات ده، زي
--  update_account_email الموجودة بالفعل (security-47) بالظبط.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.update_account_avatar(
  p_phone text, p_avatar_url text
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  update public.accounts set avatar_url = p_avatar_url where phone = p_phone;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

grant execute on function public.update_account_avatar(text, text) to anon, authenticated;

create or replace function public.update_account_profile(
  p_phone text, p_name text default null, p_city text default null, p_username text default null
) returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_rows int;
begin
  update public.accounts set
    name = coalesce(p_name, name),
    city = coalesce(p_city, city),
    username = coalesce(p_username, username)
  where phone = p_phone;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

grant execute on function public.update_account_profile(text, text, text, text) to anon, authenticated;
