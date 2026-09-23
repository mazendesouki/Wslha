import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'driver_repository.dart';

/// Dismissible popup (X button) reminding the driver to settle an
/// outstanding cash balance an admin flagged from the panel
/// (db/security-92-driver-missed-requests-and-cash-reminders.sql).
/// "Dismiss" only closes THIS popup — the reminder stays active on the
/// backend (and will show again next app open) until an admin marks it
/// settled, since it represents real money actually owed, not a notice
/// that's done once read.
class CashReminderDialog extends StatelessWidget {
  final CashReminder reminder;
  const CashReminderDialog({super.key, required this.reminder});

  @override
  Widget build(BuildContext context) {
    final due = reminder.dueAt.toLocal();
    final dueLabel = '${due.day}/${due.month}/${due.year}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('cash_reminder_title'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(context.tr('cash_reminder_body_prefix'), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${reminder.amount.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.accent, fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(context.tr('cash_reminder_body_suffix'), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${context.tr('cash_reminder_due_prefix')} $dueLabel',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            if (reminder.note != null && reminder.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${context.tr('cash_reminder_note_label')} ${reminder.note}',
                style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('cash_reminder_dismiss')),
            ),
          ],
        ),
      ),
    );
  }
}
