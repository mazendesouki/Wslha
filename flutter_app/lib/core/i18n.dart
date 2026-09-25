import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n_batch_a.dart';
import 'i18n_batch_b.dart';
import 'i18n_batch_c.dart';
import 'i18n_batch_d.dart';
import 'i18n_batch_e.dart';
import 'i18n_batch_f.dart';
import 'i18n_batch_g.dart';
import 'i18n_batch_h.dart';
import 'i18n_batch_i.dart';
import 'i18n_batch_j.dart';
import 'i18n_batch_k.dart';
import 'i18n_batch_l.dart';

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
  'login_phone_label': {'ar': 'رقم الجوال', 'en': 'Phone number'},
  'login_phone_hint': {'ar': '01xxxxxxxxx', 'en': '01xxxxxxxxx'},
  'login_phone_required': {'ar': 'أدخل رقم الجوال', 'en': 'Enter your phone number'},
  'login_password_label': {'ar': 'كلمة المرور', 'en': 'Password'},
  'login_password_required': {'ar': 'أدخل كلمة المرور', 'en': 'Enter your password'},
  'login_remember_me': {'ar': 'تذكرني', 'en': 'Remember me'},
  'login_submit': {'ar': 'دخول', 'en': 'Log in'},
  'login_no_account': {'ar': 'ليس لديك حساب؟ سجّل الآن', 'en': "Don't have an account? Register now"},
  'login_register_driver': {'ar': '📝 سجّل كسائق الآن', 'en': '📝 Register as a driver now'},
  'login_register_merchant': {'ar': '📝 سجّل كتاجر الآن', 'en': '📝 Register as a merchant now'},
  'login_error_not_found': {'ar': 'لا يوجد حساب بهذا الرقم.', 'en': 'No account found with this number.'},
  'login_error_bad_password': {'ar': 'كلمة المرور غير صحيحة.', 'en': 'Incorrect password.'},
  'login_error_generic': {'ar': 'تعذّر الاتصال، تحقق من الإنترنت وحاول مجدداً.', 'en': "Couldn't connect — check your internet and try again."},

  // Register screen
  'register_new_account': {'ar': 'حساب جديد', 'en': 'New account'},
  'register_step_word': {'ar': 'الخطوة', 'en': 'Step'},
  'register_of_word': {'ar': 'من', 'en': 'of'},
  'register_step1_title': {'ar': 'الخطوة ١ — هويتك', 'en': 'Step 1 — Your identity'},
  'register_step1_subtitle': {'ar': 'عرّفنا بنفسك واختر اسم مستخدم مميّز', 'en': 'Tell us about yourself and pick a unique username'},
  'register_full_name': {'ar': 'الاسم بالكامل', 'en': 'Full name'},
  'register_username': {'ar': 'اسم المستخدم', 'en': 'Username'},
  'register_username_helper': {'ar': 'أحرف إنجليزية وأرقام و _ . فقط (3-20 حرف)', 'en': 'English letters, numbers, and _ . only (3-20 chars)'},
  'register_national_id': {'ar': 'الرقم القومي', 'en': 'National ID'},
  'register_national_id_helper': {'ar': '14 رقم ويبدأ بـ 2 أو 3', 'en': '14 digits, starting with 2 or 3'},
  'register_national_id_expiry': {'ar': 'تاريخ انتهاء البطاقة', 'en': 'ID expiry date'},
  'register_pick_date': {'ar': 'اختر التاريخ', 'en': 'Pick a date'},
  'register_next': {'ar': 'التالي ←', 'en': 'Next →'},
  'register_back': {'ar': '→ السابق', 'en': '← Back'},
  'register_step2_title': {'ar': 'الخطوة ٢ — بيانات التواصل', 'en': 'Step 2 — Contact details'},
  'register_step2_subtitle': {'ar': 'بريدك ومدينتك لخدمة توصيل أدق', 'en': 'Your email and city, for more accurate delivery'},
  'register_email': {'ar': 'البريد الإلكتروني', 'en': 'Email'},
  'register_city': {'ar': 'المدينة', 'en': 'City'},
  'register_step3_title': {'ar': 'الخطوة ٣ — الأمان', 'en': 'Step 3 — Security'},
  'register_step3_subtitle': {'ar': 'اختر كلمة مرور قوية لحماية حسابك', 'en': 'Choose a strong password to protect your account'},
  'register_password': {'ar': 'كلمة المرور', 'en': 'Password'},
  'register_confirm_password': {'ar': 'تأكيد كلمة المرور', 'en': 'Confirm password'},
  'register_passwords_match': {'ar': '✓ كلمتا المرور متطابقتان', 'en': '✓ Passwords match'},
  'register_passwords_mismatch': {'ar': '✗ كلمتا المرور غير متطابقتين', 'en': '✗ Passwords do not match'},
  'register_submit': {'ar': 'إنشاء الحساب ✓', 'en': 'Create account ✓'},
  'register_pw_rule_length': {'ar': '8 أحرف على الأقل', 'en': 'At least 8 characters'},
  'register_pw_rule_upper': {'ar': 'حرف كبير (A-Z)', 'en': 'One uppercase letter (A-Z)'},
  'register_pw_rule_lower': {'ar': 'حرف صغير (a-z)', 'en': 'One lowercase letter (a-z)'},
  'register_pw_rule_number': {'ar': 'رقم واحد', 'en': 'One number'},
  'register_pw_rule_no_symbols': {'ar': 'بدون رموز أو مسافات', 'en': 'No symbols or spaces'},

  // Home tab (customer)
  'home_greeting_prefix': {'ar': 'مرحباً،', 'en': 'Hi'},
  'home_greeting_default_name': {'ar': 'بك', 'en': 'there'},
  'home_what_today': {'ar': 'إيه محتاج تعمله النهاردة؟', 'en': 'What do you need today?'},
  'home_more_services': {'ar': 'خدمات إضافية', 'en': 'More services'},
  'home_service_rides_title': {'ar': 'مشاوير', 'en': 'Rides'},
  'home_service_rides_subtitle': {'ar': 'احجز مشوارك دلوقتي', 'en': 'Book your ride now'},
  'home_service_airport_title': {'ar': 'توصيل المطار', 'en': 'Airport transfer'},
  'home_service_airport_subtitle': {'ar': 'من دمياط إلى كل مطارات مصر', 'en': 'From Damietta to every airport in Egypt'},
  'home_service_parcels_title': {'ar': 'طرود ومستندات', 'en': 'Parcels & documents'},
  'home_service_parcels_subtitle': {'ar': 'مندوب مخصص لشحنتك', 'en': 'A dedicated courier for your shipment'},
  'home_service_delivery_title': {'ar': 'خدمة دليفري', 'en': 'Delivery service'},
  'home_service_delivery_subtitle': {'ar': 'اطلب من أي متجر قريب منك', 'en': 'Order from any nearby store'},
  'home_trust_safety': {'ar': 'أمان وسلامة', 'en': 'Safety'},
  'home_trust_pricing': {'ar': 'أسعار واضحة', 'en': 'Clear pricing'},
  'home_trust_payment': {'ar': 'دفع مرن', 'en': 'Flexible payment'},
  'home_trust_support': {'ar': 'دعم 24 ساعة', 'en': '24/7 support'},
};

// Merged once here rather than inline in _strings — batch_a/b/c were each
// authored by a separate agent working in parallel on different screens, so
// keeping them as their own files avoided every agent editing this same
// map concurrently (a guaranteed Edit-tool collision). Verified no key
// collisions across all four maps before merging.
final Map<String, Map<String, String>> _allStrings = {
  ..._strings,
  ...batchAStrings,
  ...batchBStrings,
  ...batchCStrings,
  ...batchDStrings,
  ...batchEStrings,
  ...batchFStrings,
  ...batchGStrings,
  ...batchHStrings,
  ...batchIStrings,
  ...batchJStrings,
  ...batchKStrings,
  ...batchLStrings,
};

extension AppLocalizationsX on BuildContext {
  String tr(String key) {
    final code = LocaleController.locale.value.languageCode;
    final entry = _allStrings[key];
    if (entry == null) return key;
    return entry[code] ?? entry['ar'] ?? key;
  }
}
