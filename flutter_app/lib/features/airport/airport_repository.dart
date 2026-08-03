import '../../core/supabase_client.dart';
import 'airport_fare.dart';

/// Same driver_applications lookup rides.astro/airport.astro use — only
/// approved drivers' real vehicles are offered, not a static catalog.
class AirportRepository {
  Future<List<RegisteredVehicle>> fetchRegisteredVehicles() async {
    final rows = await sb
        .from('driver_applications')
        .select('vehicle_category,vehicle_model,vehicle_year')
        .eq('status', 'approved');

    final byKey = <String, RegisteredVehicle>{};
    for (final r in rows) {
      final cat = r['vehicle_category'] as String?;
      final name = (r['vehicle_model'] as String?)?.trim();
      if (cat == null || name == null || name.isEmpty || !vehicleCategoryInfo.containsKey(cat)) continue;
      final year = (r['vehicle_year'] as num?)?.toInt() ?? DateTime.now().year;
      final key = '$cat|$name';
      final existing = byKey[key];
      if (existing != null) {
        byKey[key] = RegisteredVehicle(
          id: key,
          category: cat,
          name: name,
          yearFrom: existing.yearFrom < year ? existing.yearFrom : year,
          yearTo: existing.yearTo > year ? existing.yearTo : year,
        );
      } else {
        byKey[key] = RegisteredVehicle(id: key, category: cat, name: name, yearFrom: year, yearTo: year);
      }
    }
    return byKey.values.toList();
  }

  /// Same `rides` table + ride_type='airport' airport.astro writes to.
  Future<Map<String, dynamic>?> createAirportRide({
    required String customerPhone,
    required String customerName,
    required String fromArea,
    required double fromLat,
    required double fromLng,
    required String airportName,
    required double airportLat,
    required double airportLng,
    required double distanceKm,
    required int fare,
    required int etaMinutes,
    required int passengers,
    required int vehicleYear,
    required String vehicleCategory,
    required String qualityTier,
    required String notes,
  }) async {
    final row = await sb.from('rides').insert({
      'customer_phone': customerPhone,
      'customer_name': customerName,
      'from_area': fromArea,
      'from_lat': fromLat,
      'from_lng': fromLng,
      'to_area': airportName,
      'to_lat': airportLat,
      'to_lng': airportLng,
      'distance_km': distanceKm,
      'fare': fare,
      'eta_minutes': etaMinutes,
      'passengers': passengers,
      'payment': 'cash',
      'vehicle_year': vehicleYear,
      'airport_vehicle_category': vehicleCategory,
      'airport_quality_tier': qualityTier,
      'notes': notes,
      'status': 'pending',
      'ride_type': 'airport',
    }).select().single();
    return row;
  }
}
