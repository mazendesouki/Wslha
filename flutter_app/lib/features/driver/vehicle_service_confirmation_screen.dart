import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_repository.dart';
import 'vehicle_service_shared.dart';

/// Step 3 of the "سجّل عملية" flow — shown once (replacing the form
/// screen) right after a NEW entry saves successfully. For a maintenance
/// item specifically, also shows when it'll next be due, pulled live from
/// get_maintenance_due_status (the entry we just saved resets that
/// item's baseline, so "due in X كم" reflects it immediately).
class VehicleServiceConfirmationScreen extends StatefulWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  final String serviceType;
  final String? maintenanceItemKey;
  final String? customLabel;
  final double cost;
  final String? serviceCenter;
  final DateTime performedAt;

  const VehicleServiceConfirmationScreen({
    super.key,
    required this.repo,
    required this.driverPhone,
    required this.serviceType,
    this.maintenanceItemKey,
    this.customLabel,
    required this.cost,
    this.serviceCenter,
    required this.performedAt,
  });

  @override
  State<VehicleServiceConfirmationScreen> createState() => _VehicleServiceConfirmationScreenState();
}

class _VehicleServiceConfirmationScreenState extends State<VehicleServiceConfirmationScreen> {
  late Future<List<MaintenanceDueStatus>> _dueFuture;

  @override
  void initState() {
    super.initState();
    _dueFuture = widget.maintenanceItemKey != null
        ? widget.repo.getMaintenanceDueStatus(widget.driverPhone)
        : Future.value(const []);
  }

  void _backToList() {
    // Stack added on top of the main خدمات المركبة screen is exactly
    // [TypeSelection, Confirmation] (the form screen that sat between
    // them was replaced, not pushed, by this screen) — two pops lands
    // back on the list, the second carrying `true` so it refreshes.
    Navigator.of(context).pop();
    Navigator.of(context).pop(true);
  }

  void _logAnother() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.performedAt.toLocal();
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final label = widget.serviceType == 'other' && widget.customLabel != null && widget.customLabel!.isNotEmpty
        ? '➕ ${widget.customLabel}'
        : (widget.maintenanceItemKey != null
            ? (vehicleMaintenanceItemLabels[widget.maintenanceItemKey] ?? widget.maintenanceItemKey!)
            : vehicleServiceTypeLabels[widget.serviceType] ?? widget.serviceType);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToList();
      },
      child: Scaffold(
        backgroundColor: context.mutedSurface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
                ),
                const SizedBox(height: 20),
                const Text('تم حفظ الخدمة بنجاح', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 6),
                Text('$label — بتاريخ $dateStr', style: const TextStyle(fontSize: 13, color: AppColors.textFaint), textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.borderColor)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('ملخص العملية', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      const SizedBox(height: 10),
                      _SummaryLine(label: 'التكلفة الإجمالية', value: '${widget.cost.toStringAsFixed(0)} ج.م'),
                      if (widget.serviceCenter != null && widget.serviceCenter!.isNotEmpty)
                        _SummaryLine(label: 'مركز الصيانة', value: widget.serviceCenter!),
                    ],
                  ),
                ),
                if (widget.maintenanceItemKey != null) ...[
                  const SizedBox(height: 14),
                  FutureBuilder<List<MaintenanceDueStatus>>(
                    future: _dueFuture,
                    builder: (context, snap) {
                      final items = snap.data ?? const [];
                      MaintenanceDueStatus? match;
                      for (final i in items) {
                        if (i.itemKey == widget.maintenanceItemKey) match = i;
                      }
                      if (match == null) return const SizedBox.shrink();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('📅 موعد الصيانة القادمة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                            const SizedBox(height: 6),
                            Text(
                              match.intervalKm != null
                                  ? 'المسافة المتبقية حتى الصيانة القادمة: ${match.intervalKm!.toStringAsFixed(0)} كم'
                                  : 'هيظهر تنبيه لما يقرب ميعاد الصيانة القادمة',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                              child: const Text('مستقرة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.success)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const Spacer(),
                FilledButton(onPressed: _backToList, child: const Text('عرض السجل')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _logAnother, child: const Text('تسجيل عملية تانية')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
