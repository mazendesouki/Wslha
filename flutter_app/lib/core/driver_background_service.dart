import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'supabase_client.dart';

/// Keeps a driver's location updating (and therefore keeps them visibly
/// "online"/matchable for new ride and delivery broadcasts) even after the
/// app is fully closed — not just backgrounded. Plain in-app Timers
/// (DriverHomeScreen's old _locationTimer) only run while the Dart UI
/// isolate is alive, which Android suspends/kills once the app isn't in
/// the foreground; a real Android foreground service (persistent
/// notification, required by the OS — not optional) is the only way to
/// keep running reliably after that.
///
/// Talks to Supabase over plain REST (not the supabase_flutter SDK client)
/// because Android runs this callback in a separate background isolate —
/// Dart isolates don't share memory, so the SDK client initialized in the
/// main isolate (core/supabase_client.dart's `sb`) doesn't exist here; a
/// stateless HTTP call needs no shared setup at all.
const String _notificationChannelId = 'wslha_driver_online';
const int _notificationId = 9001;

Map<String, String> get _restHeaders => {
      'apikey': supabaseAnonKey,
      'Authorization': 'Bearer $supabaseAnonKey',
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    };

/// Call once at app startup (both configures the service and is cheap/
/// idempotent to call again — it doesn't start it, just registers it).
Future<void> initDriverBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _notificationChannelId,
      initialNotificationTitle: 'وصّلها — متصل',
      initialNotificationContent: 'بتتابع موقعك عشان توصلّك طلبات قريبة',
      foregroundServiceNotificationId: _notificationId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

/// Starts (or, if already running, just re-registers the current phone —
/// e.g. after a relaunch restores "online" status) the background pings.
/// Never throws — a failure here (permission not fully granted yet, a
/// platform quirk) should just mean the driver keeps working with
/// foreground-only location like before this feature existed, not a
/// crash or a blocked "غير متصل → متصل" toggle.
Future<void> startDriverBackgroundService(String phone) async {
  try {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
    service.invoke('setPhone', {'phone': phone});
  } catch (e) {
    debugPrint('startDriverBackgroundService failed: $e');
  }
}

Future<void> stopDriverBackgroundService() async {
  try {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stopService');
    }
  } catch (e) {
    debugPrint('stopDriverBackgroundService failed: $e');
  }
}

/// Runs in a background isolate/process once the service starts — has no
/// access to anything set up in the main isolate (session, Supabase SDK
/// client, ActiveJobStore, ...), only what's passed in via service.invoke.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  String? phone;

  service.on('setPhone').listen((event) {
    phone = event?['phone'] as String?;
  });
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 10), (timer) async {
    final p = phone;
    if (p == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await http.post(
        Uri.parse('$supabaseUrl/rest/v1/driver_locations'),
        headers: _restHeaders,
        body: jsonEncode({
          'driver_phone': p,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'heading': pos.heading,
          'updated_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {
      // Best-effort — a single missed background ping (no signal, GPS
      // momentarily unavailable) isn't worth surfacing anywhere; the next
      // tick 10s later tries again.
    }
  });
}
