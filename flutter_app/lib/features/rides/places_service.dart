import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Separate key from the one the web app uses — that key is restricted to
/// HTTP referrers (browser-only), which Google's Places API rejects outright
/// for any server-to-server call ("API keys with referer restrictions cannot
/// be used with this API"). This key is restricted to the three Android
/// app package IDs + debug signing fingerprint instead. Same Damietta
/// bounding box bias as the web app's rides.astro.
const String _gmapsKey = 'AIzaSyCSJQuStVvhhNhbAZF1tuwO_IacicXqyhM';

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
  /// Set after every autocomplete() call — null on success, otherwise a
  /// human-readable reason. TEMPORARY diagnostic aid: on-device debugging
  /// (logcat over wireless ADB) has proven unreliable here, so AddressField
  /// surfaces this directly in the UI instead of requiring a terminal.
  String? lastError;

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
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        lastError = 'HTTP ${res.statusCode}: ${res.body}';
        return [];
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String?;
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        lastError = '${status ?? '?'}: ${body['error_message'] ?? ''}';
        return [];
      }
      lastError = null;
      final predictions = body['predictions'] as List<dynamic>? ?? [];
      return predictions
          .map((p) => PlaceSuggestion(p['description'] as String, p['place_id'] as String))
          .toList();
    } catch (e) {
      lastError = 'Exception: $e';
      return [];
    }
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
