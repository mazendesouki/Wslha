import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Selectable pill — a filled teal gradient with a checkmark when selected,
/// a plain outline otherwise. Shared across the airport and ride booking
/// forms so every single-choice picker in the app reads the same way; the
/// gradient fill matches the branded header/CTA treatment introduced on
/// rides_screen.dart (design direction "ب") instead of the flatter
/// tinted-outline look it had before.
class SelectablePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  // Greyed-out + untappable, e.g. for an option that isn't functional yet
  // (see rides_screen.dart's "المحفظة" pill — the wallet payment flow has
  // no real backend deduction wired up, so it's disabled rather than
  // offering a choice that silently does nothing).
  final bool enabled;
  const SelectablePill({super.key, required this.label, required this.selected, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: selected ? const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]) : null,
              color: selected ? null : context.surfaceColor,
              border: selected ? null : Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check, size: 15, color: Colors.white),
                  const SizedBox(width: 5),
                ],
                Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : context.bodyText)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
