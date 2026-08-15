import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: androidInit));
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    // Must exist before a background/terminated FCM message tagged with
    // this channel_id (see supabase/functions/send-push) arrives, or
    // Android falls back to a default low-importance channel.
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      'wslha_orders',
      'الطلبات الجديدة',
      description: 'إشعار فوري عند وصول طلب جديد',
      importance: Importance.high,
    ));
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
