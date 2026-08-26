import 'package:url_launcher/url_launcher.dart';
import 'phone_utils.dart';

/// Opens the device's phone dialer pre-filled with [phone] — same "📞
/// اتصل" action driver-dashboard.astro shows on the active-trip card, for
/// both directions (driver calling the customer, customer calling the
/// driver).
Future<bool> callPhone(String phone) {
  final uri = Uri(scheme: 'tel', path: normalizeEgyptianPhone(phone));
  return launchUrl(uri);
}

/// Opens a WhatsApp chat with [phone] — for when a call doesn't get
/// through and the driver needs another way to find the customer (or vice
/// versa). wa.me needs the international form without the leading '+'.
Future<bool> openWhatsApp(String phone) {
  final intl = toIntlEgyptianPhone(phone).replaceFirst('+', '');
  final uri = Uri.parse('https://wa.me/$intl');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Opens WhatsApp's own contact/chat picker pre-filled with [text] — no
/// destination phone number, since this is for sharing something (an
/// invoice) with whichever contact the user picks, not a fixed party like
/// openWhatsApp() above.
Future<bool> shareTextViaWhatsApp(String text) {
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
