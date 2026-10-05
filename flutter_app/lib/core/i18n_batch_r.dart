// settings_screen.dart's "قيّم التطبيق" tile + rate-app bottom sheet
// (db/security-111-app-reviews.sql). Kept as its own file per the
// established parallel-batch pattern (see i18n.dart's merge comment).
const Map<String, Map<String, String>> batchRStrings = {
  'settings_rate_app': {'ar': 'قيّم التطبيق', 'en': 'Rate the app'},
  'rate_app_sheet_title': {'ar': '⭐ قيّم تجربتك مع وصّلها', 'en': '⭐ Rate your experience with Wslha'},
  'rate_app_sheet_subtitle': {'ar': 'رأيك ممكن يتعرض في الموقع كشهادة بعد موافقة الإدارة', 'en': 'Your review may appear on our site as a testimonial after admin approval'},
  'rate_app_comment_label': {'ar': 'اكتب تعليقك (اختياري)', 'en': 'Write a comment (optional)'},
  'rate_app_submit': {'ar': 'إرسال التقييم', 'en': 'Submit rating'},
  'rate_app_success': {'ar': '✅ شكرًا لتقييمك!', 'en': '✅ Thanks for your rating!'},
  'rate_app_failed_prefix': {'ar': 'فشل الإرسال:', 'en': 'Failed to submit:'},
};
