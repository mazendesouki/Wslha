import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Same Google Maps key + Damietta bounding box the web app uses
/// (rides.astro's LatLngBounds({lat:31.20,lng:31.50},{lat:31.65,lng:32.10})),
/// just called via the REST Places API instead of the JS SDK.
const String _gmapsKey = 'AIzaSyAKvFfBYNDcTZgvZZH5s_lQbOc24LNjLsY';

class PlaceSuggestion {
  final String description;
  final String placeId;
  PlaceSuggestion(this.description, this.placeId);
}

class PlaceResult {
  final String name;
  final double lat;
  final double lng;
  PlaceResult(this.name, this.lat, this.lng);
}

class PlacesService {
  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    if (input.trim().isEmpty) return [];
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': input,
      'key': _gmapsKey,
      'language': 'ar',
      'components': 'country:eg',
      // Damietta bounding rectangle bias, same as the web app.
      'locationbias': 'rectangle:31.20,31.50|31.65,32.10',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final predictions = body['predictions'] as List<dynamic>? ?? [];
    return predictions
        .map((p) => PlaceSuggestion(p['description'] as String, p['place_id'] as String))
        .toList();
  }

  Future<PlaceResult?> details(String placeId) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'key': _gmapsKey,
      'language': 'ar',
      'fields': 'name,formatted_address,geometry',
    });
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>?;
    if (result == null) return null;
    final loc = result['geometry']?['location'] as Map<String, dynamic>?;
    if (loc == null) return null;
    return PlaceResult(
      (result['name'] as String?) ?? (result['formatted_address'] as String? ?? ''),
      (loc['lat'] as num).toDouble(),
      (loc['lng'] as num).toDouble(),
    );
  }
}
