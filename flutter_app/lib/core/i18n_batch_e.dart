// Batch E — manual i18n strings for: emergency contacts, favorite drivers,
// referrals, rating sheets, ratings list, and scheduled rides screens.
// Merged into AppLocalizationsX's _allStrings in core/i18n.dart.
const Map<String, Map<String, String>> batchEStrings = {
  // --- safety/emergency_contacts_screen.dart ---
  'emergency_add_title': {'ar': 'إضافة جهة اتصال طوارئ', 'en': 'Add emergency contact'},
  'emergency_name_label': {'ar': 'الاسم', 'en': 'Name'},
  'emergency_phone_label': {'ar': 'رقم الموبايل', 'en': 'Mobile number'},
  'emergency_validation_error': {'ar': 'اكتب الاسم ورقم موبايل مصري صحيح', 'en': 'Enter the name and a valid Egyptian mobile number'},
  'emergency_save': {'ar': 'حفظ', 'en': 'Save'},
  'emergency_max_contacts': {'ar': 'أقصى عدد جهات اتصال طوارئ هو 3', 'en': 'The maximum number of emergency contacts is 3'},
  'emergency_delete_title': {'ar': 'حذف جهة الاتصال؟', 'en': 'Delete this contact?'},
  'emergency_delete_body_prefix': {'ar': 'هتحذف', 'en': "You're about to delete"},
  'emergency_delete_body_suffix': {'ar': 'من قائمة الطوارئ.', 'en': 'from your emergency contacts list.'},
  'emergency_cancel': {'ar': 'تراجع', 'en': 'Cancel'},
  'emergency_delete': {'ar': 'حذف', 'en': 'Delete'},
  'emergency_appbar_title': {'ar': 'جهات اتصال الطوارئ', 'en': 'Emergency contacts'},
  'emergency_safety_notice': {
    'ar': 'لو ضغطت زرار الطوارئ أثناء الرحلة، هيتفتح تطبيق الرسائل جاهز برسالة فيها موقعك الحالي ورابط متابعة الرحلة، مرسلة لكل الأشخاص دول مرة واحدة — أنت بس اللي تضغط إرسال.',
    'en': "If you press the emergency button during a ride, your messaging app will open with a message ready to go, containing your current location and a ride-tracking link, addressed to everyone on this list at once — you just have to tap send.",
  },
  'emergency_empty': {'ar': 'لسه مفيش جهات اتصال طوارئ محفوظة', 'en': 'No emergency contacts saved yet'},
  'emergency_add_button': {'ar': 'إضافة جهة اتصال', 'en': 'Add contact'},

  // --- favorites/favorite_drivers_screen.dart ---
  'favorites_appbar_title': {'ar': 'السائقين المفضّلين', 'en': 'Favorite drivers'},
  'favorites_empty': {
    'ar': 'لسه مفيش سائقين مفضّلين — دوس على أيقونة ❤️ في تفاصيل السائق أثناء أي رحلة عشان تضيفه هنا',
    'en': 'No favorite drivers yet — tap the ❤️ icon on a driver\'s details during any ride to add them here',
  },
  'favorites_driver_fallback': {'ar': 'سائق', 'en': 'Driver'},

  // --- referrals/referral_screen.dart ---
  'referral_share_prefix': {'ar': 'انزل تطبيق وصّلها واستخدم كود الدعوة بتاعي', 'en': 'Download the وصّلها app and use my invite code'},
  'referral_share_suffix': {'ar': 'كل واحد فينا ياخد رصيد 20 ج.م في المحفظة 🎁', 'en': 'we each get 20 ج.م credit in our wallet 🎁'},
  'referral_code_copied': {'ar': 'تم نسخ الكود', 'en': 'Code copied'},
  'referral_redeem_success': {'ar': '🎉 تم! اتضاف 20 ج.م لمحفظتك', 'en': '🎉 Done! 20 ج.م was added to your wallet'},
  'referral_redeem_error': {'ar': 'الكود غير صحيح أو مستخدم قبل كده', 'en': 'This code is invalid or has already been used'},
  'referral_appbar_title': {'ar': 'كود الدعوة', 'en': 'Invite code'},
  'referral_my_code_label': {'ar': 'كود الدعوة بتاعك', 'en': 'Your invite code'},
  'referral_copy': {'ar': 'نسخ', 'en': 'Copy'},
  'referral_share': {'ar': 'مشاركة', 'en': 'Share'},
  'referral_invite_explainer': {
    'ar': 'ادعُ صحابك — كل واحد يستخدم كودك ياخد 20 ج.م رصيد في محفظته، وانت كمان تاخد 20 ج.م.',
    'en': 'Invite your friends — anyone who uses your code gets 20 ج.م credit in their wallet, and you get 20 ج.م too.',
  },
  'referral_have_code_question': {'ar': 'عندك كود من صاحبك؟', 'en': "Have a friend's code?"},
  'referral_code_hint': {'ar': 'اكتب الكود هنا', 'en': 'Enter the code here'},
  'referral_use_button': {'ar': 'استخدام', 'en': 'Redeem'},

  // --- ratings/rate_sheet.dart ---
  'rate_sheet_what_happened': {'ar': 'إيه اللي حصل بالظبط؟ (اختياري)', 'en': 'What happened exactly? (optional)'},
  'rate_sheet_extra_details_hint': {'ar': 'تفاصيل إضافية (اختياري)', 'en': 'Additional details (optional)'},
  'rate_sheet_skip': {'ar': 'تخطي', 'en': 'Skip'},
  'rate_sheet_submit': {'ar': 'إرسال التقييم', 'en': 'Submit rating'},
  'rate_sheet_skip_now': {'ar': 'تخطي دلوقتي', 'en': 'Skip for now'},

  // --- ratings/order_rating_sheet.dart ---
  'order_rating_title': {'ar': 'قيّم طلبك', 'en': 'Rate your order'},
  'order_rating_driver_label': {'ar': 'السائق 🚖', 'en': 'Driver 🚖'},
  'order_rating_comment_hint': {'ar': 'تعليق (اختياري)', 'en': 'Comment (optional)'},
  'order_rating_skip': {'ar': 'تخطي', 'en': 'Skip'},
  'order_rating_submit': {'ar': 'إرسال التقييم', 'en': 'Submit rating'},

  // --- ratings/ratings_list_screen.dart ---
  'ratings_list_no_ratings_yet': {'ar': 'لسه ما وصلش تقييم', 'en': 'No ratings yet'},
  'ratings_list_trusted_badge': {'ar': '✅ موثوق', 'en': '✅ Trusted'},
  'ratings_list_your_reply_prefix': {'ar': 'ردك:', 'en': 'Your reply:'},

  // --- rides/scheduled_rides_screen.dart ---
  'scheduled_rides_cancel_confirm_title': {'ar': 'إلغاء الرحلة المجدولة؟', 'en': 'Cancel the scheduled ride?'},
  'scheduled_rides_cancel_confirm_body': {'ar': 'هيتم إلغاء الحجز نهائيًا.', 'en': 'The booking will be cancelled permanently.'},
  'scheduled_rides_cancel_back': {'ar': 'تراجع', 'en': 'Back'},
  'scheduled_rides_cancel_confirm_action': {'ar': 'إلغاء الرحلة', 'en': 'Cancel ride'},
  'scheduled_rides_cancel_success': {'ar': '✅ تم إلغاء الرحلة', 'en': '✅ Ride cancelled'},
  'scheduled_rides_cancel_failed': {'ar': '❌ تعذّر الإلغاء', 'en': "❌ Couldn't cancel"},
  'scheduled_rides_appbar_title': {'ar': 'رحلاتي المجدولة', 'en': 'My scheduled rides'},
  'scheduled_rides_empty': {'ar': 'مفيش رحلات مجدولة حاليًا', 'en': 'No scheduled rides right now'},
  'scheduled_rides_cancel_button': {'ar': 'إلغاء', 'en': 'Cancel'},
};
