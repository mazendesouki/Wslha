import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'ride_repository.dart';

/// "رحلاتي المجدولة" — every ride the customer booked for later (db/
/// security-76) that hasn't been activated yet (still status='scheduled',
/// so no driver has seen it). Lets them review or cancel before that
/// happens; once a pg_cron job flips it to 'pending' near the scheduled
/// time it disappears from here and behaves like any normal ride.
class ScheduledRidesScreen extends StatefulWidget {
  final String phone;
  const ScheduledRidesScreen({super.key, required this.phone});

  @override
  State<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends State<ScheduledRidesScreen> {
  final _repo = RideRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchScheduledRides(widget.phone);
  }

  void _refresh() => setState(() => _future = _repo.fetchScheduledRides(widget.phone));

  Future<void> _cancel(String rideId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء الرحلة المجدولة؟'),
        content: const Text('هيتم إلغاء الحجز نهائيًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('تراجع')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('إلغاء الرحلة')),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _repo.cancelScheduledRide(rideId, widget.phone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '✅ تم إلغاء الرحلة' : '❌ تعذّر الإلغاء')),
    );
    if (ok) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🗓️ رحلاتي المجدولة')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final rides = snapshot.data!;
            if (rides.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('مفيش رحلات مجدولة حاليًا', style: TextStyle(color: AppColors.textFaint))),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: rides.length,
              itemBuilder: (context, i) {
                final r = rides[i];
                final at = DateTime.tryParse(r['scheduled_at'] as String? ?? '')?.toLocal();
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r['from_area']} ← ${r['to_area']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 6),
                      if (at != null)
                        Text(
                          '🗓️ ${at.day}/${at.month}/${at.year} — ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${r['fare']} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
                          TextButton(
                            onPressed: () => _cancel(r['id'] as String),
                            child: const Text('إلغاء', style: TextStyle(color: AppColors.error)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
