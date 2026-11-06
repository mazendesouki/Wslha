import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'api_session.dart';
import 'notifications.dart';
import 'session.dart';
import 'supabase_client.dart';

/// Real push (Firebase Cloud Messaging) — delivers even while the app is
/// closed, unlike AppNotifications (core/notifications.dart) which only
/// fires from in-app Realtime updates while the process is alive. Needs a
/// Firebase project registered for each flavor's applicationId
/// (android/app/google-services.json) — see MOBILE_APP.md. Fails quietly
/// if that's not set up yet, so the app still works without push.
class PushRegistrar {
  PushRegistrar._();
  static final _registeredPhones = <String>{};
  static bool _firebaseReady = false;

  // Broadcasts every foreground FCM message's data payload — lets a screen
  // react the instant a push lands (e.g. the driver's dispatch-offer
  // screen re-checking for a new offer via security-21's push) instead of
  // only showing a tray notification.
  static final _dataController = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get onMessageData => _dataController.stream;

  static Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;
    await Firebase.initializeApp();
    _firebaseReady = true;

    // Foreground messages don't show a system-tray banner on Android by
    // default — FCM only auto-displays the `notification` payload while
    // the app is backgrounded/terminated. Show it manually here.
    FirebaseMessaging.onMessage.listen((msg) {
      final n = msg.notification;
      if (n != null) {
        AppNotifications.instance.show(
          n.title ?? '',
          n.body ?? '',
          channelId: msg.data['channel'] as String? ?? 'wslha_rides',
        );
      }
      if (msg.data.isNotEmpty) _dataController.add(msg.data);
    });
  }

  /// Call right after login and again on cold start with an existing
  /// session — idempotent (guarded per phone), safe to call repeatedly.
  static Future<void> registerForSession(UserSession session) async {
    if (_registeredPhones.contains(session.phone)) return;
    try {
      await _ensureFirebase();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null) {
        debugPrint('[push] getToken() returned null for ${session.phone}');
        return;
      }
      debugPrint('[push] registering token ${token.substring(0, 12)}... for ${session.phone}');

      await _registerToken(session.phone, token);
      debugPrint('[push] upsert_device_token ok');
      _registeredPhones.add(session.phone);

      messaging.onTokenRefresh.listen((newToken) {
        _registerToken(session.phone, newToken);
      });
    } catch (e, st) {
      // No google-services.json yet, or the device has no Play Services —
      // the app should keep working without push either way.
      debugPrint('[push] registerForSession failed: $e\n$st');
    }
  }

  /// Access-token-first, phone-trust-RPC-fallback — upsert_device_token
  /// trusted a bare p_phone with no check at all (security-178), so a
  /// direct call could register a device token against any victim's
  /// phone. /api/push/register derives the phone from the caller's own
  /// verified session token instead; falls back to the old direct RPC
  /// (now at least requiring p_phone to be a real account) when there's
  /// no session token yet, same contract as every other migrated call.
  static Future<void> _registerToken(String phone, String token) async {
    final data = await ApiSession.postJson('/api/push/register', {
      'fcm_token': token,
      'platform': 'android',
    });
    if (data != null) return;
    await sb.rpc('upsert_device_token', params: {
      'p_phone': phone,
      'p_token': token,
      'p_platform': 'android',
    });
  }
}
