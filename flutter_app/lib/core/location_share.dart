import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'phone_utils.dart';

/// Shares the caller's live GPS position with [driverPhone] over WhatsApp
/// — for when a description of the spot isn't enough and the customer
/// just wants the driver to see exactly where they're standing. Returns
/// false (silently) on a denied location permission or a failed launch;
/// the caller decides how to surface that.
Future<bool> shareLocationOnWhatsApp(String driverPhone) async {
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
  final intl = toIntlEgyptianPhone(driverPhone).replaceFirst('+', '');
  final uri = Uri.parse('https://wa.me/$intl?text=$text');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
