import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_repository.dart';
import 'vehicle_service_shared.dart';

/// "الملخص العام" — per db/security-151's get_my_vehicle_service_summary,
/// a lifetime rollup per distinct service: how many times it was done,
/// total spent, and when it was last done. Not limited to one month.
class VehicleServiceSummaryScreen extends StatefulWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  const VehicleServiceSummaryScreen({super.key, required this.repo, required this.driverPhone});

  @override
  State<VehicleServiceSummaryScreen> createState() => _VehicleServiceSummaryScreenState();
}

class _VehicleServiceSummaryScreenState extends State<VehicleServiceSummaryScreen> {
  late Future<List<VehicleServiceSummaryRow>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repo.getServiceSummary(widget.driverPhone);
  }

  String _labelFor(VehicleServiceSummaryRow r) {
    if (r.serviceType == 'other' && r.customLabel != null && r.customLabel!.isNotEmpty) {
      return '➕ ${r.customLabel}';
    }
    if (r.maintenanceItemKey != null) {
      return vehicleMaintenanceItemLabels[r.maintenanceItemKey] ?? r.maintenanceItemKey!;
    }
    return vehicleServiceTypeLabels[r.serviceType] ?? r.serviceType;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: const Text('📋 الملخص العام')),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<VehicleServiceSummaryRow>>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = snap.data!;
            if (rows.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('مفيش سجلات لسه — سجّل أول عملية صيانة عشان يظهر هنا', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textFaint)),
                ),
              );
            }
            final grandTotal = rows.fold<double>(0, (s, r) => s + r.totalCost);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('💰 إجمالي مصاريف الصيانة (كل الفترة)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${grandTotal.toStringAsFixed(0)} ج.م', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primary)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final r in rows) _SummaryRowCard(label: _labelFor(r), row: r),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryRowCard extends StatelessWidget {
  final String label;
  final VehicleServiceSummaryRow row;
  const _SummaryRowCard({required this.label, required this.row});

  @override
  Widget build(BuildContext context) {
    final d = row.lastPerformedAt.toLocal();
    final dateStr = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
              Text('${row.totalCost.toStringAsFixed(0)} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text('🔁 ${row.entriesCount} مرة', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              Text('📅 آخر مرة: $dateStr', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
            ],
          ),
        ],
      ),
    );
  }
}
