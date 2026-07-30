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

/// Android-app-restricted Maps keys only accept requests carrying these two
/// headers — normally added automatically by Google's own Android SDKs, but
/// we're calling the REST API directly (package:http), so they have to be
/// set by hand or every call comes back REQUEST_DENIED with "empty referer"
/// even though the restriction itself is configured correctly.
/// TODO: this is the customer flavor's package + the shared debug signing
/// cert — re-derive both once release signing replaces the debug keystore
/// (rides booking is customer-only for now, see app.dart's flavor routing).
const Map<String, String> _androidKeyHeaders = {
  'X-Android-Package': 'co.wslha.wslha_app',
  'X-Android-Cert': 'E607280747B7CA9067705DE266C45ADABC035458',
};

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

  /// [types] mirrors the web's Autocomplete `types` option — e.g. 'airport'
  /// for airport.astro's airport picker (restricts results to airports
  /// instead of the Damietta-biased general address search).
  Future<List<PlaceSuggestion>> autocomplete(String input, {String? types}) async {
    if (input.trim().isEmpty) return [];
    final params = <String, String>{
      'input': input,
      'key': _gmapsKey,
      'language': 'ar',
      'components': 'country:eg',
    };
    if (types != null) {
      params['types'] = types;
    } else {
      // Damietta bounding rectangle bias, same as the web app — only for
      // the general address search, not the airport-restricted one.
      params['locationbias'] = 'rectangle:31.20,31.50|31.65,32.10';
    }
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', params);
    try {
      final res = await http.get(uri, headers: _androidKeyHeaders);
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

  /// Turns a GPS fix into a readable address — same Geocoding API call
  /// rides.astro's "📍 موقعي" button makes. Falls back to a generic label
  /// (matching the web's fallback) if the lookup fails, since the caller
  /// already has real lat/lng regardless of whether this succeeds.
  Future<String> reverseGeocode(double lat, double lng) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '$lat,$lng',
      'key': _gmapsKey,
      'language': 'ar',
    });
    try {
      final res = await http.get(uri, headers: _androidKeyHeaders);
      if (res.statusCode != 200) return 'موقعي الحالي';
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'OK') return 'موقعي الحالي';
      final results = body['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return 'موقعي الحالي';
      return (results.first['formatted_address'] as String?) ?? 'موقعي الحالي';
    } catch (_) {
      return 'موقعي الحالي';
    }
  }

  Future<PlaceResult?> details(String placeId) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'key': _gmapsKey,
      'language': 'ar',
      'fields': 'name,formatted_address,geometry',
    });
    final res = await http.get(uri, headers: _androidKeyHeaders);
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
