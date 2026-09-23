// Marketplace (سوق المستعمل) browse/detail/delivery-request screens —
// kept as its own file per the established parallel-batch pattern (see
// i18n.dart's merge comment) even though authored solo, to avoid touching
// the shared i18n.dart map directly.
const Map<String, Map<String, String>> batchIStrings = {
  // home_tab.dart
  'home_service_marketplace_title': {'ar': 'سوق المستعمل', 'en': 'Used market'},
  'home_service_marketplace_subtitle': {'ar': 'بيع واشتري بسهولة', 'en': 'Buy & sell with ease'},

  // marketplace_list_screen.dart
  'marketplace_list_title': {'ar': '🛍️ سوق المستعمل', 'en': '🛍️ Used market'},
  'marketplace_list_search_hint': {'ar': 'دوّر على منتج...', 'en': 'Search for an item...'},
  'marketplace_list_retry': {'ar': 'حاول تاني', 'en': 'Retry'},
  'marketplace_list_empty': {'ar': 'مفيش إعلانات دلوقتي', 'en': 'No listings right now'},
  'marketplace_list_no_results': {'ar': 'مفيش نتائج لبحثك', 'en': 'No results for your search'},
  'marketplace_category_all': {'ar': 'الكل', 'en': 'All'},

  // marketplace_item_screen.dart
  'marketplace_item_title': {'ar': 'تفاصيل الإعلان', 'en': 'Listing details'},
  'marketplace_item_not_found': {'ar': 'هذا الإعلان غير موجود أو تم حذفه.', 'en': 'This listing no longer exists.'},
  'marketplace_item_merchant_seller': {'ar': 'بائع تاجر', 'en': 'Merchant seller'},
  'marketplace_item_sold_badge': {'ar': 'تم البيع', 'en': 'Sold'},
  'marketplace_item_default_city': {'ar': 'دمياط الجديدة', 'en': 'New Damietta'},
  'marketplace_item_views_suffix': {'ar': 'مشاهدة', 'en': 'views'},
  'marketplace_item_no_description': {'ar': 'لا يوجد وصف إضافي.', 'en': 'No additional description.'},
  'marketplace_item_contact_seller_title': {'ar': 'تواصل مع البائع مباشرة', 'en': 'Contact the seller directly'},
  'marketplace_item_contact_seller_subtitle': {'ar': 'اتصال أو واتساب فوري', 'en': 'Call or WhatsApp instantly'},
  'marketplace_item_call_button': {'ar': 'اتصال', 'en': 'Call'},
  'marketplace_item_whatsapp_button': {'ar': 'واتساب', 'en': 'WhatsApp'},
  'marketplace_item_delivery_title': {'ar': 'تفضّل التوصيل بدل الذهاب بنفسك؟', 'en': 'Prefer delivery instead of going yourself?'},
  'marketplace_item_delivery_subtitle': {'ar': 'عبر شبكة سائقي وصّلها', 'en': 'Via Wslha\'s driver network'},
  'marketplace_item_delivery_button': {'ar': '🚚 اطلب توصيل عبر وصّلها', 'en': '🚚 Request delivery via Wslha'},

  // Delivery request bottom sheet
  'marketplace_delivery_sheet_title': {'ar': 'طلب توصيل المنتج', 'en': 'Request item delivery'},
  'marketplace_delivery_fee_prefix': {'ar': 'رسوم التوصيل', 'en': 'Delivery fee'},
  'marketplace_delivery_fee_suffix': {'ar': 'ج.م تُضاف على سعر المنتج', 'en': 'EGP added on top of the item price'},
  'marketplace_delivery_name_label': {'ar': 'اسمك الكامل', 'en': 'Full name'},
  'marketplace_delivery_phone_label': {'ar': 'رقم جوالك', 'en': 'Phone number'},
  'marketplace_delivery_address_label': {'ar': 'عنوانك بالتفصيل', 'en': 'Your address in detail'},
  'marketplace_delivery_error_name': {'ar': 'أدخل اسمك', 'en': 'Enter your name'},
  'marketplace_delivery_error_address': {'ar': 'أدخل عنوانك بالتفصيل', 'en': 'Enter your full address'},
  'marketplace_delivery_error_generic': {'ar': 'حدث خطأ، حاول مرة أخرى', 'en': 'Something went wrong, try again'},
  'marketplace_delivery_success': {'ar': '✅ تم إرسال طلب التوصيل — سيتواصل معك فريقنا لتأكيد السائق', 'en': '✅ Delivery request sent — our team will contact you to confirm a driver'},

  // location_confirm_screen.dart
  'location_confirm_title': {'ar': 'أكّد موقعك بالضبط', 'en': 'Confirm your exact location'},
  'location_confirm_hint': {'ar': 'حرّك الخريطة عشان تظبّط الدبوس على مكانك بالظبط', 'en': 'Move the map to line up the pin with your exact spot'},
  'location_confirm_button': {'ar': 'تأكيد الموقع', 'en': 'Confirm location'},

  // Phase 1 of the real-auth migration (db/security-88) — otp_login_screen.dart.
  // Delivery moved from SMS (Twilio) to email (db/security-90's shared
  // infrastructure) after Twilio's account was suspended over an unrelated
  // billing issue — see otp_auth_repository.dart.
  'login_otp_alternative': {'ar': 'تسجيل الدخول برقم الموبايل (رمز عبر البريد)', 'en': 'Log in with phone (email code)'},
  'otp_login_title': {'ar': 'تسجيل الدخول برمز التحقق', 'en': 'Log in with a verification code'},
  'otp_login_enter_phone_subtitle': {'ar': 'هنبعتلك كود تحقق على بريدك الإلكتروني المسجّل', 'en': 'We\'ll send you a verification code to your registered email'},
  'otp_login_enter_code_subtitle': {'ar': 'اكتب الكود اللي وصلك على بريدك الإلكتروني', 'en': 'Enter the code sent to your email'},
  'otp_login_phone_label': {'ar': 'رقم الجوال', 'en': 'Phone number'},
  'otp_login_send_code_button': {'ar': 'إرسال الكود', 'en': 'Send code'},
  'otp_login_code_label': {'ar': 'كود التحقق', 'en': 'Verification code'},
  'otp_login_verify_button': {'ar': 'تأكيد ودخول', 'en': 'Verify & log in'},
  'otp_login_change_phone': {'ar': 'تغيير الرقم', 'en': 'Change number'},
  'otp_login_send_failed': {'ar': 'تعذّر إرسال الكود، تأكد من الرقم وحاول تاني', 'en': 'Could not send the code — check the number and try again'},
  'otp_login_not_found': {'ar': 'هذا الرقم غير مسجّل — سجّل حساب جديد الأول', 'en': 'This number isn\'t registered — please sign up first'},
  'otp_login_no_email': {'ar': 'لا يوجد بريد إلكتروني مسجّل لهذا الحساب — تواصل مع الدعم الفني', 'en': 'No email registered for this account — contact support'},
  'otp_login_code_required': {'ar': 'أدخل الكود اللي وصلك', 'en': 'Enter the code you received'},
  'otp_login_verify_failed': {'ar': 'الكود غير صحيح أو انتهت صلاحيته', 'en': 'Incorrect or expired code'},

  // forgot_password_screen.dart — same email-code + reset_password RPC
  // pair login.astro's web forgot-password step already uses.
  'login_forgot_password': {'ar': 'نسيت كلمة المرور؟', 'en': 'Forgot password?'},
  'forgot_password_title': {'ar': 'استعادة كلمة المرور', 'en': 'Reset password'},
  'forgot_password_new_password': {'ar': 'كلمة المرور الجديدة', 'en': 'New password'},
  'forgot_password_confirm_password': {'ar': 'تأكيد كلمة المرور', 'en': 'Confirm password'},
  'forgot_password_submit': {'ar': 'تعيين كلمة المرور', 'en': 'Set password'},
  'forgot_password_mismatch': {'ar': 'كلمتا المرور غير متطابقتين', 'en': 'Passwords don\'t match'},
  'forgot_password_bad_code': {'ar': 'الرمز غير صحيح أو انتهت صلاحيته', 'en': 'Incorrect or expired code'},
  'forgot_password_send_failed': {'ar': 'تعذّر إرسال الرمز، حاول لاحقاً', 'en': 'Could not send the code — try again later'},
  'forgot_password_not_found': {'ar': 'هذا الرقم غير مسجّل في النظام', 'en': 'This number isn\'t registered'},
  'forgot_password_no_email': {'ar': 'لا يوجد بريد إلكتروني مسجّل لهذا الحساب — تواصل مع الدعم الفني', 'en': 'No email registered for this account — contact support'},
  'forgot_password_done': {'ar': 'تم تغيير كلمة المرور بنجاح — سجّل دخولك بكلمة المرور الجديدة', 'en': 'Password changed successfully — log in with your new password'},
  'forgot_password_back_to_login': {'ar': 'رجوع لتسجيل الدخول', 'en': 'Back to login'},

  // driver_merchant_register_screen.dart — commission trust banner (a
  // concrete, low number shown before signup, instead of only appearing
  // after the fact on the post-ride settlement receipt).
  'driver_reg_commission_banner_title': {'ar': 'عمولتنا من أقل العمولات في السوق', 'en': 'One of the lowest commissions around'},
  'driver_reg_commission_banner_subtitle': {'ar': 'مش نسبة تقريبية — ده اللي بتاخده فعليًا من كل رحلة', 'en': 'Not an estimate — this is exactly what we take from every trip'},

  // rides_screen.dart — live-status card (design direction ب's missing
  // piece, db/security-91's real driver count, no fake numbers).
  'rides_available_drivers_suffix': {'ar': 'سائق متاح بالقرب منك الآن', 'en': 'drivers available near you now'},
  'rides_available_drivers_live_badge': {'ar': 'مباشر', 'en': 'LIVE'},
  'rides_passenger_increase': {'ar': 'زيادة عدد الركاب', 'en': 'Increase passenger count'},
  'rides_passenger_decrease': {'ar': 'تقليل عدد الركاب', 'en': 'Decrease passenger count'},
};
