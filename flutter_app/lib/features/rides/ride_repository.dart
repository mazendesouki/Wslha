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

  /// `rides` only carries driver_name/driver_phone once a driver accepts —
  /// vehicle/photo details live on the driver's approved application row
  /// (driver_applications, keyed by phone). Same lookup rides.astro's
  /// loadDriverBadges() does on the web.
  Future<Map<String, dynamic>?> fetchDriverProfile(String driverPhone) async {
    final rows = await sb
        .from('driver_applications')
        .select(
          'full_name,driver_photo_url,vehicle_category,vehicle_model,vehicle_color,vehicle_year,vehicle_reg_number,vehicle_front_url,has_ac,is_clean',
        )
        .eq('phone', driverPhone)
        .eq('status', 'approved')
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : rows.first;
  }
}
