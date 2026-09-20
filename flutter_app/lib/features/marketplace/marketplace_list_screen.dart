import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'marketplace_item_screen.dart';
import 'marketplace_models.dart';
import 'marketplace_repository.dart';

/// Entry point for "🛍️ سوق المستعمل" on the home tab — browse active
/// listings and open one to view details / request delivery. Posting a new
/// listing stays web-only for now (marketplace/post.astro); this is a
/// browse-and-buy surface, matching src/pages/marketplace/index.astro.
class MarketplaceListScreen extends StatefulWidget {
  const MarketplaceListScreen({super.key});

  @override
  State<MarketplaceListScreen> createState() => _MarketplaceListScreenState();
}

class _MarketplaceListScreenState extends State<MarketplaceListScreen> {
  final _repo = MarketplaceRepository();
  List<MarketItem>? _items;
  bool _loading = true;
  String? _error;
  String _query = '';
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.fetchItems();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    final filtered = _items?.where((i) {
      if (_category != 'all' && i.category != _category) return false;
      if (_query.trim().isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return i.title.toLowerCase().contains(q) || (i.description ?? '').toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('marketplace_list_title'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: context.tr('marketplace_list_search_hint'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _categoryChip('all', context.tr('marketplace_category_all'), '🛍️'),
                const SizedBox(width: 8),
                for (final c in marketplaceCategories) ...[
                  _categoryChip(c.id, c.label, c.emoji),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
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
                              OutlinedButton(onPressed: _load, child: Text(context.tr('marketplace_list_retry'))),
                            ],
                          ),
                        ),
                      )
                    : (filtered == null || filtered.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🛍️', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  _query.isEmpty ? context.tr('marketplace_list_empty') : context.tr('marketplace_list_no_results'),
                                  style: const TextStyle(color: AppColors.textFaint),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.72,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) => _ItemCard(item: filtered[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(String id, String label, String emoji) {
    final selected = _category == id;
    return ChoiceChip(
      label: Text('$emoji $label', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : context.bodyText)),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: context.surfaceColor,
      side: BorderSide(color: selected ? AppColors.primary : context.borderColor),
      onSelected: (_) => setState(() => _category = id),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final MarketItem item;
  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaceColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MarketplaceItemScreen(itemId: item.id)),
        ),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: context.borderColor)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.1,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: item.images.isNotEmpty
                      ? Image.network(
                          item.images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(color: context.mutedSurface, child: const Center(child: Text('📦', style: TextStyle(fontSize: 32)))),
                        )
                      : Container(color: context.mutedSurface, child: const Center(child: Text('📦', style: TextStyle(fontSize: 32)))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text('${item.price.toStringAsFixed(0)} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
                    const SizedBox(height: 4),
                    Text(
                      marketplaceConditions[item.condition] ?? item.condition,
                      style: const TextStyle(fontSize: 10, color: AppColors.textFaint, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
