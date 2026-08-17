/// Mirrors src/utils/storesApi.ts's StoreRow/SectionRow/ProductRow — same
/// `stores`/`menu_sections`/`products` tables the web store page and
/// merchant dashboard read/write.
class StoreRow {
  final String id;
  final String name;
  final String category;
  final String emoji;
  final String area;
  final num rating;
  final int reviews;
  final String deliveryTime;
  final num deliveryFee;
  final num minOrder;
  final String tagline;
  final bool isOpen;
  final double? lat;
  final double? lng;

  StoreRow({
    required this.id,
    required this.name,
    required this.category,
    required this.emoji,
    required this.area,
    required this.rating,
    required this.reviews,
    required this.deliveryTime,
    required this.deliveryFee,
    required this.minOrder,
    required this.tagline,
    required this.isOpen,
    this.lat,
    this.lng,
  });

  factory StoreRow.fromJson(Map<String, dynamic> j) => StoreRow(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        category: j['category'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🏪',
        area: j['area'] as String? ?? '',
        rating: (j['rating'] as num?) ?? 0,
        reviews: (j['reviews'] as num?)?.toInt() ?? 0,
        deliveryTime: j['delivery_time'] as String? ?? '',
        deliveryFee: (j['delivery_fee'] as num?) ?? 0,
        minOrder: (j['min_order'] as num?) ?? 0,
        tagline: j['tagline'] as String? ?? '',
        isOpen: j['is_open'] as bool? ?? true,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}

class SectionRow {
  final String id;
  final String storeId;
  final String name;
  final int sortOrder;

  SectionRow({required this.id, required this.storeId, required this.name, required this.sortOrder});

  factory SectionRow.fromJson(Map<String, dynamic> j) => SectionRow(
        id: j['id'] as String,
        storeId: j['store_id'] as String,
        name: j['name'] as String? ?? '',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class ProductRow {
  final String id;
  final String storeId;
  final String sectionId;
  final String name;
  final String? description;
  final num price;
  final num? compareAtPrice;
  final String emoji;
  final String? imageUrl;
  final bool isAvailable;
  final int? stockQuantity;

  ProductRow({
    required this.id,
    required this.storeId,
    required this.sectionId,
    required this.name,
    this.description,
    required this.price,
    this.compareAtPrice,
    required this.emoji,
    this.imageUrl,
    required this.isAvailable,
    this.stockQuantity,
  });

  factory ProductRow.fromJson(Map<String, dynamic> j) => ProductRow(
        id: j['id'] as String,
        storeId: j['store_id'] as String,
        sectionId: j['section_id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        price: (j['price'] as num?) ?? 0,
        compareAtPrice: j['compare_at_price'] as num?,
        emoji: j['emoji'] as String? ?? '🛒',
        imageUrl: j['image_url'] as String?,
        isAvailable: j['is_available'] as bool? ?? true,
        stockQuantity: (j['stock_quantity'] as num?)?.toInt(),
      );
}
