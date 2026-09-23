import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';

/// Same `rides` table the web app writes to (rides.astro's sbCreateRide()) —
/// only the core columns needed for a working booking (vehicle-model
/// selection and free-text notes are a web-only extra, skipped here).
class RideRepository {
  /// Live surge multiplier from current_surge_multiplier() (db/security-62)
  /// — always 1.0 unless the admin has dynamic_pricing_enabled on AND
  /// current demand/driver-supply crosses a threshold. A failed/slow fetch
  /// just falls back to 1.0 (no surge shown) rather than blocking booking.
  Future<double> fetchSurgeMultiplier({String rideType = 'local'}) async {
    try {
      final result = await sb.rpc('current_surge_multiplier', params: {'p_ride_type': rideType});
      return (result as num?)?.toDouble() ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  /// Late-arrival/late-boarding penalty rows for a ride (db/security-63,
  /// security-64) — 'penalty' wallet_transactions with reference_id set
  /// to the ride id. Distinguishing driver-late vs. customer-late is just
  /// matching `phone` against the ride's driver_phone/customer_phone,
  /// since only the charged party's own phone gets a row for it. Used by
  /// both invoice dialogs to show the real final total, not just the
  /// original fare.
  Future<List<Map<String, dynamic>>> fetchRidePenalties(String rideId) async {
    try {
      final rows = await sb.from('wallet_transactions').select('phone,amount,note').eq('reference_id', rideId).eq('type', 'penalty');
      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return [];
    }
  }

  /// Real, live count of drivers who are online, free (not on a ride/order)
  /// and updated in the last 10 minutes — db/security-91's narrow RPC (never
  /// a raw driver_locations SELECT, which would leak phone/name/lat/lng).
  /// Powers the rides screen's live-status card; null on any failure so the
  /// caller can just hide the card instead of showing a stale/fake number.
  Future<int?> fetchAvailableDriversCount() async {
    try {
      final result = await sb.rpc('get_available_drivers_count');
      return (result as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

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
    // 'regular' | 'ac' — same column/multiplier airport rides already use
    // (airport_quality_tier, see airport/airport_fare.dart's
    // qualityMultiplier) reused here for local/external rides so a driver
    // without AC can't be matched to a customer who specifically asked for
    // one — see db/security-55-local-ride-ac-tier.sql. Null/omitted means
    // no preference (back-compat with rides booked before this existed).
    String? qualityTier,
    // Booking for later instead of now (db/security-76) — the ride is
    // inserted with status 'scheduled' instead of 'pending', which the
    // existing dispatch/push triggers both explicitly skip (they only
    // fire on status = 'pending'), so no driver sees or is notified about
    // it yet. A pg_cron job flips it to 'pending' (and fires the same
    // dispatch/push calls those triggers would have) once scheduledAt
    // gets within the admin-configured lead window.
    DateTime? scheduledAt,
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
      'status': scheduledAt != null ? 'scheduled' : 'pending',
      'ride_type': rideType,
      'is_negotiable': isNegotiable,
      if (stops != null && stops.isNotEmpty) 'stops': stops,
      if (qualityTier != null && qualityTier != 'regular') 'airport_quality_tier': qualityTier,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    }).select().single();
    return row;
  }

  /// Upcoming scheduled rides this customer hasn't cancelled yet — shown on
  /// a dedicated "رحلاتي المجدولة" list so they can review/cancel before
  /// a driver ever sees the request (see createRide's scheduledAt doc).
  Future<List<Map<String, dynamic>>> fetchScheduledRides(String phone) async {
    final rows = await sb
        .from('rides')
        .select()
        .eq('customer_phone', phone)
        .eq('status', 'scheduled')
        .order('scheduled_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<bool> cancelScheduledRide(String rideId, String phone) async {
    final result = await sb.rpc('cancel_scheduled_ride', params: {'p_ride_id': rideId, 'p_customer_phone': phone});
    return result == true;
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

  /// Customer cancels their own ride — allowed while it's still pending or
  /// while a driver has accepted/arrived but hasn't started the trip yet
  /// (customer_cancel_ride, db/security-40). No matching driver-side
  /// cancel exists anywhere in the app: once a driver accepts, cancelling
  /// is a customer-only right.
  /// Returns null on success, or a message to show.
  Future<String?> cancelRide(String rideId, String customerPhone) async {
    try {
      await sb.rpc('customer_cancel_ride', params: {
        'p_ride_id': rideId,
        'p_customer_phone': customerPhone,
      });
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cannot_cancel_now')) return 'الرحلة بدأت بالفعل، مش ممكن تلغيها دلوقتي.';
      if (msg.contains('not_your_ride')) return 'حصل خطأ في التحقق من الرحلة.';
      return 'تعذّر إلغاء الرحلة: $msg';
    }
  }

  /// Finds a ride this phone is still "in" (not completed/cancelled) so
  /// app startup can resume into it instead of the home screen — fixes the
  /// ride "disappearing" after Android kills the app in the background
  /// (e.g. the user switches to another app mid-ride) and Flutter
  /// cold-starts back at its default route on return, losing whatever
  /// screen was showing before. Returns the full row (not just the id) —
  /// the driver-side resume path needs every column to repopulate
  /// ActiveJobStore, not just enough to open RideTrackingScreen.
  Future<Map<String, dynamic>?> findActiveRide(String phone, {required bool asDriver}) async {
    final local = normalizeEgyptianPhone(phone);
    final intl = toIntlEgyptianPhone(phone);
    final column = asDriver ? 'driver_phone' : 'customer_phone';
    final filter = '$column.eq.$local,$column.eq.$intl';
    final rows = await sb
        .from('rides')
        .select()
        .or(filter)
        .not('status', 'in', '(completed,cancelled)')
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
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
    if (rows.isEmpty) return null;
    final profile = Map<String, dynamic>.from(rows.first);
    // Prefer the driver's own up-to-date photo (accounts.avatar_url, the
    // same one shown on their "حسابي" screen and editable there anytime)
    // over the frozen registration selfie, so the customer always sees the
    // same photo the driver currently has on their profile — db/security-66
    // seeds avatar_url from driver_photo_url at approval time, but a driver
    // can replace it afterward from their own app. `accounts` has no direct
    // SELECT grant for anon/authenticated (RLS allows it but the column
    // grants don't — see AccountRepository.lookupAccount's comment), so
    // this goes through the same lookup_account RPC instead of `.select()`.
    final avatarUrl = await fetchAccountAvatar(driverPhone);
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      profile['driver_photo_url'] = avatarUrl;
    }
    return profile;
  }

  /// Any account's current profile photo by phone (driver or customer) —
  /// via lookup_account (security definer), since `accounts` itself has no
  /// direct SELECT grant for anon/authenticated.
  Future<String?> fetchAccountAvatar(String phone) async {
    final rows = await sb.rpc('lookup_account', params: {'p_phone': phone});
    if (rows is List && rows.isNotEmpty) return rows.first['avatar_url'] as String?;
    return null;
  }
}
