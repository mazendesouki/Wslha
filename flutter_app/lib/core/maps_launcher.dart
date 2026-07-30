import 'package:url_launcher/url_launcher.dart';

/// Opens turn-by-turn navigation in the Google Maps app (or a browser
/// fallback if it isn't installed) from the device's live current location
/// to [lat]/[lng] — same destination the driver taps "افتح Google Maps
/// للملاحة" for on driver-dashboard.astro, just using Maps' documented
/// universal URL scheme (`api=1&destination=...`) instead of computing the
/// origin ourselves, so Maps handles "my location" natively.
Future<bool> openMapsNavigation(double lat, double lng) {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A Static Maps image URL with pickup (teal) + dropoff (red) pins — a
/// lightweight route preview without needing the Directions API (no
/// polyline). Uses the same Android-app-restricted key as Places
/// Autocomplete; if "Maps Static API" isn't enabled on that key yet, the
/// image request itself fails and the caller's Image.network errorBuilder
/// just hides it — the navigation button above still works regardless.
String staticRouteMapUrl({
  required double fromLat,
  required double fromLng,
  required double toLat,
  required double toLng,
  int width = 640,
  int height = 280,
}) {
  const key = 'AIzaSyCSJQuStVvhhNhbAZF1tuwO_IacicXqyhM';
  final markers = 'markers=color:0x0E4B49%7Clabel:A%7C$fromLat,$fromLng'
      '&markers=color:0xEF4444%7Clabel:B%7C$toLat,$toLng';
  return 'https://maps.googleapis.com/maps/api/staticmap'
      '?size=${width}x$height&scale=2&$markers&key=$key';
}
