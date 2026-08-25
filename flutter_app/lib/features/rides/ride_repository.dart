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
    // 'local' | 'external' — rides_screen.dart infers this from road
    // distance (fare_calc.isExternalTrip) since it has no explicit
    // destination-governorate picker, unlike the web's rides-external.astro.
    String rideType = 'local',
    // Intermediate waypoints for a multi-stop ride (excludes the origin and
    // the final destination, which stay in from_*/to_* as usual) — e.g. a
    // customer running an errand between two legs. distanceKm/fare must
    // already be the SUM across every leg (origin→stop1→...→destination);
    // guard_ride_fare() doesn't need to know about stops itself, it just
    // re-derives fare from the total distance_km + final to_area exactly
    // like a normal single-leg ride (see db/security-29-late-arrival-and-multistop.sql).
    List<Map<String, dynamic>>? stops,
    // When true, `fare` above is only a reference estimate — guard_ride_fare()
    // still overwrites it once at INSERT (it has no per-row opt-out), but the
    // real price is whatever driver offer the customer accepts afterwards via
    // acceptPriceOffer() (fare gets overwritten again at that point; the
    // trigger only fires on INSERT, never UPDATE, so it won't clobber that
    // second write — see db/security-35-ride-price-negotiation.sql).
    bool isNegotiable = false,
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
      'ride_type': rideType,
      'is_negotiable': isNegotiable,
      if (stops != null && stops.isNotEmpty) 'stops': stops,
    }).select().single();
    return row;
  }

  /// Live list of price offers submitted by drivers on a negotiable ride —
  /// the customer's tracking screen renders this while the ride is still
  /// unclaimed (status='pending', driver_phone null).
  Stream<List<Map<String, dynamic>>> watchRideOffers(String rideId) {
    return sb.from('ride_price_offers').stream(primaryKey: ['id']).eq('ride_id', rideId);
  }

  /// Customer picks one driver's price offer — locks the ride to that
  /// driver at that price (accept_ride_price_offer, db/security-35).
  /// Returns null on success, or a message to show (a recognized reason
  /// mapped to Arabic, otherwise the raw error so a real failure is
  /// diagnosable instead of a blanket "try another offer").
  Future<String?> acceptPriceOffer(String rideId, String offerId, String customerPhone) async {
    try {
      await sb.rpc('accept_ride_price_offer', params: {
        'p_ride_id': rideId,
        'p_offer_id': offerId,
        'p_customer_phone': customerPhone,
      });
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('ride_already_taken')) return 'الرحلة اتقفلت بالفعل على سائق تاني.';
      if (msg.contains('offer_no_longer_available')) return 'العرض ده مش متاح دلوقتي، جرّب عرض تاني.';
      if (msg.contains('not_your_ride')) return 'حصل خطأ في التحقق من الرحلة.';
      return 'تعذّر قبول العرض: $msg';
    }
  }

  /// Customer dismisses a specific driver's offer without accepting it —
  /// it just disappears from their own list (reject_ride_price_offer,
  /// db/security-35). Purely a customer-side filter, doesn't stop the
  /// driver from being picked via a different offer round.
  Future<bool> rejectPriceOffer(String rideId, String offerId, String customerPhone) async {
    try {
      await sb.rpc('reject_ride_price_offer', params: {
        'p_ride_id': rideId,
        'p_offer_id': offerId,
        'p_customer_phone': customerPhone,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Realtime status tracking, same table/columns driver-dashboard.astro
  /// updates (status, driver_phone, driver_name).
  Stream<List<Map<String, dynamic>>> watchRide(String rideId) {
    return sb.from('rides').stream(primaryKey: ['id']).eq('id', rideId);
  }

  /// Same table track.astro's live map polls/subscribes to — the driver
  /// app pings this every ~8s while online/on a job (see
  /// DriverRepository.pingLocation) so this stream reflects real movement.
  Stream<List<Map<String, dynamic>>> watchDriverLocation(String driverPhone) {
    return sb.from('driver_locations').stream(primaryKey: ['driver_phone']).eq('driver_phone', driverPhone);
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
