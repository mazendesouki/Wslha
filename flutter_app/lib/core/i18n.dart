import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight manual translation system — no codegen (`flutter gen-l10n`)
/// since there's no Dart SDK available in this environment to verify
/// generated code compiles. Every translatable string lives in `_strings`
/// below, keyed once and looked up per-locale via `context.tr('key')`.
///
/// This is infrastructure plus a first batch of screens (settings, login,
/// bottom navigation, common actions) — most of the app's ~50+ screens
/// still have their Arabic text hardcoded inline and are NOT yet wired to
/// this system. Converting every remaining screen is the natural next
/// increment, the same way dark-mode's `AppThemeX` extension started with
/// infra + a first batch before spreading further.
class LocaleController {
  LocaleController._();
  static const _key = 'wslha_locale';

  static final ValueNotifier<Locale> locale = ValueNotifier(const Locale('ar'));
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == 'en') locale.value = const Locale('en');
    } catch (_) {
      // Keep the Arabic default on any prefs failure.
    }
  }

  static Future<void> set(Locale value) async {
    locale.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.languageCode);
    } catch (_) {
      // In-memory value already updated — a failed persist just means the
      // choice won't survive a cold restart.
    }
  }
}

/// key → {ar: ..., en: ...}. Add new keys here as more screens are wired up.
const Map<String, Map<String, String>> _strings = {
  // Bottom navigation / shells
  'nav_home': {'ar': 'الرئيسية', 'en': 'Home'},
  'nav_orders': {'ar': 'الطلبات', 'en': 'Orders'},
  'nav_wallet': {'ar': 'المحفظة', 'en': 'Wallet'},
  'nav_settings': {'ar': 'الإعدادات', 'en': 'Settings'},
  'nav_account': {'ar': 'حسابي', 'en': 'Account'},
  'nav_rides': {'ar': 'رحلات', 'en': 'Rides'},

  // Settings screen
  'settings_title': {'ar': 'الإعدادات', 'en': 'Settings'},
  'settings_notifications': {'ar': 'الإشعارات', 'en': 'Notifications'},
  'settings_notifications_log': {'ar': 'سجل الإشعارات', 'en': 'Notification log'},
  'settings_dark_mode': {'ar': 'الوضع الليلي', 'en': 'Dark mode'},
  'settings_dark_mode_system': {'ar': 'تلقائي', 'en': 'Automatic'},
  'settings_dark_mode_light': {'ar': 'فاتح', 'en': 'Light'},
  'settings_dark_mode_dark': {'ar': 'داكن', 'en': 'Dark'},
  'settings_language': {'ar': 'اللغة', 'en': 'Language'},
  'settings_language_ar': {'ar': 'العربية', 'en': 'Arabic'},
  'settings_language_en': {'ar': 'الإنجليزية', 'en': 'English'},
  'settings_support': {'ar': 'المساعدة والدعم', 'en': 'Help & support'},
  'settings_logout': {'ar': 'تسجيل الخروج', 'en': 'Log out'},
  'settings_emergency_contacts': {'ar': 'جهات اتصال الطوارئ', 'en': 'Emergency contacts'},

  // Common actions
  'action_save': {'ar': 'حفظ', 'en': 'Save'},
  'action_cancel': {'ar': 'إلغاء', 'en': 'Cancel'},
  'action_confirm': {'ar': 'تأكيد', 'en': 'Confirm'},
  'action_send': {'ar': 'إرسال', 'en': 'Send'},
  'action_retry': {'ar': 'حاول تاني', 'en': 'Retry'},
  'action_edit': {'ar': 'تعديل', 'en': 'Edit'},
  'action_delete': {'ar': 'حذف', 'en': 'Delete'},
  'action_close': {'ar': 'إغلاق', 'en': 'Close'},

  // Login screen
  'login_title': {'ar': 'تسجيل الدخول', 'en': 'Log in'},
  'login_phone_hint': {'ar': 'رقم الموبايل', 'en': 'Phone number'},
  'login_password_hint': {'ar': 'كلمة المرور', 'en': 'Password'},
  'login_submit': {'ar': 'دخول', 'en': 'Log in'},
  'login_no_account': {'ar': 'معندكش حساب؟', 'en': "Don't have an account?"},
  'login_register': {'ar': 'سجّل دلوقتي', 'en': 'Register now'},
};

extension AppLocalizationsX on BuildContext {
  String tr(String key) {
    final code = LocaleController.locale.value.languageCode;
    final entry = _strings[key];
    if (entry == null) return key;
    return entry[code] ?? entry['ar'] ?? key;
  }
}
