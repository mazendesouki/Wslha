// settings_screen.dart's smarter-notifications controls (per-category
// toggles + quiet hours — core/notifications.dart's AppNotifications._enabled()).
// Kept as its own file per the established parallel-batch pattern (see
// i18n.dart's merge comment).
const Map<String, Map<String, String>> batchSStrings = {
  'settings_notif_orders': {'ar': 'الطلبات الجديدة', 'en': 'New orders'},
  'settings_notif_rides': {'ar': 'المشاوير والتحديثات الأخرى', 'en': 'Rides & other updates'},
  'settings_quiet_hours': {'ar': 'ساعات هدوء', 'en': 'Quiet hours'},
  'settings_quiet_hours_subtitle': {
    'ar': 'كتم الإشعارات في الوقت ده (عدا تنبيه اقتراب السائق أثناء رحلة شغالة)',
    'en': "Mute notifications during this window (except the driver-nearby alert during an active ride)",
  },
  'settings_quiet_from': {'ar': 'من', 'en': 'From'},
  'settings_quiet_to': {'ar': 'إلى', 'en': 'To'},
};
