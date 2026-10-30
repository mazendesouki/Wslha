import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'vehicle_service_form_screen.dart';
import 'vehicle_service_repository.dart';
import 'vehicle_service_shared.dart';

/// Step 1 of the "سجّل عملية" flow — a full-page list of service types
/// (instead of a chip row inside a shared bottom sheet), each opening its
/// own dedicated form screen. Matches the step-by-step flow the driver
/// asked for: list → dedicated form → confirmation screen.
class VehicleServiceTypeSelectionScreen extends StatelessWidget {
  final VehicleServiceRepository repo;
  final String driverPhone;
  const VehicleServiceTypeSelectionScreen({super.key, required this.repo, required this.driverPhone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: const Text('اختيار نوع الخدمة')),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: vehicleServiceTypeLabels.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final entry = vehicleServiceTypeLabels.entries.elementAt(i);
            final guidance = vehicleServiceTypeGuidance[entry.key];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VehicleServiceFormScreen(repo: repo, driverPhone: driverPhone, initialType: entry.key),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
                      child: Icon(vehicleServiceTypeIcons[entry.key] ?? Icons.build, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                          if (guidance != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              guidance.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_left, color: AppColors.textFaint),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
