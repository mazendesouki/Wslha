-- =====================================================================
--  وصّلها — Security #81: علم تفعيل/تعطيل تبديل اللغة
--
--  التطبيق يسمح للمستخدم يختار (عربي/إنجليزي) من الإعدادات
--  (flutter_app/lib/core/i18n.dart's LocaleController) — العلم ده بيتحكم
--  في ظهور الخيار ده من الأساس، زي كل ميزة قبله.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('feature_language_switch_enabled', 'true')
on conflict (key) do nothing;
