import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// System-tray notifications while the app is running — the "إشعارات"
/// toggle in SettingsScreen (shared_preferences key below) gates these.
/// This is local-only (flutter_local_notifications): it fires from
/// in-app Realtime updates, not a server push, so it only works while the
/// app process is alive. Real server push (Firebase Cloud Messaging, works
/// even with the app closed) is core/push.dart — it reuses the
/// 'wslha_orders' channel created below to display FCM notifications that
/// arrive while the app is foregrounded.
class AppNotifications {
  AppNotifications._();
  static final AppNotifications instance = AppNotifications._();

  static const _notifPrefKey = 'wslha_notif';
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 1000;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // The whole app is Egyptian-mobile-only (see phone_utils.dart's
    // isEgyptianMobile validation) — hardcoding one timezone instead of
    // pulling in a device-timezone-lookup package (Egypt uses a single
    // zone, no DST since 2016) is a deliberate simplification.
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    // Must exist before a background/terminated FCM message tagged with
    // this channel_id (see supabase/functions/send-push) arrives, or
    // Android falls back to a default low-importance channel. A strong
    // vibration pattern here matters most for the merchant app — a new
    // order easily gets missed among counter/kitchen noise otherwise.
    await androidImpl?.createNotificationChannel(AndroidNotificationChannel(
      'wslha_orders',
      'الطلبات الجديدة',
      description: 'إشعار فوري عند وصول طلب جديد',
      importance: Importance.max,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 400]),
    ));
    // show() below was passing this channel id without ever creating it —
    // Android silently downgraded every ride/order-status notification to
    // a default low-importance channel as a result. Register it too.
    await androidImpl?.createNotificationChannel(AndroidNotificationChannel(
      'wslha_rides',
      'تحديثات المشاوير والطلبات',
      description: 'إشعارات تغيّر حالة المشاوير والطلبات',
      importance: Importance.high,
      enableVibration: true,
    ));
  }

  Future<bool> _enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notifPrefKey) ?? true;
  }

  Future<void> show(String title, String body, {String channelId = 'wslha_rides'}) async {
    if (!await _enabled()) return;
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId == 'wslha_orders' ? 'الطلبات الجديدة' : 'تحديثات المشاوير والطلبات',
        channelDescription: 'إشعارات تغيّر حالة المشاوير والطلبات',
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        vibrationPattern: channelId == 'wslha_orders' ? Int64List.fromList([0, 400, 200, 400, 200, 400]) : null,
      ),
    );
    await _plugin.show(_nextId++, title, body, details);
  }

  /// Schedules a one-off local reminder for `whenLocal` (Cairo time) — used
  /// for airport-service pickup/flight reminders (see airport_screen.dart /
  /// driver_home_screen.dart), fired on-device even if the app is
  /// backgrounded. `id` should be stable per-ride (e.g. derived from the
  /// ride id) so re-booking/re-scheduling replaces rather than stacks.
  /// `inexactAllowWhileIdle` deliberately trades a few minutes of precision
  /// for not requiring Android 12+'s "exact alarm" permission.
  Future<void> scheduleAt(int id, String title, String body, DateTime whenLocal, {String channelId = 'wslha_rides'}) async {
    if (!await _enabled()) return;
    await init();
    if (whenLocal.isBefore(DateTime.now())) return;
    final scheduled = tz.TZDateTime.from(whenLocal, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId == 'wslha_orders' ? 'الطلبات الجديدة' : 'تحديثات المشاوير والطلبات',
          channelDescription: 'إشعارات تغيّر حالة المشاوير والطلبات',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelScheduled(int id) => _plugin.cancel(id);
}
