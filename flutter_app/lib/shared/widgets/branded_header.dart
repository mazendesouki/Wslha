import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Consistent branded header (design direction "ب", first applied to
/// rides_screen.dart) used across every customer-app screen in place of a
/// plain white AppBar — the real app logo (or a back arrow when this
/// screen was pushed and there's something to pop back to) plus the
/// screen's own service name, on the same teal gradient used everywhere
/// else in the app (header, fare summary, selected pills, CTA).
/// Reinforces the brand on every screen instead of only the one it
/// started on. Originally used a bare "و" text glyph as a stand-in mark,
/// but isolated Arabic waw renders as a small loop that read as the
/// digit "9" at this size — switched to the real logo.png (same asset
/// login_screen.dart/animated_splash.dart use) instead of trying to
/// tweak a text glyph into not looking like a number.
class BrandedHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const BrandedHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      ),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            )
          else
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))]),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/branding/logo.png', fit: BoxFit.cover),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
