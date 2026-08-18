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
