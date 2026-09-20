import '../../core/phone_utils.dart';
import '../../core/supabase_client.dart';

/// A single history item — either an `orders` row (courier/delivery/store)
/// or a `rides` row, normalized to one shape for a combined feed. Mirrors
/// profile.astro's "الطلبات"/"المشاوير" tabs, just merged into one list
/// (sorted newest-first) instead of two separate tabs.
class HistoryItem {
  final String kind; // 'order' | 'ride'
  final String id;
  final String status;
  final String title;
  final String subtitle;
  final num total;
  final DateTime? createdAt;
  /// rides only: 'local' | 'external' | 'airport' (null for orders, or a
  /// ride row saved before ride_type existed — treated as 'local').
  final String? rideType;
  // Rides only — raw pickup/dropoff addresses+coordinates, needed to
  // prefill "احجز تاني" (see orders_screen.dart's rebook button).
  final String? fromArea;
  final double? fromLat;
  final double? fromLng;
  final String? toArea;
  final double? toLat;
  final double? toLng;
  // Orders only — needed for "اطلب تاني" (reopen the store with the same
  // items re-added to the cart).
  final String? storeId;
  final List<Map<String, dynamic>>? items;

  HistoryItem({
    required this.kind,
    required this.id,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.createdAt,
    this.rideType,
    this.fromArea,
    this.fromLat,
    this.fromLng,
    this.toArea,
    this.toLat,
    this.toLng,
    this.storeId,
    this.items,
  });
}

/// Real totals for the account screen's stats row — deliberately NOT
/// derived from fetchHistory()'s result, since that query caps each of
/// orders/rides at 50 rows for the scrollable list's sake. A customer past
/// 50 real orders or rides would see fetchHistory-derived counts frozen at
/// 50 forever (reported as "the update doesn't react" — the list itself
/// kept working since new rows sort first, but a `.length` off a capped
/// list can never exceed the cap). This queries counts/totals directly
/// with no limit instead.
class HistoryStats {
  final int totalOrders;
  final int totalRides;
  final num totalSpent;
  HistoryStats({required this.totalOrders, required this.totalRides, required this.totalSpent});
}

const Map<String, String> statusAr = {
  'pending': 'قيد الانتظار',
  'preparing': 'قيد التجهيز',
  'on_the_way': 'في الطريق',
  'delivered': 'تم التسليم',
  'rejected': 'مرفوض',
  'cancelled': 'ملغاة',
  'accepted': 'تم القبول',
  'arrived': 'وصل السائق',
  'in_progress': 'جارية',
  'completed': 'مكتملة',
};

class OrdersRepository {
  /// Same purpose as RideRepository.findActiveRide() — lets app startup
  /// resume straight into OrderInvoiceScreen for a delivery order this
  /// customer is still waiting on, instead of losing it to the home screen
  /// after Android kills the app in the background. Returns the full row
  /// (not just the id) so the caller can compare created_at against a
  /// competing active ride and resume into whichever is actually more
  /// recent — a customer with any stray never-finished ride sitting in
  /// their history (a cancelled test, an old bug) would otherwise always
  /// get sent back into that instead of a genuinely newer order.
  Future<Map<String, dynamic>?> findActiveOrder(String phone) async {
    final local = normalizeEgyptianPhone(phone);
    final intl = toIntlEgyptianPhone(phone);
    final filter = 'customer_phone.eq.$local,customer_phone.eq.$intl';
    final rows = await sb
        .from('orders')
        .select()
        .or(filter)
        .not('status', 'in', '(delivered,rejected,cancelled)')
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Driver-side counterpart, used by DriverHomeScreen to repopulate
  /// ActiveJobStore on relaunch — same reasoning as
  /// RideRepository.findActiveRide()'s doc comment. Returns the full row
  /// (not just the id): the caller needs `status` to know whether to
  /// restore as "picked up" (status='on_the_way', per
  /// driver_mark_order_picked_up in security-48) or still heading to the
  /// store.
  Future<Map<String, dynamic>?> findActiveOrderForDriver(String phone) async {
    final local = normalizeEgyptianPhone(phone);
    final intl = toIntlEgyptianPhone(phone);
    final filter = 'driver_phone.eq.$local,driver_phone.eq.$intl';
    final rows = await sb
        .from('orders')
        .select()
        .or(filter)
        .not('status', 'in', '(delivered,rejected,cancelled)')
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<HistoryStats> fetchStats(String phone) async {
    final local = normalizeEgyptianPhone(phone);
    final intl = toIntlEgyptianPhone(phone);
    final filter = 'customer_phone.eq.$local,customer_phone.eq.$intl';

    final results = await Future.wait([
      sb.from('orders').select('status,total').or(filter),
      sb.from('rides').select('status,fare').or(filter),
    ]);

    final orders = results[0] as List;
    final rides = results[1] as List;

    num spent = 0;
    for (final o in orders) {
      if (o['status'] == 'delivered') spent += (o['total'] as num?) ?? 0;
    }
    for (final r in rides) {
      if (r['status'] == 'completed') spent += (r['fare'] as num?) ?? 0;
    }

    return HistoryStats(totalOrders: orders.length, totalRides: rides.length, totalSpent: spent);
  }

  Future<List<HistoryItem>> fetchHistory(String phone) async {
    final local = normalizeEgyptianPhone(phone);
    final intl = toIntlEgyptianPhone(phone);
    final filter = 'customer_phone.eq.$local,customer_phone.eq.$intl';

    final results = await Future.wait([
      sb
          .from('orders')
          // 'source' and 'icon' were guessed wrong (confirmed via direct
          // REST probing — neither exists on this table) and removed.
          // store_id/items added for "اطلب تاني" (see orders_screen.dart).
          .select('id,status,store_name,total,created_at,store_id,items')
          .or(filter)
          .order('created_at', ascending: false)
          .limit(50),
      sb
          .from('rides')
          // from_lat/from_lng/to_lat/to_lng added for "احجز تاني".
          .select('id,status,from_area,to_area,fare,driver_name,ride_type,created_at,from_lat,from_lng,to_lat,to_lng')
          .or(filter)
          .order('created_at', ascending: false)
          .limit(50),
    ]);

    final orders = (results[0] as List).map((o) {
      final title = '📦 طلب من ${o['store_name'] ?? 'المتجر'}';
      final rawItems = o['items'];
      return HistoryItem(
        kind: 'order',
        id: '${o['id']}',
        status: o['status'] as String? ?? 'pending',
        title: title,
        subtitle: statusAr[o['status']] ?? '${o['status']}',
        total: (o['total'] as num?) ?? 0,
        createdAt: DateTime.tryParse(o['created_at'] as String? ?? ''),
        storeId: o['store_id'] as String?,
        items: rawItems is List ? rawItems.whereType<Map<String, dynamic>>().toList() : null,
      );
    });

    final rides = (results[1] as List).map((r) {
      return HistoryItem(
        kind: 'ride',
        id: '${r['id']}',
        status: r['status'] as String? ?? 'pending',
        title: '🚖 ${r['from_area'] ?? ''} ← ${r['to_area'] ?? ''}',
        subtitle: (r['driver_name'] as String?)?.isNotEmpty == true
            ? 'السائق: ${r['driver_name']}'
            : statusAr[r['status']] ?? '${r['status']}',
        total: (r['fare'] as num?) ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        rideType: (r['ride_type'] as String?) ?? 'local',
        fromArea: r['from_area'] as String?,
        fromLat: (r['from_lat'] as num?)?.toDouble(),
        fromLng: (r['from_lng'] as num?)?.toDouble(),
        toArea: r['to_area'] as String?,
        toLat: (r['to_lat'] as num?)?.toDouble(),
        toLng: (r['to_lng'] as num?)?.toDouble(),
      );
    });

    final all = [...orders, ...rides];
    all.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return all;
  }

  /// Same shape as fetchHistory() above, but for a driver's own completed/
  /// active jobs (orders.driver_phone / rides.driver_phone — confirmed real
  /// columns, driver-dashboard.astro filters on both the same way).
  Future<List<HistoryItem>> fetchDriverHistory(String driverPhone) async {
    final results = await Future.wait([
      sb
          .from('orders')
          .select('id,status,store_name,total,created_at')
          .eq('driver_phone', driverPhone)
          .order('created_at', ascending: false)
          .limit(50),
      sb
          .from('rides')
          .select('id,status,from_area,to_area,fare,ride_type,created_at')
          .eq('driver_phone', driverPhone)
          .order('created_at', ascending: false)
          .limit(50),
    ]);

    final orders = (results[0] as List).map((o) {
      return HistoryItem(
        kind: 'order',
        id: '${o['id']}',
        status: o['status'] as String? ?? 'pending',
        title: '📦 طلب من ${o['store_name'] ?? 'المتجر'}',
        subtitle: statusAr[o['status']] ?? '${o['status']}',
        total: (o['total'] as num?) ?? 0,
        createdAt: DateTime.tryParse(o['created_at'] as String? ?? ''),
      );
    });

    final rides = (results[1] as List).map((r) {
      return HistoryItem(
        kind: 'ride',
        id: '${r['id']}',
        status: r['status'] as String? ?? 'pending',
        title: '🚖 ${r['from_area'] ?? ''} ← ${r['to_area'] ?? ''}',
        subtitle: statusAr[r['status']] ?? '${r['status']}',
        total: (r['fare'] as num?) ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        rideType: (r['ride_type'] as String?) ?? 'local',
      );
    });

    final all = [...orders, ...rides];
    all.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return all;
  }
}
