import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shares the caller's live GPS position over WhatsApp — opens WhatsApp's
/// own contact picker (no phone number pre-filled) so it can go to
/// whoever the customer wants (a friend, family, the driver themselves —
/// their call), instead of being locked to one fixed recipient. Returns
/// false (silently) on a denied location permission or a failed launch;
/// the caller decides how to surface that.
Future<bool> shareLocationOnWhatsApp() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    return false;
  }

  final pos = await Geolocator.getCurrentPosition();
  final mapsUrl = 'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
  final text = Uri.encodeComponent('📍 موقعي الحالي: $mapsUrl');
  final uri = Uri.parse('https://wa.me/?text=$text');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Shares a live-tracking web link (ride-track.astro, no login required) for
/// an in-progress ride — the "مشاركة الرحلة" safety feature: opens WhatsApp's
/// contact picker (no fixed recipient) with a message a family member can
/// open in any browser to watch the driver's live location + ride status,
/// without needing the app installed. Same open-picker pattern as
/// shareLocationOnWhatsApp() above.
Future<bool> shareRideTracking({
  required String rideId,
  String? fromArea,
  String? toArea,
  String? driverName,
}) async {
  final route = (fromArea != null && toArea != null) ? '$fromArea ← $toArea' : null;
  final link = 'https://wslha.co/ride-track?id=$rideId';
  final lines = [
    '🚖 بتابع رحلتي معاك عشان الأمان',
    if (route != null) route,
    if (driverName != null && driverName.isNotEmpty) 'السائق: $driverName',
    link,
  ];
  final text = Uri.encodeComponent(lines.join('\n'));
  final uri = Uri.parse('https://wa.me/?text=$text');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
