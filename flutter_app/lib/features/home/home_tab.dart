import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../shared/widgets/logout_button.dart';
import '../../shared/widgets/placeholder_screen.dart';
import '../airport/airport_screen.dart';
import '../marketplace/marketplace_list_screen.dart';
import '../rides/rides_screen.dart';
import '../stores/stores_list_screen.dart';

class HomeTab extends StatelessWidget {
  final UserSession session;
  const HomeTab({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    // Rides and airport are the two services almost every customer opens
    // this screen for — given equal-size, filled primary tiles up top so
    // they're the first thing tapped, instead of competing on equal footing
    // with parcels/stores in one undifferentiated 2x2 grid.
    final primary = <_ServiceCard>[
      _ServiceCard('🚖', context.tr('home_service_rides_title'), context.tr('home_service_rides_subtitle'), AppColors.primary, (ctx) => const RidesScreen()),
      _ServiceCard('🛫', context.tr('home_service_airport_title'), context.tr('home_service_airport_subtitle'), AppColors.accent, (ctx) => const AirportScreen()),
    ];
    final secondary = <_ServiceCard>[
      _ServiceCard('📦', context.tr('home_service_parcels_title'), context.tr('home_service_parcels_subtitle'), AppColors.primaryDark, (ctx) => PlaceholderScreen(title: context.tr('home_service_parcels_title'), emoji: '📦')),
      _ServiceCard('🛍️', context.tr('home_service_delivery_title'), context.tr('home_service_delivery_subtitle'), AppColors.primary, (ctx) => const StoresListScreen()),
      _ServiceCard('🏷️', context.tr('home_service_marketplace_title'), context.tr('home_service_marketplace_subtitle'), AppColors.accent, (ctx) => const MarketplaceListScreen()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('${context.tr('home_greeting_prefix')} ${session.name.isNotEmpty ? session.name : context.tr('home_greeting_default_name')} 👋'),
        actions: const [LogoutButton()],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.tr('home_what_today'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final s in primary) ...[
                  Expanded(child: _PrimaryServiceTile(card: s)),
                  if (s != primary.last) const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 20),
            Text(
              context.tr('home_more_services'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textFaint),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final s in secondary) ...[
                  Expanded(child: _SecondaryServiceTile(card: s)),
                  if (s != secondary.last) const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 24),
            const _TrustBadgesStrip(),
          ],
        ),
      ),
    );
  }
}

/// Reassurance row under the service grid — same four claims the website's
/// own landing page leads with (amanah/safety, clear pricing, flexible pay,
/// 24/7 support), just condensed to icon+label for a phone-width strip.
class _TrustBadgesStrip extends StatelessWidget {
  const _TrustBadgesStrip();

  @override
  Widget build(BuildContext context) {
    final items = [
      ('🛡️', context.tr('home_trust_safety')),
      ('💰', context.tr('home_trust_pricing')),
      ('💳', context.tr('home_trust_payment')),
      ('🎧', context.tr('home_trust_support')),
    ];
    return Row(
      children: [
        for (final item in items) ...[
          Expanded(
            child: Column(
              children: [
                Text(item.$1, style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 4),
                Text(
                  item.$2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: AppColors.textFaint, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ],
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

/// The two "start here" choices — filled with the service's own accent
/// color (not just tinted) so they read as the primary call-to-action,
/// matching how the rest of the app already treats its main CTA buttons.
class _PrimaryServiceTile extends StatelessWidget {
  final _ServiceCard card;
  const _PrimaryServiceTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: card.accent,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: card.builder)),
        child: Container(
          height: 140,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(card.emoji, style: const TextStyle(fontSize: 22)),
              ),
              const Spacer(),
              Text(card.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
              const SizedBox(height: 3),
              Text(
                card.subtitle,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
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

/// Compact tinted-outline row for the less-central services (parcels,
/// store delivery) — same visual language the primary tiles used to share,
/// now scaled down since these aren't the first thing most customers want.
class _SecondaryServiceTile extends StatelessWidget {
  final _ServiceCard card;
  const _SecondaryServiceTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaceColor,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: card.builder)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: card.accent.withValues(alpha: 0.16), width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: card.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(card.emoji, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  card.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
