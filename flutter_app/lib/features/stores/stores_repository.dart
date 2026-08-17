import '../../core/supabase_client.dart';
import 'stores_models.dart';

class StoresRepository {
  Future<List<StoreRow>> fetchStores() async {
    final rows = await sb.from('stores').select().eq('is_active', true).order('name');
    return (rows as List).map((r) => StoreRow.fromJson(r as Map<String, dynamic>)).toList();
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
