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

  HistoryItem({
    required this.kind,
    required this.id,
    required this.status,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.createdAt,
  });
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
  Future<List<HistoryItem>> fetchHistory(String phone) async {
    final local = normalizeEgyptianPhone(phone);
    final intl = toIntlEgyptianPhone(phone);
    final filter = 'customer_phone.eq.$local,customer_phone.eq.$intl';

    final results = await Future.wait([
      sb
          .from('orders')
          .select('id,status,store_name,type,icon,total,created_at')
          .or(filter)
          .order('created_at', ascending: false)
          .limit(50),
      sb
          .from('rides')
          .select('id,status,from_area,to_area,fare,driver_name,created_at')
          .or(filter)
          .order('created_at', ascending: false)
          .limit(50),
    ]);

    final orders = (results[0] as List).map((o) {
      final title = '${o['icon'] ?? '📦'} طلب من ${o['store_name'] ?? (o['type'] == 'general_delivery' ? 'خدمة دليفري' : 'المتجر')}';
      return HistoryItem(
        kind: 'order',
        id: '${o['id']}',
        status: o['status'] as String? ?? 'pending',
        title: title,
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
        subtitle: (r['driver_name'] as String?)?.isNotEmpty == true
            ? 'السائق: ${r['driver_name']}'
            : statusAr[r['status']] ?? '${r['status']}',
        total: (r['fare'] as num?) ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
      );
    });

    final all = [...orders, ...rides];
    all.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return all;
  }
}
