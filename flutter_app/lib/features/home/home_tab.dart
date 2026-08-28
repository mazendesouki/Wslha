import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import '../../shared/widgets/placeholder_screen.dart';
import '../airport/airport_screen.dart';
import '../rides/rides_screen.dart';
import '../stores/stores_list_screen.dart';

class HomeTab extends StatelessWidget {
  final UserSession session;
  const HomeTab({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    // Same 4 services, each given its own brand-family accent (teal/gold
    // shades only — no off-brand colors) instead of one repeated tint, so
    // the grid reads as distinct choices rather than four identical rows.
    final services = <_ServiceCard>[
      _ServiceCard('🚖', 'مشاوير', 'احجز مشوارك دلوقتي', AppColors.primary, (ctx) => const RidesScreen()),
      _ServiceCard('🛫', 'توصيل المطار', 'من دمياط إلى كل مطارات مصر', AppColors.accent, (ctx) => const AirportScreen()),
      _ServiceCard('📦', 'طرود ومستندات', 'مندوب مخصص لشحنتك', AppColors.primaryDark, (ctx) => const PlaceholderScreen(title: 'توصيل طرود', emoji: '📦')),
      _ServiceCard('🛍️', 'خدمة دليفري', 'اطلب من أي متجر قريب منك', AppColors.primary, (ctx) => const StoresListScreen()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('مرحباً، ${session.name.isNotEmpty ? session.name : 'بك'} 👋'),
        actions: const [LogoutButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'إيه محتاج تعمله النهاردة؟',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.92,
              children: services.map((s) => _ServiceCardTile(card: s)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard {
  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget Function(BuildContext) builder;
  _ServiceCard(this.emoji, this.title, this.subtitle, this.accent, this.builder);
}

class _ServiceCardTile extends StatelessWidget {
  final _ServiceCard card;
  const _ServiceCardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardTint,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: card.builder)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: card.accent.withValues(alpha: 0.16), width: 1.2),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: card.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(card.emoji, style: const TextStyle(fontSize: 24)),
              ),
              const Spacer(),
              Text(card.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const SizedBox(height: 3),
              Text(
                card.subtitle,
                style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
