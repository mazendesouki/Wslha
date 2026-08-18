import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'ratings_repository.dart';

/// Compact "⭐ 4.8 (23) — عميل موثوق" style chip, fed by any of
/// RatingsRepository's summary futures (driver/customer/store) — same
/// visual language everywhere it appears (offer card, driver card, store
/// header) so the trust signal reads consistently across all three apps.
class TrustBadge extends StatelessWidget {
  final Future<RatingSummary> future;
  final String trustedLabel;
  final String newLabel;

  const TrustBadge({super.key, required this.future, required this.trustedLabel, this.newLabel = '🆕 جديد — لا يوجد تقييم بعد'});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RatingSummary>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 20, width: 60, child: Center(child: SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 1.5))));
        }
        final s = snap.data!;
        if (s.isNew) {
          return _chip(newLabel, AppColors.textFaint, const Color(0xFFF3F4F6));
        }
        final emoji = s.avg >= 4.5 ? '😍' : s.avg >= 3.5 ? '🙂' : s.avg >= 2.5 ? '😐' : '🙁';
        final text = '$emoji ${s.avg.toStringAsFixed(1)} (${s.count})${s.isTrusted ? ' — $trustedLabel' : ''}';
        final color = s.isTrusted ? AppColors.success : AppColors.accent;
        return _chip(text, color, color.withValues(alpha: 0.1));
      },
    );
  }

  Widget _chip(String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}
