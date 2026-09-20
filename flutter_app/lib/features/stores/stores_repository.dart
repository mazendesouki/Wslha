import '../../core/supabase_client.dart';
import 'stores_models.dart';

class StoresRepository {
  Future<List<StoreRow>> fetchStores() async {
    final rows = await sb.from('stores').select().eq('is_active', true).order('name');
    return (rows as List).map((r) => StoreRow.fromJson(r as Map<String, dynamic>)).toList();
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
