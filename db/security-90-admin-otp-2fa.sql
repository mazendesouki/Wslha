-- =====================================================================
--  وصّلها — Security #90: طبقة حماية إضافية (OTP بالبريد) للوحة التحكم
--
--  الهدف: تجربة OTP كطبقة تحقق إضافية فوق كلمة مرور المشرف — في مكانين:
--    (أ) تسجيل الدخول للوحة التحكم (admin-login.astro) — بعد كلمة المرور
--        مباشرة، قبل ما تتفتح اللوحة.
--    (ب) حذف مستخدم من لوحة التحكم (admin.astro → deleteUser) — بعد كلمة
--        المرور ومفتاح الحماية، قبل تنفيذ admin_delete_account.
--
--  البنية التحتية جاهزة بالفعل من قبل (مفيش داعي لأي Twilio/SMS جديد):
--    • جدول otps (phone, code, expires_at, used) موجود ومؤمّن (لا يقرأه anon مباشرة).
--    • edge function "swift-processor" (كودها request-password-reset) بترسل
--      كود 6 أرقام لبريد الحساب المسجّل عبر Resend، وتخزّنه في otps.
--    • دالة reset_password() بتتحقق من الكود بنفس المنطق، لكنها بتغيّر كلمة
--      المرور كمان — مش مناسبة هنا لأننا عايزين تحقق فقط بدون أي أثر جانبي.
--
--  الجديد هنا: verify_otp_code() — نفس منطق التحقق بالظبط (نفس الشروط:
--  غير مستخدم + لسه صالح + أحدث كود) لكن من غير أي تعديل على accounts —
--  تحقق فقط، تُستخدم لأي غرض 2FA مستقبلي بدون تكرار الكود.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

create or replace function public.verify_otp_code(p_phone text, p_code text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare r record;
begin
  select * into r from public.otps
   where phone = p_phone and code = p_code and used = false and expires_at > now()
   order by created_at desc limit 1;
  if not found then return false; end if;
  update public.otps set used = true where id = r.id;
  return true;
end;
$$;
grant execute on function public.verify_otp_code(text, text) to anon, authenticated;
