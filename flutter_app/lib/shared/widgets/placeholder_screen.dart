import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Explicit "coming soon" screen for the features not built in this pass
/// (courier, delivery, orders history, profile, settings, merchant/driver
/// dashboards) — deliberately shown instead of a broken/dead link, per the
/// plan's phased scope.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String emoji;

  const PlaceholderScreen({super.key, required this.title, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'قريباً في المرحلة القادمة',
              style: TextStyle(color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
