import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import '../../shared/widgets/placeholder_screen.dart';
import '../rides/rides_screen.dart';

class HomeTab extends StatelessWidget {
  final UserSession session;
  const HomeTab({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final services = <_ServiceCard>[
      _ServiceCard('🚖', 'مشاوير', 'احجز مشوارك دلوقتي', (ctx) => const RidesScreen()),
      _ServiceCard('📦', 'طرود ومستندات', 'مندوب مخصص لشحنتك', (ctx) => const PlaceholderScreen(title: 'توصيل طرود', emoji: '📦')),
      _ServiceCard('🛍️', 'خدمة دليفري', 'اشترِ من أي مكان', (ctx) => const PlaceholderScreen(title: 'خدمة دليفري', emoji: '🛍️')),
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
            const SizedBox(height: 12),
            ...services.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ServiceCardTile(card: s),
                )),
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
  final Widget Function(BuildContext) builder;
  _ServiceCard(this.emoji, this.title, this.subtitle, this.builder);
}

class _ServiceCardTile extends StatelessWidget {
  final _ServiceCard card;
  const _ServiceCardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: card.builder)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(card.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(card.subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
