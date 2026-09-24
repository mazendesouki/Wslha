import 'package:geolocator/geolocator.dart';
import '../../core/supabase_client.dart';

class RideSettlement {
  final double fare;
  final double commission;
  final double driverEarn;
  final double rate;
  RideSettlement({required this.fare, required this.commission, required this.driverEarn, required this.rate});
}

class PendingOffer {
  final String offerId;
  final String targetType; // 'ride' | 'order'
  final Map<String, dynamic> data;
  final DateTime? expiresAt;
  PendingOffer(this.offerId, this.targetType, this.data, {this.expiresAt});
}

/// Same driver_locations table + dispatch RPCs driver-dashboard.astro uses
/// (get_my_pending_offer / accept_dispatch_offer / reject_dispatch_offer).
class DriverRepository {
  /// One-shot position fetch (not continuous background tracking — that's
  /// a larger addition than this "basic" pass covers, see README).
  Future<Position?> _currentPosition() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final requested = await Geolocator.requestPermission();
      if (requested == LocationPermission.denied || requested == LocationPermission.deniedForever) {
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) return null;
    // A last-known fix (instant, from the OS's cache) is good enough to go
    // online with — _startLocationPings() (called right after a successful
    // goOnline()) starts refreshing the real position within seconds
    // anyway, so there's no accuracy cost to preferring the cached value
    // here over waiting on a fresh GPS fix.
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) return cached;
    } catch (_) {
      // fall through to a fresh fix below
    }
    try {
      // Same fix as address_field.dart's "استخدم موقعي" — getCurrentPosition()
      // has no timeout of its own and can hang indefinitely on a weak/no GPS
      // fix, which froze the "متصل/غير متصل" switch for seconds (reported
      // live: opening the driver app left the toggle stuck mid-tap). Bounded
      // tighter than the address field's 15s — this only needs an
      // approximate starting point, not a precise pickup address.
      return await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<bool> goOnline(String phone, String name) async {
    final pos = await _currentPosition();
    if (pos == null) return false;
    await sb.from('driver_locations').upsert({
      'driver_phone': phone,
      'driver_name': name,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'is_online': true,
      'updated_at': DateTime.now().toIso8601String(),
    });
    return true;
  }

  /// Latest driver_applications.status for this phone, or null if no
  /// application exists at all. Used to gate the driver home shell before
  /// the driver ever sees the online toggle — accept_dispatch_offer()
  /// enforces the same check server-side regardless (see
  /// db/security-15-driver-approval-gate.sql), this is just so an
  /// unapproved driver gets a clear explanation instead of every accept
  /// silently failing.
  Future<String?> fetchApprovalStatus(String phone) async {
    final rows = await sb
        .from('driver_applications')
        .select('status')
        .eq('phone', phone)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['status'] as String?;
  }

  Future<void> goOffline(String phone) async {
    await sb.from('driver_locations').upsert({
      'driver_phone': phone,
      'is_online': false,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<PendingOffer?> getPendingOffer(String phone) async {
    final result = await sb.rpc('get_my_pending_offer', params: {'p_driver_phone': phone});
    if (result == null) return null;
    final row = result is List ? (result.isNotEmpty ? result.first : null) : result;
    if (row == null || row['offer_id'] == null) return null;
    return _offerFromRow(row as Map<String, dynamic>);
  }

  /// Every currently-pending offer for this driver (not just the latest) —
  /// lets the app show a real list instead of one offer at a time when
  /// several land close together (see security-22).
  Future<List<PendingOffer>> getPendingOffers(String phone) async {
    final result = await sb.rpc('get_my_pending_offers', params: {'p_driver_phone': phone});
    if (result is! List) return [];
    return result.map((row) => _offerFromRow(row as Map<String, dynamic>)).toList();
  }

  PendingOffer _offerFromRow(Map<String, dynamic> row) => PendingOffer(
        row['offer_id'].toString(),
        row['target_type'] as String,
        Map<String, dynamic>.from(row['data'] as Map),
        expiresAt: DateTime.tryParse(row['expires_at'] as String? ?? ''),
      );

  /// Periodic GPS ping while online/on a job — lets the customer's live
  /// tracking map (see ride_repository.watchDriverLocation) show real
  /// movement instead of a single point frozen at accept time.
  Future<void> pingLocation(String phone) async {
    final pos = await _currentPosition();
    if (pos == null) return;
    await sb.from('driver_locations').upsert({
      'driver_phone': phone,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'heading': pos.heading,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Returns 'ok', or a failure reason string ('vehicle_category_mismatch',
  /// 'expired_or_taken', 'already_taken') so the caller can show a specific
  /// message instead of a generic error.
  Future<String> acceptOffer(String offerId, String phone, String name) async {
    final result = await sb.rpc('accept_dispatch_offer', params: {
      'p_offer_id': offerId,
      'p_driver_phone': phone,
      'p_driver_name': name,
    });
    if (result is Map) {
      if (result['ok'] == true) return 'ok';
      return (result['reason'] as String?) ?? 'error';
    }
    return result == true ? 'ok' : 'error';
  }

  Future<void> rejectOffer(String offerId, String phone) async {
    await sb.rpc('reject_dispatch_offer', params: {'p_offer_id': offerId, 'p_driver_phone': phone});
  }

  /// Negotiable rides still open for bidding (no driver assigned yet) —
  /// `rides` is anon-readable directly (security07rlslockdown.sql), so this
  /// is a plain filtered query, not a dedicated RPC; only submitting/
  /// accepting a price offer needs the security-definer RPCs below (see
  /// db/security-35-ride-price-negotiation.sql).
  Stream<List<Map<String, dynamic>>> watchOpenNegotiableRides() {
    return sb
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('is_negotiable', true)
        .order('created_at', ascending: false);
  }

  /// Every offer on a given negotiable ride — the caller filters down to
  /// this driver's own row client-side (see negotiation_screen.dart).
  /// supabase_flutter's `.stream()` only supports a single server-side
  /// `.eq()` filter, so a second column (driver_phone) can't be chained on
  /// here the way a normal query would.
  Stream<List<Map<String, dynamic>>> watchOffersOnRide(String rideId) {
    return sb.from('ride_price_offers').stream(primaryKey: ['id']).eq('ride_id', rideId);
  }

  /// Submits (or updates) this driver's price offer on a negotiable ride.
  /// Returns null on success, or a short failure reason.
  Future<String?> submitPriceOffer(String rideId, String phone, String name, num price) async {
    try {
      await sb.rpc('submit_ride_price_offer', params: {
        'p_ride_id': rideId,
        'p_driver_phone': phone,
        'p_driver_name': name,
        'p_price': price,
      });
      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('ride_already_taken')) return 'الرحلة اتقفلت — سائق تاني اتقبل عليها.';
      if (msg.contains('not_negotiable')) return 'الرحلة دي مش تفاوضية.';
      return 'تعذّر إرسال العرض، حاول مرة أخرى.';
    }
  }

  /// Open airport rides not yet assigned to a driver — same open-table
  /// read as watchOpenNegotiableRides() above, just filtered to
  /// ride_type='airport' instead of is_negotiable. Shown as a persistent
  /// browsable list (no countdown) alongside the timed dispatch_offers
  /// path, per db/security-65-airport-ride-requests.sql.
  Stream<List<Map<String, dynamic>>> watchOpenAirportRides() {
    return sb
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('ride_type', 'airport')
        .order('created_at', ascending: false);
  }

  /// This driver's own rejected-ride ids, fetched once per screen open —
  /// used to filter watchOpenAirportRides() client-side so a rejected
  /// ride doesn't keep resurfacing in this driver's own list.
  Future<Set<String>> fetchRejectedAirportRideIds(String phone) async {
    final rows = await sb.from('airport_ride_rejections').select('ride_id').eq('driver_phone', phone);
    return List<Map<String, dynamic>>.from(rows).map((r) => r['ride_id'].toString()).toSet();
  }

  /// Returns 'ok', or a failure reason string ('vehicle_category_mismatch',
  /// 'quality_tier_mismatch', 'already_taken') — same shape as acceptOffer().
  Future<String> acceptAirportRide(String rideId, String phone, String name) async {
    final result = await sb.rpc('accept_airport_ride', params: {
      'p_ride_id': rideId,
      'p_driver_phone': phone,
      'p_driver_name': name,
    });
    if (result is Map && result['ok'] == true) return 'ok';
    return (result is Map ? result['reason'] as String? : null) ?? 'error';
  }

  Future<void> rejectAirportRide(String rideId, String phone) async {
    await sb.rpc('reject_airport_ride', params: {'p_ride_id': rideId, 'p_driver_phone': phone});
  }

  /// Marks an order picked up — routed through driver_mark_order_picked_up
  /// (security-48), which verifies this order is actually assigned to this
  /// driver server-side. A raw table UPDATE would let anyone mark any
  /// order picked up directly.
  Future<void> markOrderPickedUp(String orderId, String driverPhone) async {
    await sb.rpc('driver_mark_order_picked_up', params: {
      'p_order_id': orderId,
      'p_driver_phone': driverPhone,
    });
  }

  /// Confirms delivery via the same RPC (which also handles the
  /// merchant payout + platform commission + driver points server-side).
  /// Requires the 4-digit code shown on the customer's tracking page —
  /// proves the driver actually handed the order over, not just a
  /// self-reported tap with zero verification (mirrors driver-dashboard.astro).
  /// Returns false (not an exception) for a wrong code, so the driver can
  /// just retry instead of losing their place in the delivery flow.
  Future<bool> confirmOrderDelivery(String orderId, String driverPhone, String otp) async {
    final result = await sb.rpc('confirm_order_delivery', params: {
      'p_order_id': orderId,
      'p_otp': otp,
      'p_driver_phone': driverPhone,
    });
    return result == true;
  }

  /// Same status column driver-dashboard.astro's markArrived()/startTrip()
  /// PATCH — the customer-side tracking screen's icon timeline expects
  /// exactly these transitions (pending→accepted→arrived→in_progress→completed).
  /// Routed through mark_ride_arrived() (security-29) instead of a raw PATCH
  /// so lateness is measured server-side (against accepted_at) and the
  /// automatic 20 ج.م late-arrival deduction can't be spoofed by the client.
  /// Returns (lateMinutes, feeApplied) so the caller can tell the driver.
  Future<(int, bool)> markRideArrived(String rideId, String driverPhone) async {
    final result = await sb.rpc('mark_ride_arrived', params: {
      'p_ride_id': rideId,
      'p_driver_phone': driverPhone,
    });
    if (result is Map) {
      return (((result['late_minutes'] as num?) ?? 0).toInt(), result['fee_applied'] == true);
    }
    return (0, false);
  }

  /// "العميل لم يحضر" — db/security-70. Server re-validates the ride is
  /// still 'arrived' and that enough time has actually passed since
  /// arrived_at (PricingSettings.noShowGraceMinutes is only used
  /// client-side to gate showing the button at all). Returns the actual
  /// waited minutes + fee charged, or throws if the grace period hasn't
  /// elapsed yet server-side.
  Future<(int, double)> reportNoShow(String rideId, String driverPhone) async {
    final result = await sb.rpc('driver_report_no_show', params: {
      'p_ride_id': rideId,
      'p_driver_phone': driverPhone,
    });
    if (result is Map) {
      return (
        ((result['waited_minutes'] as num?) ?? 0).toInt(),
        ((result['fee'] as num?) ?? 0).toDouble(),
      );
    }
    return (0, 0.0);
  }

  /// Routed through driver_update_ride_status (security-48), which
  /// verifies this ride is actually assigned to this driver server-side.
  Future<void> markRideInProgress(String rideId, String driverPhone) async {
    await sb.rpc('driver_update_ride_status', params: {
      'p_ride_id': rideId,
      'p_driver_phone': driverPhone,
      'p_status': 'in_progress',
    });
  }

  /// Today/this-week completed trip+order counts (db/security-71) — a
  /// lightweight count query, unlike fetchTripStats' lifetime breakdown.
  Future<(int, int)> fetchProgress(String phone) async {
    final result = await sb.rpc('get_driver_progress', params: {'p_driver_phone': phone});
    if (result is Map) {
      return (((result['today'] as num?) ?? 0).toInt(), ((result['week'] as num?) ?? 0).toInt());
    }
    return (0, 0);
  }

  /// Server-side lifetime trip breakdown — same RPC driver-dashboard.astro's
  /// إحصائيات tab calls (see db/security-17-driver-trip-stats.sql, extended
  /// with a store_orders category by db/security-28-driver-profile.sql).
  Future<Map<String, dynamic>> fetchTripStats(String phone) async {
    final result = await sb.rpc('get_driver_trip_stats', params: {'p_driver_phone': phone});
    if (result is Map) return Map<String, dynamic>.from(result);
    return {};
  }

  /// The driver's own latest application row — vehicle photos/model/plate
  /// live here (driver_applications), not on accounts. Same table the web
  /// driver-dashboard reads for the vehicle-info card.
  Future<Map<String, dynamic>?> fetchVehicleInfo(String phone) async {
    final rows = await sb
        .from('driver_applications')
        .select(
          'vehicle_category,vehicle_model,vehicle_color,vehicle_year,vehicle_reg_number,'
          'vehicle_front_url,vehicle_back_url,vehicle_right_url,vehicle_left_url,plate_photo_url,'
          'has_ac,is_clean,is_modern',
        )
        .eq('phone', phone)
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  /// Same raw PATCH driver-dashboard.astro's "عربية مكيّفة" toggle does —
  /// lets a driver self-declare a quality tier (has_ac/is_clean/is_modern).
  /// Without this, the Flutter driver app had no way at all to set these
  /// (has_ac was only ever set once at signup, web-only), so
  /// accept_dispatch_offer()'s tier check would reject every driver who
  /// never happened to check that box during registration — the tier
  /// picker on the customer side looked broken because no driver could
  /// ever actually qualify.
  Future<void> updateQualityFlag(String phone, String column, bool value) async {
    await sb.from('driver_applications').update({column: value}).eq('phone', phone);
  }

  Future<RideSettlement?> completeRide(String rideId, String driverPhone) async {
    // driver_update_ride_status (security-48) verifies ride ownership
    // server-side before allowing the transition to 'completed'.
    await sb.rpc('driver_update_ride_status', params: {
      'p_ride_id': rideId,
      'p_driver_phone': driverPhone,
      'p_status': 'completed',
    });
    final ride = await sb.from('rides').select('fare').eq('id', rideId).single();
    // Server reads the real fare + commission rate itself and credits the
    // driver's wallet — see db/security-07-commission-settlement.sql.
    // (This app never credited ride earnings at all before; orders already
    // went through the equally server-side confirm_order_delivery RPC.)
    final result = await sb.rpc('settle_ride_commission', params: {
      'p_ride_id': rideId,
      'p_driver_phone': driverPhone,
    });
    final row = result is List ? (result.isNotEmpty ? result.first : null) : result;
    if (row == null) return null;
    return RideSettlement(
      fare: ((ride['fare'] as num?) ?? 0).toDouble(),
      commission: ((row['commission'] as num?) ?? 0).toDouble(),
      driverEarn: ((row['driver_earn'] as num?) ?? 0).toDouble(),
      rate: ((row['rate'] as num?) ?? 0).toDouble(),
    );
  }

  /// "سجل الرحلات" (db/security-92/93) — dispatch offers that expired
  /// unanswered: most commonly a driver whose "متصل" switch was still on,
  /// but whose device had lost internet right when an offer came in, so it
  /// timed out before they ever saw it. Last 30 days; each row's
  /// stillAvailable says whether it can actually still be accepted.
  Future<List<MissedRequest>> fetchMissedRequests(String phone) async {
    final rows = await sb.rpc('get_driver_missed_requests', params: {'p_driver_phone': phone});
    return (rows as List).cast<Map<String, dynamic>>().map(MissedRequest.fromRow).toList();
  }

  /// Manually recovers a missed request (db/security-93) — no 30s
  /// countdown, works even while offline (this is a deliberate manual pull,
  /// not a live dispatch push). Returns null on success, or an error reason
  /// string ('already_taken' | 'vehicle_category_mismatch' |
  /// 'quality_tier_mismatch' | ...) the caller turns into a message.
  Future<String?> acceptMissedRequest(String offerId, String driverPhone, String driverName) async {
    final result = await sb.rpc('accept_missed_request', params: {
      'p_offer_id': offerId,
      'p_driver_phone': driverPhone,
      'p_driver_name': driverName,
    }) as Map<String, dynamic>;
    if (result['ok'] == true) return null;
    return result['reason'] as String? ?? 'error';
  }

  Future<bool> dismissMissedRequest(String offerId, String driverPhone) async {
    final result = await sb.rpc('dismiss_missed_request', params: {'p_offer_id': offerId, 'p_driver_phone': driverPhone});
    return result == true;
  }

  /// Outstanding cash-collection reminders an admin sent this driver
  /// (db/security-92) — stays active (keeps showing) until an admin marks
  /// it settled from the panel, not just dismissed once in the app.
  Future<List<CashReminder>> fetchActiveCashReminders(String phone) async {
    final rows = await sb.rpc('get_driver_active_cash_reminders', params: {'p_driver_phone': phone});
    return (rows as List).cast<Map<String, dynamic>>().map(CashReminder.fromRow).toList();
  }
}

class MissedRequest {
  final String id;
  final String targetType; // 'ride' | 'order'
  final DateTime offeredAt;
  final String? fromArea;
  final String? toArea;
  final double? fare;
  final String? storeName;
  final double? orderTotal;
  // Whether the underlying ride/order is genuinely still unassigned right
  // now (db/security-93) — the log itself is a permanent history, but only
  // an offer that's still up for grabs can actually be accepted.
  final bool stillAvailable;
  MissedRequest({
    required this.id,
    required this.targetType,
    required this.offeredAt,
    this.fromArea,
    this.toArea,
    this.fare,
    this.storeName,
    this.orderTotal,
    this.stillAvailable = false,
  });

  factory MissedRequest.fromRow(Map<String, dynamic> row) => MissedRequest(
        id: row['id'] as String,
        targetType: row['target_type'] as String? ?? 'ride',
        offeredAt: DateTime.parse(row['offered_at'] as String),
        fromArea: row['from_area'] as String?,
        toArea: row['to_area'] as String?,
        fare: (row['fare'] as num?)?.toDouble(),
        storeName: row['store_name'] as String?,
        orderTotal: (row['order_total'] as num?)?.toDouble(),
        stillAvailable: row['still_available'] as bool? ?? false,
      );
}

class CashReminder {
  final String id;
  final double amount;
  final String? note;
  final DateTime createdAt;
  final DateTime dueAt;
  CashReminder({required this.id, required this.amount, this.note, required this.createdAt, required this.dueAt});

  factory CashReminder.fromRow(Map<String, dynamic> row) => CashReminder(
        id: row['id'] as String,
        amount: ((row['amount'] as num?) ?? 0).toDouble(),
        note: row['note'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        dueAt: DateTime.parse(row['due_at'] as String),
      );
}
