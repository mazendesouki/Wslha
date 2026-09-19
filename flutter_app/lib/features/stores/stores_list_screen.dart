import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'store_detail_screen.dart';
import 'stores_models.dart';
import 'stores_repository.dart';

/// Entry point for "🛍️ خدمة دليفري" on the home tab — browse active
/// stores and open one to shop, same data source as store/[id].astro.
class StoresListScreen extends StatefulWidget {
  const StoresListScreen({super.key});

  @override
  State<StoresListScreen> createState() => _StoresListScreenState();
}

class _StoresListScreenState extends State<StoresListScreen> {
  final _repo = StoresRepository();
  List<StoreRow>? _stores;
  bool _loading = true;
  String? _error;
  String _query = '';

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
      final stores = await _repo.fetchStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
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
    final filtered = _stores?.where((s) {
      if (_query.trim().isEmpty) return true;
      final q = _query.trim();
      return s.name.contains(q) || s.category.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('stores_list_appbar_title'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: context.tr('stores_list_search_hint'),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
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
                              OutlinedButton(onPressed: _load, child: Text(context.tr('stores_list_retry'))),
                            ],
                          ),
                        ),
                      )
                    : (filtered == null || filtered.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🏪', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  _query.isEmpty ? context.tr('stores_list_empty_no_stores') : context.tr('stores_list_empty_no_results'),
                                  style: const TextStyle(color: AppColors.textFaint),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _StoreCard(store: filtered[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final StoreRow store;
  const _StoreCard({required this.store});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaceColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StoreDetailScreen(store: store)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
                child: Text(store.emoji, style: const TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(store.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                        ),
                        if (!store.isOpen)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
                            child: Text(context.tr('stores_list_closed_badge'), style: const TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w800)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(store.tagline.isNotEmpty ? store.tagline : store.category,
                        style: const TextStyle(fontSize: 11, color: AppColors.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star, color: AppColors.accent, size: 13),
                        const SizedBox(width: 2),
                        Text('${store.rating} (${store.reviews})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 10),
                        const Icon(Icons.timer_outlined, color: AppColors.textFaint, size: 13),
                        const SizedBox(width: 2),
                        Text(store.deliveryTime, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
