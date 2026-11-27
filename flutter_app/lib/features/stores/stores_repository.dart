import '../../core/data_cache.dart';
import '../../core/supabase_client.dart';
import 'stores_models.dart';

class StoresRepository {
  /// Cached for 10 minutes (core/data_cache.dart) — the store directory
  /// barely changes minute to minute, but was previously re-fetched in
  /// full on every single open of the stores list. Cache miss/expiry
  /// falls straight through to the same query as before; nothing changes
  /// about what data is shown, only how often it's fetched from the server.
  Future<List<StoreRow>> fetchStores() async {
    final cached = await DataCache.readList<Map<String, dynamic>>(
      'stores_active',
      (m) => m,
      maxAge: const Duration(minutes: 10),
    );
    final rows = cached ?? await _fetchStoresFresh();
    return rows.map((r) => StoreRow.fromJson(r)).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchStoresFresh() async {
    final rows = await sb.from('stores').select().eq('is_active', true).order('name');
    final list = (rows as List).cast<Map<String, dynamic>>();
    await DataCache.writeList('stores_active', list);
    return list;
  }

  /// Single-store lookup — used by invoices_screen.dart's "اطلب تاني" to
  /// reopen a past delivery order's store without fetching the whole list.
  /// Returns null if the store's since been deactivated/deleted, so the
  /// caller can tell the customer instead of pushing a broken screen.
  Future<StoreRow?> fetchStore(String storeId) async {
    final rows = await sb.from('stores').select().eq('id', storeId).eq('is_active', true).limit(1);
    if ((rows as List).isEmpty) return null;
    return StoreRow.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<List<SectionRow>> fetchSections(String storeId) async {
    final rows = await sb.from('menu_sections').select().eq('store_id', storeId).order('sort_order');
    return (rows as List).map((r) => SectionRow.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<ProductRow>> fetchProducts(String storeId) async {
    final rows = await sb.from('products').select().eq('store_id', storeId).order('sort_order');
    return (rows as List).map((r) => ProductRow.fromJson(r as Map<String, dynamic>)).toList();
  }
}
