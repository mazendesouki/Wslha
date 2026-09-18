import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/safety/emergency_contacts_repository.dart';
import 'supabase_client.dart';

class SosResult {
  final bool hadContacts;
  final bool hasLocation;
  final bool smsOpened;
  const SosResult({required this.hadContacts, required this.hasLocation, required this.smsOpened});
}

/// Triggering SOS: (1) best-effort GPS fix, (2) logs a permanent record to
/// sos_alerts (db/security-68) regardless of what happens next, so there's
/// always an audit trail even if the phone can't actually send anything,
/// (3) opens the native SMS app pre-filled with the live location + (if
/// mid-ride) the same public ride-track.astro link "مشاركة الرحلة" uses,
/// addressed to every saved emergency contact at once. The user still has
/// to hit send themselves — neither Android nor iOS let a third-party app
/// silently send SMS, which is the correct, expected behavior.
class SosService {
  final _contactsRepo = EmergencyContactsRepository();

  Future<SosResult> trigger({
    required String phone,
    required String role, // 'customer' | 'driver'
    String? rideId,
  }) async {
    Position? pos;
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
        pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
      }
    } catch (_) {}

    try {
      await sb.rpc('log_sos_alert', params: {
        'p_phone': phone,
        'p_role': role,
        if (rideId != null) 'p_ride_id': rideId,
        if (pos != null) 'p_lat': pos.latitude,
        if (pos != null) 'p_lng': pos.longitude,
      });
    } catch (_) {}

    List<EmergencyContact> contacts = [];
    try {
      contacts = await _contactsRepo.list(phone);
    } catch (_) {}

    final lines = [
      '🆘 حالة طوارئ — محتاج مساعدة دلوقتي',
      if (pos != null) '📍 موقعي الحالي: https://maps.google.com/?q=${pos.latitude},${pos.longitude}',
      if (rideId != null) '🚖 تابع رحلتي مباشرة: https://wslha.co/ride-track?id=$rideId',
    ];
    final message = lines.join('\n');

    var smsOpened = false;
    if (contacts.isNotEmpty) {
      final recipients = contacts.map((c) => c.phone).join(',');
      final uri = Uri(scheme: 'sms', path: recipients, queryParameters: {'body': message});
      try {
        smsOpened = await launchUrl(uri);
      } catch (_) {}
    }

    return SosResult(hadContacts: contacts.isNotEmpty, hasLocation: pos != null, smsOpened: smsOpened);
  }
}
