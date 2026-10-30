import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_form_screen.dart';
import 'vehicle_service_repository.dart';
import 'vehicle_service_shared.dart';

/// Full read-only detail page for one logged entry — reached by tapping a
/// card on the main list or in the monthly report. Edit/delete live here
/// instead of being buried in the form screen, matching the mockup's
/// separate "عرض السجل بالتفصيل" step.
class VehicleServiceDetailScreen extends StatefulWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  final VehicleServiceLog log;
  const VehicleServiceDetailScreen({super.key, required this.repo, required this.driverPhone, required this.log});

  @override
  State<VehicleServiceDetailScreen> createState() => _VehicleServiceDetailScreenState();
}

class _VehicleServiceDetailScreenState extends State<VehicleServiceDetailScreen> {
  late VehicleServiceLog _log;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _log = widget.log;
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => VehicleServiceFormScreen(repo: widget.repo, driverPhone: widget.driverPhone, existingLog: _log)),
    );
    if (changed == true && mounted) {
      // The entry may have changed in ways this screen can't easily
      // re-derive in place (type switched, cost recomputed server-side)
      // — simplest correct thing is to pop back to the list with `true`
      // so it refreshes, rather than try to patch _log locally.
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف السجل؟'),
        content: const Text('مش هينفع ترجع فيه بعد الحذف.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('حذف', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    final ok = await widget.repo.deleteLog(widget.driverPhone, _log.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر الحذف، حاول مرة أخرى.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final log = _log;
    final label = log.serviceType == 'other' && log.customLabel != null
        ? '➕ ${log.customLabel}'
        : (log.maintenanceItems?.length == 1
            ? (vehicleMaintenanceItemLabels[log.maintenanceItems!.first] ?? log.maintenanceItems!.first)
            : vehicleServiceTypeLabels[log.serviceType] ?? log.serviceType);
    final d = log.performedAt.toLocal();
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final quantityConfig = vehicleServiceQuantityUnitConfigs[log.serviceType];

    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(label)),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.borderColor)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailRow(label: 'التاريخ', value: dateStr),
                    if (log.odometerKm != null) _DetailRow(label: 'قراءة العداد', value: '${log.odometerKm!.toStringAsFixed(0)} كم'),
                    if (log.fuelLiters != null) _DetailRow(label: 'نوع الزيت/الوقود', value: '${log.fuelLiters!.toStringAsFixed(1)} لتر'),
                    if (log.pricePerLiter != null) _DetailRow(label: 'سعر اللتر', value: '${log.pricePerLiter!.toStringAsFixed(2)} ج.م'),
                    if (log.quantity != null)
                      _DetailRow(label: quantityConfig?.quantityLabel ?? 'الكمية', value: '${formatVehicleServiceQuantity(log.quantity)} ${quantityConfig?.quantitySuffix ?? ''}'),
                    if (log.unitPrice != null)
                      _DetailRow(label: quantityConfig?.unitPriceLabel ?? 'سعر الوحدة', value: '${log.unitPrice!.toStringAsFixed(2)} ج.م'),
                    if (log.serviceCenter != null && log.serviceCenter!.isNotEmpty) _DetailRow(label: 'مركز الصيانة', value: log.serviceCenter!),
                    if (log.cost != null) _DetailRow(label: 'التكلفة الإجمالية', value: '${log.cost!.toStringAsFixed(0)} ج.م', emphasize: true),
                    if (log.notes != null && log.notes!.isNotEmpty) _DetailRow(label: 'ملاحظات', value: log.notes!),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _deleting ? null : _edit, child: const Text('تعديل')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _deleting ? null : _delete,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                child: _deleting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                    : const Text('🗑️ حذف السجل'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const _DetailRow({required this.label, required this.value, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textFaint)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 14, fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700, color: emphasize ? AppColors.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}
