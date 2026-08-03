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
  PendingOffer(this.offerId, this.targetType, this.data);
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
    try {
      return await Geolocator.getCurrentPosition();
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
    return PendingOffer(
      row['offer_id'].toString(),
      row['target_type'] as String,
      Map<String, dynamic>.from(row['data'] as Map),
    );
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

  /// Marks an order picked up (matches driver-dashboard.astro's PATCH).
  Future<void> markOrderPickedUp(String orderId) async {
    await sb.from('orders').update({
      'status': 'on_the_way',
      'picked_up_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
  }

  /// Confirms delivery via the same RPC (which also handles the
  /// merchant payout + platform commission + driver points server-side).
  Future<void> confirmOrderDelivery(String orderId, String driverPhone) async {
    await sb.rpc('confirm_order_delivery', params: {'p_order_id': orderId, 'p_driver_phone': driverPhone});
  }

  /// Same status column driver-dashboard.astro's markArrived()/startTrip()
  /// PATCH — the customer-side tracking screen's icon timeline expects
  /// exactly these transitions (pending→accepted→arrived→in_progress→completed).
  Future<void> markRideArrived(String rideId) async {
    await sb.from('rides').update({'status': 'arrived'}).eq('id', rideId);
  }

  Future<void> markRideInProgress(String rideId) async {
    await sb.from('rides').update({'status': 'in_progress'}).eq('id', rideId);
  }

  Future<RideSettlement?> completeRide(String rideId, String driverPhone) async {
    final ride = await sb.from('rides').update({
      'status': 'completed',
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', rideId).select('fare').single();
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
}
