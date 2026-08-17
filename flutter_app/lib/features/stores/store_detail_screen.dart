import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'cart_store.dart';
import 'checkout_sheet.dart';
import 'stores_models.dart';
import 'stores_repository.dart';

class StoreDetailScreen extends StatefulWidget {
  final StoreRow store;
  const StoreDetailScreen({super.key, required this.store});

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  final _repo = StoresRepository();
  List<SectionRow>? _sections;
  List<ProductRow>? _products;
  bool _loading = true;
  String? _error;
  final _cart = CartStore.instance;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCartChanged);
    _load();
  }

  @override
  void dispose() {
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.fetchSections(widget.store.id),
        _repo.fetchProducts(widget.store.id),
      ]);
      if (!mounted) return;
      setState(() {
        _sections = results[0] as List<SectionRow>;
        _products = (results[1] as List<ProductRow>).where((p) => p.isAvailable).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _setQty(ProductRow p, int qty) {
    if (_cart.storeId != null && _cart.storeId != widget.store.id && _cart.count > 0) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('سلة من متجر تاني'),
          content: Text('عندك عناصر في سلتك من "${_cart.storeName}" — لو أضفت من هنا هتتفضّى السلة القديمة. تكمل؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _cart.clear();
                _cart.setQty(widget.store, p, qty);
              },
              child: const Text('استبدال السلة'),
            ),
          ],
        ),
      );
      return;
    }
    _cart.setQty(widget.store, p, qty);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: Text(widget.store.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.error), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  ),
                )
              : _buildMenu(),
      bottomNavigationBar: (_cart.storeId == widget.store.id && _cart.count > 0) ? _buildCartBar() : null,
    );
  }

  Widget _buildMenu() {
    final sections = _sections ?? [];
    final products = _products ?? [];
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text('🍽️', style: TextStyle(fontSize: 48)),
            SizedBox(height: 12),
            Text('لسه مفيش منتجات في المتجر ده', style: TextStyle(color: AppColors.textFaint)),
          ],
        ),
      );
    }

    final bySection = <String, List<ProductRow>>{};
    for (final p in products) {
      bySection.putIfAbsent(p.sectionId, () => []).add(p);
    }
    final orderedSections = sections.where((s) => bySection.containsKey(s.id)).toList();
    // Products whose section_id doesn't match any known section still show,
    // grouped under a generic header, instead of silently disappearing.
    final orphanKeys = bySection.keys.where((k) => !sections.any((s) => s.id == k));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                const Icon(Icons.star, color: AppColors.accent, size: 16),
                const SizedBox(width: 4),
                Text('${widget.store.rating} (${widget.store.reviews})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(width: 14),
                const Icon(Icons.timer_outlined, color: AppColors.textFaint, size: 16),
                const SizedBox(width: 4),
                Text(widget.store.deliveryTime, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                const Spacer(),
                Text('رسوم التوصيل ${widget.store.deliveryFee.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
              ],
            ),
          ),
          for (final s in orderedSections) ..._sectionBlock(s.name, bySection[s.id]!),
          for (final k in orphanKeys) ..._sectionBlock('أصناف أخرى', bySection[k]!),
        ],
      ),
    );
  }

  List<Widget> _sectionBlock(String title, List<ProductRow> items) => [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        ),
        ...items.map((p) => _ProductTile(product: p, qty: _cart.qtyOf(p.id), onQtyChanged: (q) => _setQty(p, q))),
        const SizedBox(height: 12),
      ];

  Widget _buildCartBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CheckoutSheet()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🛒 ${_cart.count} عناصر', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                  Text('السلة — ${_cart.total.toStringAsFixed(0)} ج.م', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final ProductRow product;
  final int qty;
  final ValueChanged<int> onQtyChanged;
  const _ProductTile({required this.product, required this.qty, required this.onQtyChanged});

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.compareAtPrice != null && product.compareAtPrice! > product.price;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(product.imageUrl!, width: 56, height: 56, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _emojiBox()),
            )
          else
            _emojiBox(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                if (product.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(product.description!, style: const TextStyle(fontSize: 11, color: AppColors.textFaint), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('${product.price} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
                    if (hasDiscount) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${product.compareAtPrice} ج.م',
                        style: const TextStyle(fontSize: 11, color: AppColors.textFaint, decoration: TextDecoration.lineThrough),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          qty == 0
              ? OutlinedButton(onPressed: () => onQtyChanged(1), child: const Text('+ أضف'))
              : Row(
                  children: [
                    IconButton(onPressed: () => onQtyChanged(qty - 1), icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary)),
                    Text('$qty', style: const TextStyle(fontWeight: FontWeight.w900)),
                    IconButton(onPressed: () => onQtyChanged(qty + 1), icon: const Icon(Icons.add_circle_outline, color: AppColors.primary)),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _emojiBox() => Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(10)),
        child: Text(product.emoji, style: const TextStyle(fontSize: 24)),
      );
}
