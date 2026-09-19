-- =====================================================================
--  وصّلها — Security #72: أعلام تفعيل/تعطيل الميزات (Feature Flags)
--
--  كل ميزة جديدة اتضافت الجلسة دي (وأي ميزة تتضاف بعدها) لازم يبقى
--  للأدمن قدرة يقفلها/يفتحها من لوحة التحكم من غير ما يحتاج نشر نسخة
--  تطبيق جديدة. مفيش دالة جديدة مطلوبة — admin_set_setting الموجودة
--  بالفعل (security04otpssettings.sql) بتتعامل مع أي مفتاح generic،
--  فده بس seed للقيم الافتراضية (true = شغالة زي ما هي دلوقتي، مفيش
--  تغيير في السلوك الحالي) + قراءة عامة عن طريق app_settings_anon_read
--  RLS الموجودة بالفعل.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('feature_sos_enabled', 'true'),
  ('feature_favorites_enabled', 'true'),
  ('feature_referral_enabled', 'true'),
  ('feature_chat_enabled', 'true'),
  ('feature_no_show_enabled', 'true'),
  ('feature_multistop_enabled', 'true'),
  ('feature_daily_goal_enabled', 'true'),
  ('feature_ride_share_enabled', 'true')
on conflict (key) do nothing;
