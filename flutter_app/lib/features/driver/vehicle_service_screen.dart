import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'driver_repository.dart';
import 'vehicle_service_detail_screen.dart';
import 'vehicle_service_monthly_report_screen.dart';
import 'vehicle_service_repository.dart';
import 'vehicle_service_shared.dart';
import 'vehicle_service_summary_screen.dart';
import 'vehicle_service_type_selection_screen.dart';

/// "خدمات المركبات" — سجل/ملف صيانة العربية: صيانة دورية، وقود (سعر
/// اللتر + معدل الاستهلاك محسوب تلقائيًا)، كاوتش، زيت، فحص المحرك، وأي
/// خدمة تانية السائق يحددها بنفسه. See db/security-134/137.
///
/// Logging a new entry is a 3-step full-page flow (list → dedicated form
/// → confirmation, see vehicle_service_type_selection/form/confirmation_
/// screen.dart) rather than a bottom sheet — explicit driver feedback on
/// the old combined sheet. Tapping an existing entry opens
/// VehicleServiceDetailScreen (edit/delete live there now).
class VehicleServiceScreen extends StatefulWidget {
  final String driverPhone;
  const VehicleServiceScreen({super.key, required this.driverPhone});

  @override
  State<VehicleServiceScreen> createState() => _VehicleServiceScreenState();
}

class _VehicleServiceScreenState extends State<VehicleServiceScreen> {
  final _repo = VehicleServiceRepository();
  final _driverRepo = DriverRepository();
  late Future<List<VehicleServiceLog>> _future;
  late Future<List<VehicleServiceLog>> _fuelFuture;
  late Future<List<MaintenanceDueStatus>> _maintenanceDueFuture;
  late Future<Map<String, dynamic>?> _vehicleInfoFuture;
  double? _tankCapacity;
  String? _filter;

  @override
  void initState() {
    super.initState();
    _load();
    _loadFuelSummary();
    _loadMaintenanceDue();
    _vehicleInfoFuture = _driverRepo.fetchVehicleInfo(widget.driverPhone);
    _repo.getFuelTankCapacity(widget.driverPhone).then((v) {
      if (mounted) setState(() => _tankCapacity = v);
    });
  }

  void _load() {
    _future = _repo.listMine(widget.driverPhone, serviceType: _filter);
  }

  void _loadFuelSummary() {
    _fuelFuture = _repo.listMine(widget.driverPhone, serviceType: 'fuel');
  }

  void _loadMaintenanceDue() {
    _maintenanceDueFuture = _repo.getMaintenanceDueStatus(widget.driverPhone);
  }

  Future<void> _refresh() async {
    setState(() {
      _load();
      _loadFuelSummary();
      _loadMaintenanceDue();
    });
    await Future.wait([_future, _fuelFuture, _maintenanceDueFuture]);
  }

  Future<void> _openTypeSelection() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VehicleServiceTypeSelectionScreen(repo: _repo, driverPhone: widget.driverPhone)),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _openDetail(VehicleServiceLog log) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VehicleServiceDetailScreen(repo: _repo, driverPhone: widget.driverPhone, log: log)),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _editTankCapacity() async {
    final ctrl = TextEditingController(text: _tankCapacity?.toStringAsFixed(0) ?? '');
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('⛽ سعة خزان الوقود'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'السعة باللتر'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(double.tryParse(ctrl.text.trim())),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (value == null || value <= 0) return;
    final ok = await _repo.setFuelTankCapacity(widget.driverPhone, value);
    if (!mounted) return;
    if (ok) {
      setState(() => _tankCapacity = value);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر حفظ سعة الخزان')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(
        title: const Text('🔧 خدمات المركبة'),
        actions: [
          IconButton(
            tooltip: 'الملخص العام',
            icon: const Text('📋', style: TextStyle(fontSize: 18)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VehicleServiceSummaryScreen(repo: _repo, driverPhone: widget.driverPhone)),
            ),
          ),
          IconButton(
            tooltip: 'التقرير الشهري',
            icon: const Text('📊', style: TextStyle(fontSize: 18)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VehicleServiceMonthlyReportScreen(repo: _repo, driverPhone: widget.driverPhone)),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openTypeSelection,
        icon: const Icon(Icons.add),
        label: const Text('سجّل عملية'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            FutureBuilder<Map<String, dynamic>?>(
              future: _vehicleInfoFuture,
              builder: (context, snap) => _VehicleInfoHeaderCard(vehicle: snap.data),
            ),
            FutureBuilder<List<VehicleServiceLog>>(
              future: _fuelFuture,
              builder: (context, snap) => _FuelSummaryCard(
                logs: snap.data ?? const [],
                tankCapacity: _tankCapacity,
                onEditCapacity: _editTankCapacity,
              ),
            ),
            FutureBuilder<List<MaintenanceDueStatus>>(
              future: _maintenanceDueFuture,
              builder: (context, snap) => _MaintenanceDueCard(items: snap.data ?? const []),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  _filterChip(null, 'الكل'),
                  for (final e in vehicleServiceTypeLabels.entries) _filterChip(e.key, e.value),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<VehicleServiceLog>>(
                  future: _future,
                  builder: (context, snap) {
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final logs = snap.data!;
                    if (logs.isEmpty) {
                      return ListView(
                        children: const [
                          SizedBox(height: 80),
                          Center(
                            child: Text('مفيش سجلات لسه — اضغط "سجّل عملية" عشان تضيف أول عملية',
                                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textFaint)),
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _LogCard(log: logs[i], onTap: () => _openDetail(logs[i])),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String? type, String label) {
    final selected = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected ? Colors.white : null)),
        selected: selected,
        selectedColor: AppColors.primary,
        onSelected: (_) => setState(() {
          _filter = type;
          _load();
        }),
      ),
    );
  }
}

/// Read-only strip showing the vehicle details already captured at
/// registration (driver_applications) — model/color/plate/year — so the
/// driver never has to re-type them here; every log entry is implicitly
/// tied to this one vehicle via driver_phone. Collapses to nothing while
/// loading/on failure rather than showing a placeholder skeleton, since
/// this is a nice-to-have header, not something worth blocking on.
class _VehicleInfoHeaderCard extends StatelessWidget {
  final Map<String, dynamic>? vehicle;
  const _VehicleInfoHeaderCard({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final v = vehicle;
    if (v == null) return const SizedBox.shrink();
    // vehicle_year/vehicle_reg_number can be numeric or text depending on
    // when the driver_applications row was created — toString() instead of
    // `as String?`, same fix driver_profile_screen.dart already needed.
    final model = v['vehicle_model']?.toString();
    final color = v['vehicle_color']?.toString();
    final regNumber = v['vehicle_reg_number']?.toString();
    final year = v['vehicle_year']?.toString();
    final parts = [model, color].where((e) => e != null && e.isNotEmpty).join(' — ');
    if (parts.isEmpty && (regNumber == null || regNumber.isEmpty) && (year == null || year.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.borderColor)),
      child: Row(
        children: [
          const Text('🚗', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (parts.isNotEmpty) Text(parts, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                Wrap(
                  spacing: 10,
                  children: [
                    if (regNumber != null && regNumber.isNotEmpty)
                      Text('لوحة: $regNumber', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                    if (year != null && year.isNotEmpty)
                      Text('موديل: $year', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Average consumption (km/liter) computed from odometer deltas between
/// consecutive fill-ups — the standard "full-to-full" method — plus
/// running totals, shown above the list regardless of the active filter.
class _FuelSummaryCard extends StatelessWidget {
  final List<VehicleServiceLog> logs;
  final double? tankCapacity;
  final VoidCallback onEditCapacity;
  const _FuelSummaryCard({required this.logs, required this.tankCapacity, required this.onEditCapacity});

  @override
  Widget build(BuildContext context) {
    final withOdometer = logs.where((l) => l.odometerKm != null && l.fuelLiters != null && l.fuelLiters! > 0).toList()
      ..sort((a, b) => a.odometerKm!.compareTo(b.odometerKm!));

    double kmSum = 0, literSum = 0;
    for (var i = 1; i < withOdometer.length; i++) {
      final deltaKm = withOdometer[i].odometerKm! - withOdometer[i - 1].odometerKm!;
      if (deltaKm > 0) {
        kmSum += deltaKm;
        literSum += withOdometer[i].fuelLiters!;
      }
    }
    final avgKmPerLiter = literSum > 0 ? kmSum / literSum : null;
    final totalCost = logs.fold<double>(0, (s, l) => s + (l.cost ?? 0));
    final totalLiters = logs.fold<double>(0, (s, l) => s + (l.fuelLiters ?? 0));

    if (logs.isEmpty && tankCapacity == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('⛽ ملخص الوقود', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13))),
              InkWell(
                onTap: onEditCapacity,
                child: Row(
                  children: [
                    Text(
                      tankCapacity != null ? 'سعة الخزان: ${tankCapacity!.toStringAsFixed(0)} لتر' : 'حدّد سعة الخزان',
                      style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.edit, size: 13, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                Text(
                  avgKmPerLiter != null ? 'معدل الاستهلاك: ${avgKmPerLiter.toStringAsFixed(1)} كم/لتر' : 'معدل الاستهلاك: محتاج تعبئتين على الأقل',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Text('إجمالي الإنفاق: ${totalCost.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                Text('إجمالي اللترات: ${totalLiters.toStringAsFixed(1)} لتر', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows which periodic-maintenance catalog items (db/security-142) are
/// overdue or due soon, computed server-side from km since each item was
/// last logged against the driver's latest known odometer reading.
/// Collapses to nothing once everything is ok/never-tracked-yet, so it
/// doesn't take space when there's nothing actionable.
class _MaintenanceDueCard extends StatelessWidget {
  final List<MaintenanceDueStatus> items;
  const _MaintenanceDueCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final due = items.where((i) => i.status == 'overdue' || i.status == 'due_soon').toList()
      ..sort((a, b) {
        if (a.status != b.status) return a.status == 'overdue' ? -1 : 1;
        if (a.importance != b.importance) return a.importance == 'critical' ? -1 : 1;
        return 0;
      });
    if (due.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🛠️ صيانة مطلوبة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final i in due)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: i.status == 'overdue' ? AppColors.error.withValues(alpha: 0.15) : const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${i.status == 'overdue' ? '⛔' : '⏰'} ${i.labelAr}${i.importance == 'critical' ? ' ‼️' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: i.status == 'overdue' ? AppColors.error : const Color(0xFFB45309),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final VehicleServiceLog log;
  final VoidCallback onTap;
  const _LogCard({required this.log, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = log.serviceType == 'other' && log.customLabel != null
        ? '➕ ${log.customLabel}'
        : vehicleServiceTypeLabels[log.serviceType] ?? log.serviceType;
    final d = log.performedAt.toLocal();
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                Text(dateStr, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left, size: 18, color: AppColors.textFaint),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (log.cost != null) Text('💰 ${log.cost!.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (log.odometerKm != null) Text('🧭 ${log.odometerKm!.toStringAsFixed(0)} كم', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                if (log.fuelLiters != null) Text('⛽ ${log.fuelLiters!.toStringAsFixed(1)} لتر', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                if (log.pricePerLiter != null) Text('(${log.pricePerLiter!.toStringAsFixed(2)} ج.م/لتر)', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                if (log.quantity != null)
                  Text(
                    '${formatVehicleServiceQuantity(log.quantity)} ${vehicleServiceQuantityUnitConfigs[log.serviceType]?.quantitySuffix ?? ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                  ),
                if (log.unitPrice != null)
                  Text(
                    '(${log.unitPrice!.toStringAsFixed(2)} ${vehicleServiceQuantityUnitConfigs[log.serviceType]?.unitPriceSuffix ?? 'ج.م'})',
                    style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                  ),
              ],
            ),
            if (log.maintenanceItems != null && log.maintenanceItems!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final key in log.maintenanceItems!)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
                      child: Text(vehicleMaintenanceItemLabels[key] ?? key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ),
                ],
              ),
            ],
            if (log.serviceCenter != null && log.serviceCenter!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('🏢 ${log.serviceCenter}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
            ],
            if (log.notes != null && log.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(log.notes!, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
            ],
          ],
        ),
      ),
    );
  }
}
