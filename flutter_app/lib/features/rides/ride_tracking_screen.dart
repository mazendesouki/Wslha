import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'ride_repository.dart';

const Map<String, String> _statusAr = {
  'pending': 'بانتظار سائق',
  'accepted': 'تم القبول',
  'arrived': 'السائق وصل',
  'in_progress': 'في الطريق',
  'completed': 'اكتملت',
  'cancelled': 'ملغاة',
};

class RideTrackingScreen extends StatefulWidget {
  final String rideId;
  const RideTrackingScreen({super.key, required this.rideId});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  final _rideRepo = RideRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تتبّع الرحلة')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _rideRepo.watchRide(widget.rideId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final ride = snapshot.data!.first;
          final status = ride['status'] as String? ?? 'pending';
          final driverName = ride['driver_name'] as String?;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _statusAr[status] ?? status,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.primary),
                      ),
                      const SizedBox(height: 8),
                      Text('${ride['from_area']} ← ${ride['to_area']}'),
                      const SizedBox(height: 4),
                      Text('${ride['fare']} ج.م', style: const TextStyle(fontWeight: FontWeight.w900)),
                      if (driverName != null && driverName.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('السائق: $driverName', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                if (status == 'pending')
                  OutlinedButton(
                    onPressed: () async {
                      await _rideRepo.cancelRide(widget.rideId);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('إلغاء الرحلة'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
