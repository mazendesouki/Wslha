import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// System-tray notifications while the app is running — the "إشعارات"
/// toggle in SettingsScreen (shared_preferences key below) gates these.
/// This is local-only (flutter_local_notifications): it fires from
/// in-app Realtime updates, not a server push, so it only works while the
/// app process is alive. A real push (Firebase Cloud Messaging) needs a
/// Firebase project set up on the user's own Google account first — out of
/// scope until that's requested.
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
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<bool> _enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notifPrefKey) ?? true;
  }

  Future<void> show(String title, String body) async {
    if (!await _enabled()) return;
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'wslha_rides',
        'تحديثات المشاوير والطلبات',
        channelDescription: 'إشعارات تغيّر حالة المشاوير والطلبات',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(_nextId++, title, body, details);
  }
}
