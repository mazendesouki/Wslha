import 'supabase_client.dart';

/// Admin-configurable pricing (app_settings) — mirrors what
/// src/data/airports.ts's loadPricingSettings() does on the web, and what
/// guard_ride_fare() (db/security-11-pricing-settings.sql) reads
/// server-side for local/external rides. Airport rides have no
/// server-side fare recompute, so PricingSettings.load() is what actually
/// makes airport pricing admin-configurable for this app.
///
/// All fields are mutable with the same hardcoded defaults the formulas
/// used before this existed — a failed/slow fetch just means the app
/// keeps using those defaults instead of blocking booking.
class PricingSettings {
  PricingSettings._();

  static double localBaseFee = 25;
  static double localMinFare = 40;
  static double localRateSedan = 8;

  static double airportBaseFee = 300;
  static double airportMinFare = 2500;
  static double airportRateSedan = 12;
  static double airportRateSuv = 15.6;
  static double airportRateVan = 16.8;

  static bool _loaded = false;

  /// Fire-and-forget is fine to call repeatedly (e.g. from each screen's
  /// initState) — only the first successful fetch actually applies.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final rows = await sb.from('app_settings').select('key,value').inFilter('key', [
        'local_base_fee', 'local_min_fare', 'local_rate_sedan',
        'airport_base_fee', 'airport_min_fare', 'airport_rate_sedan', 'airport_rate_suv', 'airport_rate_van',
      ]);
      double? num(String key) {
        final row = (rows as List).cast<Map<String, dynamic>>().where((r) => r['key'] == key).toList();
        if (row.isEmpty) return null;
        return double.tryParse('${row.first['value']}');
      }

      localBaseFee    = num('local_base_fee') ?? localBaseFee;
      localMinFare     = num('local_min_fare') ?? localMinFare;
      localRateSedan   = num('local_rate_sedan') ?? localRateSedan;
      airportBaseFee   = num('airport_base_fee') ?? airportBaseFee;
      airportMinFare   = num('airport_min_fare') ?? airportMinFare;
      airportRateSedan = num('airport_rate_sedan') ?? airportRateSedan;
      airportRateSuv   = num('airport_rate_suv') ?? airportRateSuv;
      airportRateVan   = num('airport_rate_van') ?? airportRateVan;
      _loaded = true;
    } catch (_) {
      // Network hiccup — keep the hardcoded defaults.
    }
  }
}
