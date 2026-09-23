// Trip log + driver cash reminder (db/security-92) — kept as its own file
// per the established parallel-batch pattern (see i18n.dart's merge
// comment) to avoid touching the shared i18n.dart map directly.
const Map<String, Map<String, String>> batchJStrings = {
  // driver_home_screen.dart
  'trip_log_appbar_title': {'ar': '📋 سجل الرحلات', 'en': '📋 Trip log'},

  // trip_log_screen.dart
  'trip_log_empty': {'ar': 'مفيش طلبات فاتتك لحد دلوقتي', 'en': "You haven't missed any requests so far"},
  'trip_log_order_fallback_title': {'ar': 'طلب توصيل', 'en': 'Delivery order'},

  // cash_reminder_dialog.dart
  'cash_reminder_title': {'ar': '💰 تذكير سداد رصيد كاش', 'en': '💰 Cash balance reminder'},
  'cash_reminder_body_prefix': {'ar': 'عندك مبلغ', 'en': "You've collected"},
  'cash_reminder_body_suffix': {'ar': 'مستحق للشركة — برجاء السداد خلال', 'en': 'owed to the company — please settle within'},
  'cash_reminder_due_prefix': {'ar': 'آخر موعد للسداد:', 'en': 'Due by:'},
  'cash_reminder_note_label': {'ar': 'ملاحظة:', 'en': 'Note:'},
  'cash_reminder_dismiss': {'ar': 'تم، هسدد', 'en': 'Got it'},
};
