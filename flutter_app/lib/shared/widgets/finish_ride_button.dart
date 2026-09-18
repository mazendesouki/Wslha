import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../features/rides/fare_calculator.dart' show haversineKm;
import '../../features/rides/ride_repository.dart';

/// Gates "إنهاء الرحلة" behind the driver's live GPS proximity to the
/// ride's destination instead of letting it fire at any point once the
/// ride is in progress. Below [thresholdMeters] the normal button is
/// enabled; above it, it's shown disabled with the remaining distance and
/// a manual-confirm fallback (dialog) covers weak/indoor GPS signal.
class FinishRideButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  final String driverPhone;
  final double destinationLat;
  final double destinationLng;

  static const thresholdMeters = 150;

  const FinishRideButton({
    super.key,
    required this.busy,
    required this.onTap,
    required this.driverPhone,
    required this.destinationLat,
    required this.destinationLng,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: RideRepository().watchDriverLocation(driverPhone),
      builder: (context, snap) {
        final loc = (snap.data != null && snap.data!.isNotEmpty) ? snap.data!.first : null;
        final lat = (loc?['lat'] as num?)?.toDouble();
        final lng = (loc?['lng'] as num?)?.toDouble();
        final distanceM = (lat != null && lng != null) ? haversineKm(lat, lng, destinationLat, destinationLng) * 1000 : null;
        final arrived = distanceM != null && distanceM <= thresholdMeters;
        final distanceLabel = distanceM == null
            ? null
            : (distanceM < 1000 ? '${distanceM.round()} م' : '${(distanceM / 1000).toStringAsFixed(1)} كم');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: busy ? null : (arrived ? onTap : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: arrived ? AppColors.success : AppColors.textFaint,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      arrived ? '✓ وصلنا للوجهة — إنهاء الرحلة' : '📍 لسه ما وصلتش${distanceLabel != null ? ' ($distanceLabel متبقية)' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
            ),
            if (!arrived) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : () => _confirmManually(context),
                child: const Text('وصلت فعليًا؟ اضغط هنا للتأكيد يدويًا', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        );
      },
    );
  }

  void _confirmManually(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد الوصول يدويًا'),
        content: const Text('الموقع الحالي لسه بعيد عن نقطة النهاية حسب الـ GPS. متأكد إنك وصلت فعلاً وعايز تنهي الرحلة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('تراجع')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onTap();
            },
            child: const Text('تأكيد الإنهاء'),
          ),
        ],
      ),
    );
  }
}
