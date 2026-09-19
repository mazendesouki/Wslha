import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../rides/ride_tracking_screen.dart';
import 'order_invoice_screen.dart';
import 'orders_repository.dart';

const Map<String, Color> _statusColor = {
  'delivered': AppColors.success,
  'completed': AppColors.success,
  'rejected': AppColors.error,
  'cancelled': AppColors.error,
  'pending': AppColors.textFaint,
  'preparing': AppColors.accent,
  'on_the_way': AppColors.primary,
  'accepted': AppColors.primary,
  'arrived': AppColors.primary,
  'in_progress': AppColors.primary,
};

const _completedStatuses = {'delivered', 'completed'};
const _cancelledStatuses = {'cancelled', 'rejected'};

/// Same combined orders+rides feed as the driver's DriverOrdersScreen, just
/// filtered by customer_phone (fetchHistory) instead of driver_phone —
/// mirrors the same kind/period filters, status breakdown (مكتملة/ملغاة/
/// قيد التنفيذ) and type breakdown (توصيل/داخلي/خارجي/مطار), so both
/// apps read as the same product.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  final _repo = OrdersRepository();
  List<HistoryItem>? _items;
  bool _loading = true;
  String? _error;
  static const _kinds = ['all', 'ride', 'order'];
  late final TabController _tabController;
  String _kindFilter = 'all'; // 'all' | 'ride' | 'order'
  String _periodFilter = 'all'; // 'all' | 'today' | 'week' | 'month'
  String _statusFilter = 'all'; // 'all' | 'completed' | 'cancelled' | 'active'
  String _typeFilter = 'all'; // 'all' | 'order' | 'local' | 'external' | 'airport'
  bool _statsExpanded = false;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kinds.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      setState(() {
        _kindFilter = _kinds[_tabController.index];
        _statusFilter = 'all';
        _typeFilter = 'all';
      });
    });
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text.trim().toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = await SessionStore.load();
    if (session == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final items = await _repo.fetchHistory(session.phone);
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

  bool _withinPeriod(DateTime? date) {
    if (_periodFilter == 'all') return true;
    if (date == null) return false;
    final now = DateTime.now();
    // created_at comes back from Supabase as UTC — comparing its raw
    // year/month/day against DateTime.now() (local) misclassifies "اليوم"
    // near midnight (an order from 1am Cairo time is still "yesterday"
    // in UTC), silently dropping today's real items from the filter.
    final local = date.toLocal();
    switch (_periodFilter) {
      case 'today':
        return local.year == now.year && local.month == now.month && local.day == now.day;
      case 'week':
        return now.difference(local).inDays < 7;
      case 'month':
        return local.year == now.year && local.month == now.month;
      default:
        return true;
    }
  }

  String _itemStatusBucket(HistoryItem it) {
    if (_completedStatuses.contains(it.status)) return 'completed';
    if (_cancelledStatuses.contains(it.status)) return 'cancelled';
    return 'active';
  }

  String _itemTypeBucket(HistoryItem it) {
    if (it.kind == 'order') return 'order';
    return it.rideType ?? 'local';
  }

  void _toggleStatusFilter(String value) {
    setState(() => _statusFilter = _statusFilter == value ? 'all' : value);
  }

  void _toggleTypeFilter(String value) {
    setState(() => _typeFilter = _typeFilter == value ? 'all' : value);
  }

  Widget _chip(String value, String label, String groupValue, ValueChanged<String> onSelect) {
    final selected = value == groupValue;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : context.bodyText)),
      selected: selected,
      selectedColor: AppColors.primary,
      backgroundColor: context.surfaceColor,
      side: BorderSide(color: selected ? AppColors.primary : context.borderColor),
      onSelected: (_) => onSelect(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byKind = _items == null
        ? null
        : (_kindFilter == 'all' ? _items! : _items!.where((it) => it.kind == _kindFilter).toList());
    // kind+period only — the shared base both breakdowns below narrow further.
    final statsBase = byKind?.where((it) => _withinPeriod(it.createdAt)).toList();
    // The visible list honors the status/type tile selection plus the
    // invoice search box (matches id, route/store title, or subtitle).
    final filtered = statsBase
        ?.where((it) => _statusFilter == 'all' || _itemStatusBucket(it) == _statusFilter)
        .where((it) => _typeFilter == 'all' || _itemTypeBucket(it) == _typeFilter)
        .where((it) =>
            _search.isEmpty ||
            it.id.toLowerCase().contains(_search) ||
            it.title.toLowerCase().contains(_search) ||
            it.subtitle.toLowerCase().contains(_search))
        .toList();

    // Independent of the period chip — always "this calendar month" — so
    // the driver/customer can see monthly cost+count even while "اليوم" or
    // "الأسبوع" is the active period filter, plus a week-by-week split.
    final now = DateTime.now();
    final monthItems = byKind?.where((it) {
          final d = it.createdAt?.toLocal();
          return d != null && d.year == now.year && d.month == now.month;
        }).toList() ??
        const <HistoryItem>[];
    final monthCount = monthItems.length;
    num monthTotal = 0;
    final Map<int, List<HistoryItem>> byWeek = {};
    for (final it in monthItems) {
      if (_completedStatuses.contains(it.status)) monthTotal += it.total;
      final week = ((it.createdAt!.toLocal().day - 1) ~/ 7) + 1;
      byWeek.putIfAbsent(week, () => []).add(it);
    }
    final weekKeys = byWeek.keys.toList()..sort();

    // Status counts are scoped by the selected type tile, so tapping
    // "داخلي" narrows مكتملة/ملغاة/قيد التنفيذ to داخلي rides only.
    final statusScope = _typeFilter == 'all' ? statsBase : statsBase?.where((it) => _itemTypeBucket(it) == _typeFilter).toList();
    // Type counts are scoped by the selected status tile, symmetrically.
    final typeScope = _statusFilter == 'all' ? statsBase : statsBase?.where((it) => _itemStatusBucket(it) == _statusFilter).toList();

    num totalSpent = 0;
    int completedCount = 0;
    int cancelledCount = 0;
    num cancelledTotal = 0;
    int activeCount = 0;
    num activeTotal = 0;
    if (statusScope != null) {
      for (final it in statusScope) {
        if (_completedStatuses.contains(it.status)) {
          totalSpent += it.total;
          completedCount++;
        } else if (_cancelledStatuses.contains(it.status)) {
          cancelledCount++;
          cancelledTotal += it.total;
        } else {
          activeCount++;
          activeTotal += it.total;
        }
      }
    }

    int deliveryCount = 0;
    int localCount = 0;
    int externalCount = 0;
    int airportCount = 0;
    if (typeScope != null) {
      for (final it in typeScope) {
        if (it.kind == 'order') {
          deliveryCount++;
        } else {
          switch (it.rideType) {
            case 'external':
              externalCount++;
            case 'airport':
              airportCount++;
            default:
              localCount++;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: const Text('طلباتي ومشاويري')),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.borderColor)),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textFaint,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              indicator: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              padding: const EdgeInsets.all(4),
              tabs: const [
                Tab(text: '📋 الكل'),
                Tab(text: '🚗 رحلات'),
                Tab(text: '🛵 توصيل'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('today', '📅 اليوم', _periodFilter, (v) => setState(() => _periodFilter = v)),
                _chip('week', '🗓️ الأسبوع', _periodFilter, (v) => setState(() => _periodFilter = v)),
                _chip('month', '📆 الشهر', _periodFilter, (v) => setState(() => _periodFilter = v)),
                _chip('all', '⏳ كل الوقت', _periodFilter, (v) => setState(() => _periodFilter = v)),
              ],
            ),
          ),
          if (statsBase != null && statsBase.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _statsExpanded = !_statsExpanded),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, Color(0xFF0E4D3D)],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  _summaryStat('$monthCount', 'رحلة/طلب هذا الشهر'),
                                  const SizedBox(width: 18),
                                  Container(width: 1, height: 26, color: Colors.white24),
                                  const SizedBox(width: 18),
                                  _summaryStat('${monthTotal.toStringAsFixed(0)} ج.م', 'تكلفة الشهر'),
                                ],
                              ),
                            ),
                            Icon(_statsExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_statsExpanded) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _statusTile('✅', 'مكتملة', completedCount, totalSpent, AppColors.success,
                              selected: _statusFilter == 'completed', onTap: () => _toggleStatusFilter('completed')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _statusTile('❌', 'ملغاة', cancelledCount, cancelledTotal, AppColors.error,
                              selected: _statusFilter == 'cancelled', onTap: () => _toggleStatusFilter('cancelled')),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _statusTile('⏳', 'قيد التنفيذ', activeCount, activeTotal, AppColors.accent,
                              selected: _statusFilter == 'active', onTap: () => _toggleStatusFilter('active')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _typeTile('🛵', 'توصيل', deliveryCount, selected: _typeFilter == 'order', onTap: () => _toggleTypeFilter('order'))),
                        const SizedBox(width: 8),
                        Expanded(child: _typeTile('🚗', 'داخلي', localCount, selected: _typeFilter == 'local', onTap: () => _toggleTypeFilter('local'))),
                        const SizedBox(width: 8),
                        Expanded(child: _typeTile('🛣️', 'خارجي', externalCount, selected: _typeFilter == 'external', onTap: () => _toggleTypeFilter('external'))),
                        const SizedBox(width: 8),
                        Expanded(child: _typeTile('✈️', 'مطار', airportCount, selected: _typeFilter == 'airport', onTap: () => _toggleTypeFilter('airport'))),
                      ],
                    ),
                    if (weekKeys.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.borderColor)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('📅 تقسيم أسبوعي (الشهر الحالي)', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            const SizedBox(height: 6),
                            for (final w in weekKeys)
                              _weekRow(
                                'الأسبوع $w (${(w - 1) * 7 + 1}–${w * 7})',
                                byWeek[w]!.length,
                                byWeek[w]!.where((it) => _completedStatuses.contains(it.status)).fold<num>(0, (sum, it) => sum + it.total),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'ابحث برقم الفاتورة أو الاسم...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.isNotEmpty ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _searchCtrl.clear) : null,
                isDense: true,
                filled: true,
                fillColor: context.surfaceColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.borderColor)),
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
                              OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                            ],
                          ),
                        ),
                      )
                    : (filtered == null || filtered.isEmpty)
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('📦', style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 12),
                                Text(
                                  _search.isNotEmpty
                                      ? 'مفيش نتائج تطابق البحث "${_searchCtrl.text}"'
                                      : _statusFilter != 'all' || _typeFilter != 'all'
                                          ? 'مفيش نتائج للتصنيف المحدد — جرّب تشيل الفلتر'
                                          : _kindFilter == 'all'
                                              ? 'لا يوجد طلبات أو مشاوير سابقة بعد'
                                              : _kindFilter == 'ride'
                                                  ? 'لسه مفيش رحلات في الفترة دي'
                                                  : 'لسه مفيش توصيل في الفترة دي',
                                  style: const TextStyle(color: AppColors.textFaint),
                                  textAlign: TextAlign.center,
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
                              itemBuilder: (context, i) {
                                final item = filtered[i];
                                final color = _statusColor[item.status] ?? AppColors.textFaint;
                                final isRide = item.kind == 'ride';
                                return Material(
                                  color: context.surfaceColor,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => isRide
                                            ? RideTrackingScreen(rideId: item.id)
                                            : OrderInvoiceScreen(orderId: item.id),
                                      ),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: context.borderColor),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: (isRide ? AppColors.primary : AppColors.accent).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(13),
                                            ),
                                            child: Text(isRide ? '🚖' : '📦', style: const TextStyle(fontSize: 19)),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                                    const SizedBox(width: 5),
                                                    Text(item.subtitle, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
                                                  ],
                                                ),
                                                if (item.createdAt != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    _formatDate(item.createdAt!),
                                                    style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Text('${item.total} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.chevron_left, color: AppColors.textFaint, size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _weekRow(String label, int count, num total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
          Text('$count رحلة/طلب — ${total.toStringAsFixed(0)} ج.م', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.bodyText)),
        ],
      ),
    );
  }

  Widget _statusTile(String emoji, String label, int count, num total, Color color,
      {bool selected = false, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : context.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : context.borderColor, width: selected ? 1.6 : 1),
          ),
          child: Column(
            children: [
              Text('$emoji $count', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
              Text('${total.toStringAsFixed(0)} ج.م', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeTile(String emoji, String label, int count, {bool selected = false, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.1) : context.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.primary : context.borderColor, width: selected ? 1.6 : 1),
          ),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 3),
              Text(
                '$count',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: selected ? AppColors.primary : context.bodyText),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: selected ? AppColors.primary : AppColors.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} — ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
