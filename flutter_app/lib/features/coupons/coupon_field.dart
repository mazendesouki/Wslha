import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import 'coupon_repository.dart';

/// A compact "عندك كود خصم؟" expander + apply button, reused by every
/// checkout screen (rides today, delivery/orders next). Only previews the
/// discount via validate_coupon — the actual redemption happens once the
/// caller's ride/order genuinely exists, via onApplied's code + amount.
class CouponField extends StatefulWidget {
  final String phone;
  final double amount;
  final String serviceType; // 'ride' | 'delivery'
  final void Function(String code, CouponCheck? check) onChanged; // check null = invalid
  const CouponField({super.key, required this.phone, required this.amount, required this.serviceType, required this.onChanged});

  @override
  State<CouponField> createState() => _CouponFieldState();
}

class _CouponFieldState extends State<CouponField> {
  final _repo = CouponRepository();
  final _ctrl = TextEditingController();
  bool _checking = false;
  CouponCheck? _result;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty || widget.amount <= 0) return;
    setState(() => _checking = true);
    try {
      final result = await _repo.validate(code: code, phone: widget.phone, amount: widget.amount, serviceType: widget.serviceType);
      if (!mounted) return;
      setState(() => _result = result);
      widget.onChanged(code, result.valid ? result : null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _result = CouponCheck(valid: false, discountAmount: 0, message: context.tr('coupon_field_check_failed')));
      widget.onChanged(code, null);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: context.tr('coupon_field_hint'),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _checking ? null : _check,
              child: _checking
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('coupon_field_apply')),
            ),
          ],
        ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _result!.valid
                  ? '✅ ${context.tr('coupon_field_success').replaceAll('AMOUNT', _result!.discountAmount.toStringAsFixed(0))}'
                  : '❌ ${_result!.message}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _result!.valid ? AppColors.primaryDark : AppColors.error),
            ),
          ),
      ],
    );
  }
}
