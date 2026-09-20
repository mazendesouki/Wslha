const Map<String, Map<String, String>> batchHStrings = {
  // shared/widgets/finish_ride_button.dart
  'finish_ride_arrived_button': {'ar': '✓ وصلنا للوجهة — إنهاء الرحلة', 'en': '✓ Arrived at destination — Finish ride'},
  'finish_ride_not_arrived_button': {'ar': '📍 لسه ما وصلتش', 'en': "📍 Not there yet"},
  'finish_ride_remaining_suffix': {'ar': 'متبقية', 'en': 'remaining'},
  'finish_ride_manual_confirm_link': {'ar': 'وصلت فعليًا؟ اضغط هنا للتأكيد يدويًا', 'en': 'Actually arrived? Tap here to confirm manually'},
  'finish_ride_manual_dialog_title': {'ar': 'تأكيد الوصول يدويًا', 'en': 'Confirm arrival manually'},
  'finish_ride_manual_dialog_body': {
    'ar': 'الموقع الحالي لسه بعيد عن نقطة النهاية حسب الـ GPS. متأكد إنك وصلت فعلاً وعايز تنهي الرحلة؟',
    'en': "Your current location is still far from the destination according to GPS. Are you sure you've arrived and want to finish the ride?",
  },
  'finish_ride_manual_dialog_cancel': {'ar': 'تراجع', 'en': 'Cancel'},
  'finish_ride_manual_dialog_confirm': {'ar': 'تأكيد الإنهاء', 'en': 'Confirm finish'},

  // shared/widgets/sos_button.dart
  'sos_alert_no_contacts': {
    'ar': 'اتسجل تنبيه الطوارئ — بس لسه معندكش جهات اتصال طوارئ محفوظة عشان نبعتلهم',
    'en': "Emergency alert logged — but you don't have any saved emergency contacts to notify yet",
  },
  'sos_add_contacts_action': {'ar': 'إضافة', 'en': 'Add'},
  'sos_alert_sms_opened': {'ar': '🆘 اتسجل التنبيه — فتحنالك رسالة جاهزة، اضغط إرسال', 'en': "🆘 Alert logged — we've opened a ready message for you, tap send"},
  'sos_alert_logged': {'ar': '🆘 اتسجل تنبيه الطوارئ', 'en': '🆘 Emergency alert logged'},
  'sos_button_label': {'ar': 'طوارئ', 'en': 'Emergency'},
  'sos_countdown_title': {'ar': '🆘 تفعيل تنبيه الطوارئ', 'en': '🆘 Activate emergency alert'},
  'sos_countdown_body': {
    'ar': 'هيتبعت تنبيه فيه موقعك لجهات الطوارئ خلال SECONDS ثانية — اضغط إلغاء لو دوست بالغلط.',
    'en': 'An alert with your location will be sent to your emergency contacts in SECONDS seconds — tap cancel if you tapped by mistake.',
  },
  'sos_countdown_cancel': {'ar': 'إلغاء', 'en': 'Cancel'},

  // shared/widgets/waiting_timer_card.dart
  'waiting_timer_customer_grace': {
    'ar': 'السائق وصل — عندك REMAINING قبل ما يبدأ خصم FEE ج.م عن كل دقيقة تأخير',
    'en': 'The driver has arrived — you have REMAINING before a FEE EGP charge per minute of delay starts',
  },
  'waiting_timer_driver_grace': {
    'ar': 'في انتظار العميل — REMAINING متبقية بدون خصم عليه',
    'en': 'Waiting for the customer — REMAINING left with no charge yet',
  },
  'waiting_timer_customer_over': {
    'ar': 'اتأخرت MINUTES د — هيتخصم منك FEE ج.م لو الرحلة بدأت دلوقتي',
    'en': "You're MINUTES min late — FEE EGP will be charged if the ride starts now",
  },
  'waiting_timer_driver_over': {
    'ar': 'العميل اتأخر MINUTES د — هيتخصم منه FEE ج.م لو الرحلة بدأت دلوقتي',
    'en': 'The customer is MINUTES min late — FEE EGP will be charged if the ride starts now',
  },

  // shared/widgets/logout_button.dart
  'logout_tooltip': {'ar': 'تسجيل الخروج', 'en': 'Log out'},

  // shared/widgets/placeholder_screen.dart
  'placeholder_coming_soon': {'ar': 'قريباً في المرحلة القادمة', 'en': 'Coming soon in the next phase'},

  // features/rides/address_field.dart
  'address_field_location_permission_needed': {'ar': 'محتاجين إذن الموقع عشان نحدد نقطة انطلاقك', 'en': 'We need location permission to determine your starting point'},
  'address_field_location_service_disabled': {'ar': 'خدمة تحديد الموقع (GPS) مقفولة على جهازك', 'en': 'Location services (GPS) are turned off on your device'},
  'address_field_location_failed': {'ar': 'تعذّر تحديد موقعك، حاول تاني', 'en': 'Could not determine your location, try again'},
  'address_field_location_timeout': {'ar': 'الموقع بياخد وقت طويل، اكتب العنوان يدويًا أو حاول تاني', 'en': 'Location is taking too long — type the address manually or try again'},
  'address_field_use_current_location': {'ar': 'استخدم موقعي الحالي', 'en': 'Use my current location'},

  // features/coupons/coupon_field.dart
  'coupon_field_check_failed': {'ar': 'تعذّر التحقق من الكود، حاول تاني', 'en': "Couldn't verify the code, try again"},
  'coupon_field_hint': {'ar': '🎟️ عندك كود خصم؟', 'en': '🎟️ Have a discount code?'},
  'coupon_field_apply': {'ar': 'تطبيق', 'en': 'Apply'},
  'coupon_field_success': {'ar': 'هترجعلك AMOUNT ج.م في محفظتك بعد التأكيد', 'en': "You'll get AMOUNT EGP back in your wallet after confirmation"},

  // features/favorites/favorite_driver_button.dart
  'favorite_driver_remove_tooltip': {'ar': 'إزالة من المفضّلين', 'en': 'Remove from favorites'},
  'favorite_driver_add_tooltip': {'ar': 'إضافة للسائقين المفضّلين', 'en': 'Add to favorite drivers'},

  // features/driver/driver_home_shell.dart
  'driver_shell_rejected_title': {'ar': 'تم رفض طلب انضمامك', 'en': 'Your application was rejected'},
  'driver_shell_pending_title': {'ar': 'حسابك قيد المراجعة', 'en': 'Your account is under review'},
  'driver_shell_rejected_body': {'ar': 'تواصل مع الدعم لمعرفة السبب أو لإعادة التقديم.', 'en': 'Contact support to find out why or to re-apply.'},
  'driver_shell_pending_body': {
    'ar': 'لسه ما اتراجعش طلبك من الإدارة — مش هتقدر تستقبل رحلات لحد ما يتم الاعتماد.',
    'en': "Your application hasn't been reviewed by the admin yet — you won't be able to receive rides until it's approved.",
  },
  'driver_shell_refresh_status': {'ar': '🔄 تحديث الحالة', 'en': '🔄 Refresh status'},

  // features/settings/settings_screen.dart
  'settings_new_version_title': {'ar': 'نسخة جديدة متاحة', 'en': 'New version available'},
  'settings_new_version_body': {'ar': 'الإصدار VERSION', 'en': 'Version VERSION'},
  'settings_update_now': {'ar': 'تحديث الآن', 'en': 'Update now'},
  'settings_tile_account': {'ar': 'حسابي', 'en': 'My account'},
  'settings_tile_wallet': {'ar': 'المحفظة', 'en': 'Wallet'},
  'settings_tile_orders': {'ar': 'طلباتي ومشاويري', 'en': 'My orders and rides'},
  'settings_app_version_label': {'ar': 'وصّلها — الإصدار VERSION', 'en': 'Wslha — version VERSION'},

  // features/account/account_screen.dart
  'account_role_customer': {'ar': 'عميل', 'en': 'Customer'},
  'account_role_driver': {'ar': 'سائق', 'en': 'Driver'},
  'account_role_merchant': {'ar': 'تاجر', 'en': 'Merchant'},
  'account_role_admin': {'ar': 'أدمن', 'en': 'Admin'},
};
