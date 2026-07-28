import '../../core/supabase_client.dart';

/// Same `rides` table the web app writes to (rides.astro's sbCreateRide()) —
/// only the core columns needed for a working booking (vehicle-model
/// selection and free-text notes are a web-only extra, skipped here).
class RideRepository {
  Future<Map<String, dynamic>?> createRide({
    required String customerPhone,
    required String customerName,
    required String fromArea,
    required double fromLat,
    required double fromLng,
    required String toArea,
    required double toLat,
    required double toLng,
    required double distanceKm,
    required int fare,
    required int etaMinutes,
    required int passengers,
    required String payment,
  }) async {
    final row = await sb.from('rides').insert({
      'customer_phone': customerPhone,
      'customer_name': customerName,
      'from_area': fromArea,
      'from_lat': fromLat,
      'from_lng': fromLng,
      'to_area': toArea,
      'to_lat': toLat,
      'to_lng': toLng,
      'distance_km': distanceKm,
      'fare': fare,
      'eta_minutes': etaMinutes,
      'passengers': passengers,
      'payment': payment,
      'status': 'pending',
      'ride_type': 'local',
    }).select().single();
    return row;
  }

  /// Realtime status tracking, same table/columns driver-dashboard.astro
  /// updates (status, driver_phone, driver_name).
  Stream<List<Map<String, dynamic>>> watchRide(String rideId) {
    return sb.from('rides').stream(primaryKey: ['id']).eq('id', rideId);
  }

  Future<void> cancelRide(String rideId) async {
    await sb.from('rides').update({'status': 'cancelled'}).eq('id', rideId);
  }
}
