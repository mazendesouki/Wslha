import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Outlined selectable pill — white/tinted with a border that turns green
/// and grows a checkmark when selected, instead of a solid filled
/// ChoiceChip. Shared across the airport and ride booking forms so every
/// single-choice picker in the app reads the same way.
class SelectablePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const SelectablePill({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryLight : Colors.white,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE9ECEB), width: selected ? 1.6 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 15, color: AppColors.primary),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? AppColors.primaryDark : Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }
}
