import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'ratings_repository.dart';

/// Full ratings list — reached by tapping the compact avg/count card on a
/// profile screen instead of showing every individual review inline there.
/// Shared by both driver_profile_screen.dart ("تقييمات العملاء") and
/// account_screen.dart ("تقييمات السائقين عني") since the summary card and
/// review-tile layout are otherwise identical.
class RatingsListScreen extends StatelessWidget {
  final String title;
  final RatingSummary summary;
  final List<Map<String, dynamic>> reviews;
  final String countLabel;
  final String emptyMessage;

  const RatingsListScreen({
    super.key,
    required this.title,
    required this.summary,
    required this.reviews,
    required this.countLabel,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _summaryCard(),
          const SizedBox(height: 16),
          if (reviews.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(16)),
              child: Center(
                child: Text(emptyMessage, style: const TextStyle(color: AppColors.textFaint, fontSize: 12), textAlign: TextAlign.center),
              ),
            )
          else
            ...reviews.map(_reviewTile),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final s = summary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [
        BoxShadow(color: Color(0x11000000), blurRadius: 8, offset: Offset(0, 2)),
      ]),
      child: Row(
        children: [
          Text(
            s.isNew ? '🆕' : (s.avg >= 4.5 ? '😍' : s.avg >= 3.5 ? '🙂' : s.avg >= 2.5 ? '😐' : '🙁'),
            style: const TextStyle(fontSize: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.isNew ? 'لسه ما وصلش تقييم' : s.avg.toStringAsFixed(1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text(s.isNew ? emptyMessage : '${s.count} $countLabel', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              ],
            ),
          ),
          if (s.isTrusted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: const Text('✅ موثوق', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.success)),
            ),
        ],
      ),
    );
  }

  Widget _reviewTile(Map<String, dynamic> r) {
    final rating = ((r['rating'] as num?) ?? 0).toInt();
    final emoji = rating >= 1 && rating <= 5 ? ratingEmojis[rating - 1] : '⭐';
    final comment = r['comment'] as String?;
    final reply = r['driver_reply'] as String?;
    final tags = (r['tags'] as List?)?.cast<String>() ?? [];
    final serviceType = r['service_type'] as String?;
    final typeIcon = serviceType == 'order' ? '🛍️' : serviceType == 'airport' ? '✈️' : '🚗';
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(typeIcon, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              if (createdAt != null)
                Text('${createdAt.year}/${createdAt.month}/${createdAt.day}', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('"$comment"', style: const TextStyle(fontSize: 13)),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(999)),
                        child: Text(t, style: const TextStyle(fontSize: 10, color: AppColors.primaryDark)),
                      ))
                  .toList(),
            ),
          ],
          if (reply != null && reply.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
              child: Text('ردك: $reply', style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ),
          ],
        ],
      ),
    );
  }
}
