import 'package:flutter/foundation.dart';
import 'stores_models.dart';

class CartLine {
  final ProductRow product;
  int qty;
  CartLine({required this.product, required this.qty});
}

/// Single-store cart, mirroring src/utils/cart.ts's rule (localStorage
/// `Cart` there is also scoped to one storeId at a time — switching stores
/// clears whatever was in progress). Kept as a ChangeNotifier singleton so
/// the store-detail screen and the floating cart bar/badge stay in sync
/// without a state-management package.
class CartStore extends ChangeNotifier {
  CartStore._();
  static final CartStore instance = CartStore._();

  String? storeId;
  String? storeName;
  num deliveryFee = 0;
  num minOrder = 0;
  // The separate dispatch-matching server (server/index.js) needs the
  // order's origin coordinates to find nearby drivers — without them it
  // silently falls back to a legacy broadcast path this app doesn't
  // implement, so an order would never reach any driver. Defaults to New
  // Damietta's centre, same fallback store/[id].astro's checkout uses when
  // a store hasn't set its own lat/lng.
  static const double _fallbackLat = 31.4441;
  static const double _fallbackLng = 31.6533;
  double storeLat = _fallbackLat;
  double storeLng = _fallbackLng;
  final List<CartLine> _lines = [];

  List<CartLine> get lines => List.unmodifiable(_lines);
  int get count => _lines.fold(0, (s, l) => s + l.qty);
  num get subtotal => _lines.fold<num>(0, (s, l) => s + l.qty * l.product.price);
  num get total => subtotal + (_lines.isEmpty ? 0 : deliveryFee);

  int qtyOf(String productId) {
    for (final l in _lines) {
      if (l.product.id == productId) return l.qty;
    }
    return 0;
  }

  void setQty(StoreRow store, ProductRow product, int qty) {
    if (storeId != store.id) {
      _lines.clear();
      storeId = store.id;
      storeName = store.name;
      deliveryFee = store.deliveryFee;
      minOrder = store.minOrder;
      storeLat = store.lat ?? _fallbackLat;
      storeLng = store.lng ?? _fallbackLng;
    }
    final idx = _lines.indexWhere((l) => l.product.id == product.id);
    if (qty <= 0) {
      if (idx >= 0) _lines.removeAt(idx);
    } else if (idx >= 0) {
      _lines[idx].qty = qty;
    } else {
      _lines.add(CartLine(product: product, qty: qty));
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    storeId = null;
    storeName = null;
    deliveryFee = 0;
    minOrder = 0;
    storeLat = _fallbackLat;
    storeLng = _fallbackLng;
    notifyListeners();
  }
}
