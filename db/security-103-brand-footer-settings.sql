-- =====================================================================
--  وصّلها — Security #103: بيانات فوتر البريد الإلكتروني قابلة للتعديل
--
--  الفوتر (request-password-reset + send-marketing-email) كان بيانات
--  تواصل ثابتة في الكود (تليفون/واتساب/بريد) — أي تغيير كان محتاج
--  تعديل كود ونشر إصدار جديد. دلوقتي نفس الآلية العامة الموجودة بالفعل
--  (app_settings + admin_set_setting، زي أعلام الميزات security-72)
--  بتخزّن القيم دي، والدالتين بيقروها وقت الإرسال — الأدمن يقدر يغيّرها
--  من لوحة التحكم على طول من غير أي نشر كود.
--
--  seed بنفس القيم الحالية بالظبط (مفيش تغيير سلوك).
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('brand_footer_phone_display', '0020 1102 667324'),
  ('brand_footer_phone_tel',     '+201102667324'),
  ('brand_footer_whatsapp',      '201102667324'),
  ('brand_footer_email',         'info@wslha.co')
on conflict (key) do nothing;
