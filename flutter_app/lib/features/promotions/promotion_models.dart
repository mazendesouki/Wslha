/// Mirrors public.app_promotions (db/security-98) — an admin-authored
/// in-app popup (offer/announcement), not a system push notification.
class AppPromotion {
  final String id;
  final String message;
  final String? emoji;
  final String? imageUrl;
  final int displaySeconds;

  const AppPromotion({
    required this.id,
    required this.message,
    this.emoji,
    this.imageUrl,
    required this.displaySeconds,
  });

  factory AppPromotion.fromRow(Map<String, dynamic> r) => AppPromotion(
        id: r['id'] as String,
        message: r['message'] as String? ?? '',
        emoji: r['emoji'] as String?,
        imageUrl: r['image_url'] as String?,
        displaySeconds: (r['display_seconds'] as num?)?.toInt() ?? 8,
      );
}
