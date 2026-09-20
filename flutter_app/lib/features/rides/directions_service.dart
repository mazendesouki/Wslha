import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'places_service.dart';

/// Same Android-app-restricted key as places_service.dart — see that file's
/// header comment for why it needs the X-Android-Package/X-Android-Cert
/// headers set by hand. "Directions API" has to be enabled on this key in
/// Google Cloud Console for this to return real routes; until then (or on
/// any other failure — no network, ZERO_RESULTS, ...) fetchRoadRoute()
/// returns null and every caller falls back to fare_calculator's
/// haversine × roadFactor estimate, so nothing ever breaks either way.
const String _gmapsKey = 'AIzaSyCSJQuStVvhhNhbAZF1tuwO_IacicXqyhM';
const Map<String, String> _androidKeyHeaders = {
  'X-Android-Package': 'co.wslha.wslha_app',
  'X-Android-Cert': 'E607280747B7CA9067705DE266C45ADABC035458',
};

class RoadRoute {
  final double km;
  final int minutes;
  const RoadRoute(this.km, this.minutes);
}

/// Real routed road distance/duration between a ride's actual pickup,
/// waypoints and dropoff — replaces the flat straightKm × 1.35 estimate
/// with what the Directions API actually says the road distance is,
/// following the same origin → stops → destination order the ride books
/// with (not the driver's live GPS position at request time, unlike the
/// "افتح خرائط جوجل" navigation button elsewhere in the app).
class DirectionsService {
  Future<RoadRoute?> fetchRoadRoute(List<PlaceResult> points) async {
    if (points.length < 2) return null;
    final origin = points.first;
    final destination = points.last;
    final waypoints = points.sublist(1, points.length - 1);

    final params = <String, String>{
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
      'mode': 'driving',
      'language': 'ar',
      'key': _gmapsKey,
    };
    if (waypoints.isNotEmpty) {
      params['waypoints'] = waypoints.map((p) => '${p.lat},${p.lng}').join('|');
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', params);
    try {
      final res = await http.get(uri, headers: _androidKeyHeaders).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final routes = body['routes'] as List<dynamic>? ?? [];
      if (routes.isEmpty) return null;
      final legs = routes.first['legs'] as List<dynamic>? ?? [];
      if (legs.isEmpty) return null;

      double meters = 0;
      int seconds = 0;
      for (final leg in legs) {
        meters += ((leg['distance']?['value'] as num?) ?? 0).toDouble();
        seconds += ((leg['duration']?['value'] as num?) ?? 0).toInt();
      }
      if (meters <= 0) return null;
      return RoadRoute(meters / 1000.0, (seconds / 60).ceil());
    } catch (_) {
      return null;
    }
  }
}
