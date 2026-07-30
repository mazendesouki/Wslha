import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'ride_repository.dart';

/// Ordered ride statuses (rides.astro / driver-dashboard.astro write these
/// same values to rides.status), mirrored on the icon timeline below —
/// same visual language as the web's track.astro "HungerStation-style"
/// timeline (icon steps + progress bar + ETA card), just without the live
/// map/rating modules, which are a bigger Phase-2 scope.
const List<_Step> _steps = [
  _Step('pending', '📋', 'تم استلام الطلب'),
  _Step('accepted', '🚗', 'تم قبول الطلب'),
  _Step('arrived', '📍', 'السائق وصل'),
  _Step('in_progress', '🛣️', 'في الطريق'),
  _Step('completed', '✅', 'اكتملت الرحلة'),
];

class _Step {
  final String key;
  final String icon;
  final String label;
  const _Step(this.key, this.icon, this.label);
}

class RideTrackingScreen extends StatefulWidget {
  final String rideId;
  const RideTrackingScreen({super.key, required this.rideId});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  final _rideRepo = RideRepository();

  // Cached by driver phone so the lookup only fires once per assigned
  // driver, not on every Realtime tick of the ride row.
  String? _driverProfilePhone;
  Future<Map<String, dynamic>?>? _driverProfileFuture;

  int _stepIndex(String status) {
    final i = _steps.indexWhere((s) => s.key == status);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _rideRepo.watchRide(widget.rideId),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final ride = snapshot.data!.first;
          final status = ride['status'] as String? ?? 'pending';
          final isCancelled = status == 'cancelled';
          final driverName = ride['driver_name'] as String?;
          final driverPhone = ride['driver_phone'] as String?;
          final curIdx = _stepIndex(status);

          if (driverPhone != null && driverPhone.isNotEmpty && driverPhone != _driverProfilePhone) {
            _driverProfilePhone = driverPhone;
            _driverProfileFuture = _rideRepo.fetchDriverProfile(driverPhone);
          } else if (driverPhone == null || driverPhone.isEmpty) {
            _driverProfilePhone = null;
            _driverProfileFuture = null;
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: isCancelled ? AppColors.error : AppColors.primary,
                foregroundColor: Colors.white,
                title: const Text('تتبّع الرحلة'),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
                        ),
                        child: isCancelled
                            ? Column(
                                children: const [
                                  Text('❌', style: TextStyle(fontSize: 32)),
                                  SizedBox(height: 8),
                                  Text('الرحلة ملغاة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.error)),
                                ],
                              )
                            : _Timeline(curIdx: curIdx),
                      ),
                      const SizedBox(height: 16),
                      if (!isCancelled) _EtaCard(status: status),
                      if (!isCancelled && _driverProfileFuture != null) ...[
                        const SizedBox(height: 16),
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _driverProfileFuture,
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                              );
                            }
                            final profile = snap.data;
                            if (profile == null) return const SizedBox.shrink();
                            return _DriverCard(profile: profile, fallbackName: driverName);
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _infoRow('من', '${ride['from_area'] ?? '—'}'),
                            const Divider(height: 20),
                            _infoRow('إلى', '${ride['to_area'] ?? '—'}'),
                            const Divider(height: 20),
                            _infoRow('السائق', driverName?.isNotEmpty == true ? driverName! : 'جارٍ التعيين…'),
                            const Divider(height: 20),
                            _infoRow('الأجرة', '${ride['fare'] ?? 0} ج.م', highlight: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (status == 'pending')
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            await _rideRepo.cancelRide(widget.rideId);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          child: const Text('إلغاء الرحلة'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 16 : 13,
            fontWeight: FontWeight.w900,
            color: highlight ? AppColors.success : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final int curIdx;
  const _Timeline({required this.curIdx});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final segDone = (i ~/ 2) < curIdx;
          return Expanded(
            child: Container(height: 3, color: segDone ? AppColors.primary : const Color(0xFFE5E7EB)),
          );
        }
        final idx = i ~/ 2;
        final step = _steps[idx];
        final done = idx < curIdx;
        final active = idx == curIdx;
        final bg = done || active ? AppColors.primary : Colors.white;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
                border: Border.all(color: done || active ? AppColors.primary : const Color(0xFFE5E7EB), width: 2.5),
                boxShadow: active
                    ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 2)]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(step.icon, style: TextStyle(fontSize: 16, color: done || active ? Colors.white : null)),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 56,
              child: Text(
                step.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: done || active ? Colors.black87 : AppColors.textFaint,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  final String? fallbackName;
  const _DriverCard({required this.profile, required this.fallbackName});

  @override
  Widget build(BuildContext context) {
    final name = (profile['full_name'] as String?)?.trim();
    final photoUrl = profile['driver_photo_url'] as String?;
    final vehicleModel = profile['vehicle_model'] as String?;
    final vehicleColor = profile['vehicle_color'] as String?;
    final vehicleYear = profile['vehicle_year'];
    final regNumber = profile['vehicle_reg_number'] as String?;
    final carPhotoUrl = profile['vehicle_front_url'] as String?;

    final carLine = [vehicleColor, vehicleModel, if (vehicleYear != null) '$vehicleYear']
        .where((s) => s != null && s.isNotEmpty)
        .join(' — ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primaryLight,
                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                child: (photoUrl == null || photoUrl.isEmpty)
                    ? const Text('🧑‍✈️', style: TextStyle(fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (name != null && name.isNotEmpty) ? name : (fallbackName ?? 'السائق'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                    if (carLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(carLine, style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700)),
                    ],
                    if (regNumber != null && regNumber.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('🚘 $regNumber', style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (carPhotoUrl != null && carPhotoUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                carPhotoUrl,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EtaCard extends StatelessWidget {
  final String status;
  const _EtaCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, badge, badgeColor) = switch (status) {
      'completed' => ('وصل طلبك بنجاح', '🎉 مكتمل', AppColors.success),
      'in_progress' => ('السائق في الطريق إليك', '🛣️ في الطريق', AppColors.primary),
      'arrived' => ('السائق بانتظارك في نقطة الانطلاق', '📍 وصل', AppColors.primary),
      'accepted' => ('السائق في طريقه لاستلامك', '🚗 مقبولة', AppColors.primary),
      _ => ('بانتظار سائق يقبل الرحلة', '📋 جديدة', AppColors.textFaint),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('🕐', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
            child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: badgeColor)),
          ),
        ],
      ),
    );
  }
}
