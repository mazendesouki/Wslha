-- =====================================================================
--  وصّلها — Security #80: علم تفعيل/تعطيل الوضع الليلي
--
--  التطبيق يسمح للمستخدم يختار (تلقائي/فاتح/داكن) من الإعدادات
--  (flutter_app/lib/core/theme.dart's ThemeController) — العلم ده بيتحكم
--  في ظهور الخيار ده من الأساس، زي كل ميزة قبله.
--
--  آمن لإعادة التشغيل.
-- =====================================================================
set search_path = public, extensions;

insert into public.app_settings (key, value) values
  ('feature_dark_mode_enabled', 'true')
on conflict (key) do nothing;
