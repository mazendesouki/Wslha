import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'ride_repository.dart';

// 0=Sunday..6=Saturday — matches Postgres extract(dow), used by both this
// screen and rides_screen.dart's day-picker chips.
const List<String> _dayShortLabelsAr = ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];

/// "رحلاتي المتكررة" — standing recurring-ride templates (db/security-108),
/// each generating an ordinary scheduled ride automatically on its chosen
/// days. Mirrors ScheduledRidesScreen's layout/flow.
class RecurringRideSchedulesScreen extends StatefulWidget {
  final String phone;
  const RecurringRideSchedulesScreen({super.key, required this.phone});

  @override
  State<RecurringRideSchedulesScreen> createState() => _RecurringRideSchedulesScreenState();
}

class _RecurringRideSchedulesScreenState extends State<RecurringRideSchedulesScreen> {
  final _repo = RideRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchMyRecurringSchedules(widget.phone);
  }

  void _refresh() => setState(() => _future = _repo.fetchMyRecurringSchedules(widget.phone));

  Future<void> _cancel(String scheduleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.tr('recurring_rides_cancel_confirm_title')),
        content: Text(context.tr('recurring_rides_cancel_confirm_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('scheduled_rides_cancel_back'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('scheduled_rides_cancel_confirm_action'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await _repo.cancelRecurringRideSchedule(scheduleId, widget.phone);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? context.tr('scheduled_rides_cancel_success') : context.tr('scheduled_rides_cancel_failed'))),
    );
    if (ok) _refresh();
  }

  String _daysLabel(List<dynamic> days) {
    final sorted = days.cast<num>().map((d) => d.toInt()).toList()..sort();
    return sorted.map((d) => _dayShortLabelsAr[d]).join('، ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('🔁 ${context.tr('recurring_rides_appbar_title')}')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final schedules = snapshot.data!;
              if (schedules.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text(context.tr('recurring_rides_empty'), style: const TextStyle(color: AppColors.textFaint))),
                  ],
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: schedules.length,
                itemBuilder: (context, i) {
                  final s = schedules[i];
                  final time = (s['time_of_day'] as String? ?? '').substring(0, 5);
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
                        Text('${s['from_area']} ← ${s['to_area']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 6),
                        Text(
                          '🔁 ${_daysLabel(s['days_of_week'] as List<dynamic>)} — ⏰ $time',
                          style: const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${s['fare']} ج.م', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
                            TextButton(
                              onPressed: () => _cancel(s['id'] as String),
                              child: Text(context.tr('scheduled_rides_cancel_button'), style: const TextStyle(color: AppColors.error)),
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
      ),
    );
  }
}
