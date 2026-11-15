import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// The one sanctioned way to build a "label: value" row anywhere in the
/// app (invoices, receipts, profile/account fields, checkout summaries).
///
/// Why this exists: 7 separate screens each hand-rolled their own local
/// `_row`/`_infoRow`/`_summaryRow` helper, and every one of them made the
/// same mistake — the value side was a bare, unconstrained `Text`, so a
/// long value (a Google plus-code address routinely runs 50+ chars) just
/// overflowed straight past the card/dialog edge instead of wrapping.
/// Comments alone don't stop an eighth copy of that mistake; this widget
/// does, because the value is always laid out inside Expanded with
/// textAlign.end — wrapping is the only thing it can do, by construction.
///
/// New label/value rows should use this directly instead of writing
/// another local helper. If a screen's existing local helper needs
/// tweaking, prefer having it delegate to this rather than reimplementing
/// the Row — see ride_tracking_screen.dart/_row, driver_home_screen.dart's
/// _ReceiptDialog._row, etc. for the delegation pattern.
class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final EdgeInsetsGeometry padding;
  final IconData? icon;
  final double gap;

  /// true: both label and value sit in Expanded (1:2 flex) — the aligned
  /// two-column look used by formal receipt/invoice dialogs. false
  /// (default): label keeps its natural width and only the value side is
  /// Expanded — the look used by simple info rows.
  final bool flexLabel;

  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
    this.padding = const EdgeInsets.symmetric(vertical: 3),
    this.icon,
    this.gap = 10,
    this.flexLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLabelStyle = labelStyle ??
        const TextStyle(fontSize: 12, color: AppColors.textFaint, fontWeight: FontWeight.w700);
    final effectiveValueStyle = valueStyle ?? const TextStyle(fontSize: 13, fontWeight: FontWeight.w900);

    final labelWidget = Text(label, style: effectiveLabelStyle);
    final valueWidget = Text(value, textAlign: TextAlign.end, style: effectiveValueStyle);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.textFaint),
            const SizedBox(width: 8),
          ],
          flexLabel ? Expanded(child: labelWidget) : labelWidget,
          SizedBox(width: gap),
          Expanded(flex: flexLabel ? 2 : 1, child: valueWidget),
        ],
      ),
    );
  }
}
