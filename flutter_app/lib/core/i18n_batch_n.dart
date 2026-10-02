// rides_screen.dart's "recurring ride" booking option + recurring_ride_
// schedules_screen.dart (db/security-108-recurring-rides.sql). Kept as its
// own file per the established parallel-batch pattern (see i18n.dart's
// merge comment).
const Map<String, Map<String, String>> batchNStrings = {
  'rides_make_recurring': {'ar': '🔁 اجعلها رحلة متكررة ثابتة', 'en': '🔁 Make this a standing recurring ride'},
  'rides_recurring_pick_time': {'ar': 'اختار ميعاد الرحلة', 'en': 'Pick the ride time'},
  'rides_recurring_at_prefix': {'ar': 'الميعاد:', 'en': 'Time:'},
  'rides_submit_recurring': {'ar': 'احجز الرحلة المتكررة', 'en': 'Book the recurring ride'},
  'rides_my_recurring_rides': {'ar': 'رحلاتي المتكررة', 'en': 'My recurring rides'},
  'recurring_rides_created_success': {'ar': '✅ اتسجّلت الرحلة المتكررة — هتتحجز تلقائيًا في معادها', 'en': "✅ Recurring ride saved — it'll book itself automatically"},
  'recurring_rides_appbar_title': {'ar': 'رحلاتي المتكررة', 'en': 'My recurring rides'},
  'recurring_rides_empty': {'ar': 'مفيش رحلات متكررة مسجّلة', 'en': 'No recurring rides set up yet'},
  'recurring_rides_cancel_confirm_title': {'ar': 'إلغاء الرحلة المتكررة؟', 'en': 'Cancel this recurring ride?'},
  'recurring_rides_cancel_confirm_body': {'ar': 'مش هتتحجز تلقائيًا تاني بعد كده.', 'en': "It won't book itself automatically anymore."},
};
