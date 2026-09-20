/// Mirrors src/utils/marketplaceApi.ts's MarketItem/CATEGORIES/CONDITIONS —
/// same `marketplace_items` table the web سوق المستعمل reads/writes.
class MarketItem {
  final String id;
  final String sellerPhone;
  final String sellerType; // 'customer' | 'merchant'
  final String title;
  final String? description;
  final String category;
  final String condition; // 'new' | 'like_new' | 'used' | 'fair'
  final num price;
  final int quantity;
  final String? city;
  final String? area;
  final List<String> images;
  final String contactPhone;
  final bool whatsapp;
  final String status; // 'active' | 'sold' | 'removed' | 'under_review'
  final int views;
  final DateTime? createdAt;
  final double? lat;
  final double? lng;

  const MarketItem({
    required this.id,
    required this.sellerPhone,
    required this.sellerType,
    required this.title,
    this.description,
    required this.category,
    required this.condition,
    required this.price,
    required this.quantity,
    this.city,
    this.area,
    required this.images,
    required this.contactPhone,
    required this.whatsapp,
    required this.status,
    required this.views,
    required this.createdAt,
    this.lat,
    this.lng,
  });

  factory MarketItem.fromRow(Map<String, dynamic> r) => MarketItem(
        id: r['id'] as String,
        sellerPhone: r['seller_phone'] as String? ?? '',
        sellerType: r['seller_type'] as String? ?? 'customer',
        title: r['title'] as String? ?? '',
        description: r['description'] as String?,
        category: r['category'] as String? ?? 'other',
        condition: r['condition'] as String? ?? 'used',
        price: (r['price'] as num?) ?? 0,
        quantity: (r['quantity'] as num?)?.toInt() ?? 1,
        city: r['city'] as String?,
        area: r['area'] as String?,
        images: (r['images'] as List?)?.whereType<String>().toList() ?? const [],
        contactPhone: r['contact_phone'] as String? ?? r['seller_phone'] as String? ?? '',
        whatsapp: r['whatsapp'] as bool? ?? false,
        status: r['status'] as String? ?? 'active',
        views: (r['views'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        lat: (r['lat'] as num?)?.toDouble(),
        lng: (r['lng'] as num?)?.toDouble(),
      );
}

const List<({String id, String label, String emoji})> marketplaceCategories = [
  (id: 'electronics', label: 'إلكترونيات وموبايلات', emoji: '📱'),
  (id: 'furniture', label: 'أثاث ومنزل', emoji: '🛋️'),
  (id: 'cars', label: 'سيارات ومركبات', emoji: '🚗'),
  (id: 'fashion', label: 'ملابس وإكسسوارات', emoji: '👕'),
  (id: 'appliances', label: 'أجهزة كهربائية', emoji: '🔌'),
  (id: 'kids', label: 'مستلزمات أطفال', emoji: '🧸'),
  (id: 'books', label: 'كتب وقرطاسية', emoji: '📚'),
  (id: 'sports', label: 'رياضة وهوايات', emoji: '⚽'),
  (id: 'other', label: 'أخرى', emoji: '📦'),
];

const Map<String, String> marketplaceConditions = {
  'new': 'جديد',
  'like_new': 'كالجديد',
  'used': 'مستعمل بحالة جيدة',
  'fair': 'مستعمل - يحتاج صيانة',
};
