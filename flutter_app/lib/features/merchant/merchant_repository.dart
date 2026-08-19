import '../../core/supabase_client.dart';

/// Same stores/orders tables merchant-dashboard.astro reads/writes.
class MerchantRepository {
  Future<Map<String, dynamic>?> getStoreForOwner(String ownerPhone) async {
    final rows = await sb.from('stores').select().eq('owner_phone', ownerPhone).limit(1);
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<List<Map<String, dynamic>>> getOrders(String storeId) async {
    final rows = await sb
        .from('orders')
        .select()
        .eq('store_id', storeId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Stream<List<Map<String, dynamic>>> watchOrders(String storeId) {
    return sb.from('orders').stream(primaryKey: ['id']).eq('store_id', storeId).order('created_at', ascending: false);
  }

  Future<void> acceptOrder(String orderId, {int? prepMinutes}) async {
    await sb.from('orders').update({
      'status': 'preparing',
      'accepted_at': DateTime.now().toIso8601String(),
      if (prepMinutes != null) 'prep_minutes': prepMinutes,
    }).eq('id', orderId);
  }

  Future<void> rejectOrder(String orderId) async {
    await sb.from('orders').update({
      'status': 'rejected',
      'rejected_at': DateTime.now().toIso8601String(),
    }).eq('id', orderId);
  }
}
