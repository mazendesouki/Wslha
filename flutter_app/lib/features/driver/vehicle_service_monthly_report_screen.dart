import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_detail_screen.dart';
import 'vehicle_service_filter_screen.dart';
import 'vehicle_service_repository.dart';
import 'vehicle_service_shared.dart';

const List<String> _arabicMonthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// "التقرير الشهري" — per db/security-151, shows every service logged in
/// one calendar month, broken down by type with per-type and grand
/// totals (plus a bar chart of the same breakdown), with prev/next month
/// navigation or a dedicated filter screen (type + year + month). The
/// service-type filter is applied client-side — the underlying RPCs
/// already return everything for the month, so there's no need for a new
/// DB parameter just to narrow what's displayed.
class VehicleServiceMonthlyReportScreen extends StatefulWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  const VehicleServiceMonthlyReportScreen({super.key, required this.repo, required this.driverPhone});

  @override
  State<VehicleServiceMonthlyReportScreen> createState() => _VehicleServiceMonthlyReportScreenState();
}

class _VehicleServiceMonthlyReportScreenState extends State<VehicleServiceMonthlyReportScreen> {
  late int _year;
  late int _month;
  String? _typeFilter;
  late Future<List<VehicleServiceMonthlyTotal>> _totalsFuture;
  late Future<List<VehicleServiceLog>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  void _load() {
    _totalsFuture = widget.repo.getMonthlyTotals(widget.driverPhone, _year, _month);
    _entriesFuture = widget.repo.listMonthlyReport(widget.driverPhone, _year, _month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      var m = _month + delta;
      var y = _year;
      if (m < 1) {
        m = 12;
        y -= 1;
      } else if (m > 12) {
        m = 1;
        y += 1;
      }
      _month = m;
      _year = y;
      _load();
    });
  }

  Future<void> _openFilter() async {
    final result = await Navigator.of(context).push<VehicleServiceFilterResult>(
      MaterialPageRoute(
        builder: (_) => VehicleServiceFilterScreen(initialType: _typeFilter, initialYear: _year, initialMonth: _month),
      ),
    );
    if (result == null) return;
    setState(() {
      _typeFilter = result.serviceType;
      _year = result.year;
      _month = result.month;
      _load();
    });
  }

  Future<void> _openDetail(VehicleServiceLog log) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VehicleServiceDetailScreen(repo: widget.repo, driverPhone: widget.driverPhone, log: log)),
    );
    if (changed == true && mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth = _year == now.year && _month == now.month;

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(
        title: const Text('📊 التقرير الشهري'),
        actions: [IconButton(tooltip: 'تصفية', icon: const Icon(Icons.filter_list), onPressed: _openFilter)],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.borderColor)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_right)),
                  Column(
                    children: [
                      Text('${_arabicMonthNames[_month - 1]} $_year', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      if (_typeFilter != null)
                        Text(vehicleServiceTypeLabels[_typeFilter] ?? _typeFilter!, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  IconButton(onPressed: isCurrentMonth ? null : () => _shiftMonth(1), icon: const Icon(Icons.chevron_left)),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  setState(_load);
                  await Future.wait([_totalsFuture, _entriesFuture]);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    FutureBuilder<List<VehicleServiceMonthlyTotal>>(
                      future: _totalsFuture,
                      builder: (context, snap) {
                        if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                        final totals = (snap.data!..sort((a, b) => b.totalCost.compareTo(a.totalCost)))
                            .where((t) => _typeFilter == null || t.serviceType == _typeFilter)
                            .toList();
                        final grandTotal = totals.fold<double>(0, (s, t) => s + t.totalCost);
                        final totalEntries = totals.fold<int>(0, (s, t) => s + t.entriesCount);
                        if (totals.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Center(child: Text('مفيش سجلات تطابق الفلترة', style: TextStyle(color: AppColors.textFaint))),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('💰 إجمالي مصاريف الصيانة هذا الشهر', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text('${grandTotal.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primary)),
                                  Text('$totalEntries عملية مسجّلة', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _MonthlyCostBarChart(totals: totals),
                            const SizedBox(height: 14),
                            const Text('التفصيل حسب النوع', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                            const SizedBox(height: 8),
                            for (final t in totals)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.borderColor)),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(vehicleServiceTypeLabels[t.serviceType] ?? t.serviceType, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                                    Text('${t.entriesCount} عملية', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                                    const SizedBox(width: 10),
                                    Text('${t.totalCost.toStringAsFixed(0)} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 14),
                            const Text('كل العمليات', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),
                    FutureBuilder<List<VehicleServiceLog>>(
                      future: _entriesFuture,
                      builder: (context, snap) {
                        final entries = (snap.data ?? const []).where((e) => _typeFilter == null || e.serviceType == _typeFilter).toList();
                        return Column(
                          children: [
                            for (final e in entries) _MonthlyEntryTile(log: e, onTap: () => _openDetail(e)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain Flutter-widget bar chart (no chart package dependency) — a bar
/// per service type, height proportional to its share of this month's
/// cost, labeled with the type and its total.
class _MonthlyCostBarChart extends StatelessWidget {
  final List<VehicleServiceMonthlyTotal> totals;
  const _MonthlyCostBarChart({required this.totals});

  @override
  Widget build(BuildContext context) {
    final maxCost = totals.fold<double>(0, (m, t) => t.totalCost > m ? t.totalCost : m);
    if (maxCost <= 0) return const SizedBox.shrink();
    const chartHeight = 140.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
      decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.borderColor)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final t in totals)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.totalCost.toStringAsFixed(0), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Container(
                  width: 28,
                  height: chartHeight * (t.totalCost / maxCost).clamp(0.04, 1.0),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 48,
                  child: Text(
                    (vehicleServiceTypeLabels[t.serviceType] ?? t.serviceType).replaceAll(RegExp(r'^\S+\s'), ''),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MonthlyEntryTile extends StatelessWidget {
  final VehicleServiceLog log;
  final VoidCallback onTap;
  const _MonthlyEntryTile({required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = log.serviceType == 'other' && log.customLabel != null
        ? '➕ ${log.customLabel}'
        : (log.maintenanceItems?.length == 1
            ? (vehicleMaintenanceItemLabels[log.maintenanceItems!.first] ?? log.maintenanceItems!.first)
            : vehicleServiceTypeLabels[log.serviceType] ?? log.serviceType);
    final d = log.performedAt.toLocal();
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.borderColor)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                ],
              ),
            ),
            if (log.cost != null) Text('${log.cost!.toStringAsFixed(0)} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_left, size: 16, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}
