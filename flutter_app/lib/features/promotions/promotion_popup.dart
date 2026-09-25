import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import 'promotion_models.dart';
import 'promotion_repository.dart';

const _seenPromotionsKey = 'wslha_seen_promotions';

/// Called once per home-shell initState (customer/driver/merchant) — shows
/// the admin's current in-app popup (db/security-98) for this audience if
/// one is active and this device hasn't seen it before. A promotion is
/// remembered as "seen" the moment it's shown (auto-close or the X tap
/// both count), so it never repeats for the same install once dismissed.
Future<void> maybeShowPromotion(BuildContext context, String target) async {
  final promo = await PromotionRepository().fetchActive(target);
  if (promo == null) return;

  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getStringList(_seenPromotionsKey) ?? [];
  if (seen.contains(promo.id)) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PromotionDialog(promo: promo),
  );

  await prefs.setStringList(_seenPromotionsKey, [...seen, promo.id]);
}

class _PromotionDialog extends StatefulWidget {
  final AppPromotion promo;
  const _PromotionDialog({required this.promo});

  @override
  State<_PromotionDialog> createState() => _PromotionDialogState();
}

class _PromotionDialogState extends State<_PromotionDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(seconds: widget.promo.displaySeconds), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final promo = widget.promo;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (promo.imageUrl != null)
                  AspectRatio(
                    // Matches the admin tool's recommended banner size
                    // (1080×566) exactly.
                    aspectRatio: 1080 / 566,
                    child: Image.network(
                      promo.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    promo.emoji != null ? '${promo.emoji} ${promo.message}' : promo.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          // PositionedDirectional (not Positioned) so the ✕ lands at the
          // reading-start corner regardless of RTL/LTR locale.
          PositionedDirectional(
            top: -14,
            end: -14,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
