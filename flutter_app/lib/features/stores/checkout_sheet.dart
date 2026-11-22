import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/phone_utils.dart';
import '../../core/service_controls.dart';
import '../../core/session.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../../shared/widgets/key_value_row.dart';
import '../account/account_repository.dart';
import '../orders/order_invoice_screen.dart';
import '../orders/orders_repository.dart';
import 'cart_store.dart';

/// Submits straight into the `orders` table with the same shape
/// store/[id].astro's checkout sheet uses, so merchant-dashboard.astro's
/// live order feed (and the FCM new-order push) pick it up unchanged.
class CheckoutSheet extends StatefulWidget {
  const CheckoutSheet({super.key});

  @override
  State<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<CheckoutSheet> {
  final _cart = CartStore.instance;
  final _accountRepo = AccountRepository();
  final _ordersRepo = OrdersRepository();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _payment = 'كاش';
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _savedAddresses = [];

  @override
  void initState() {
    super.initState();
    SessionStore.load().then((s) async {
      if (s == null || !mounted) return;
      _nameCtrl.text = s.name;
      _phoneCtrl.text = s.phone;
      setState(() {});
      // Saved addresses — see db/security-31-customer-account-plus.sql. A
      // hiccup here shouldn't block checkout, just skip the prefill/picker.
      final addresses = await _accountRepo.fetchSavedAddresses(s.phone).catchError((_) => <Map<String, dynamic>>[]);
      if (!mounted) return;
      final matches = addresses.where((a) => a['is_default'] == true).toList();
      final defaultAddr = matches.isNotEmpty ? matches.first : (addresses.isNotEmpty ? addresses.first : null);
      setState(() {
        _savedAddresses = addresses;
        if (defaultAddr != null) {
          _areaCtrl.text = (defaultAddr['area'] as String?) ?? '';
          _addressCtrl.text = (defaultAddr['address'] as String?) ?? '';
        }
      });
    });
  }

  Future<void> _pickSavedAddress() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(context.tr('checkout_saved_addresses_title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            ..._savedAddresses.map((a) => ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                  title: Text(a['label'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([a['area'], a['address']].where((e) => e != null && (e as String).isNotEmpty).join(' — ')),
                  onTap: () => Navigator.of(sheetContext).pop(a),
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _areaCtrl.text = (picked['area'] as String?) ?? '';
      _addressCtrl.text = (picked['address'] as String?) ?? '';
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _areaCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final area = _areaCtrl.text.trim();
    final address = _addressCtrl.text.trim();

    if (name.length < 2) {
      setState(() => _error = context.tr('checkout_error_name'));
      return;
    }
    if (!isEgyptianMobile(phone)) {
      setState(() => _error = egPhoneError);
      return;
    }
    if (address.length < 5) {
      setState(() => _error = context.tr('checkout_error_address'));
      return;
    }
    if (_cart.subtotal < _cart.minOrder) {
      setState(() => _error = '${context.tr('checkout_error_min_order')} ${_cart.minOrder.toStringAsFixed(0)} ج.م.');
      return;
    }
    if (!await ServiceControls.isActive('delivery_orders')) {
      setState(() => _error = context.tr('checkout_service_unavailable'));
      return;
    }

    // Same duplicate-request guard as rides_screen.dart's _submit() — this
    // insert has no idempotency key beyond its own id either, so a
    // connectivity drop that makes an actually-successful order look like
    // it failed could otherwise lead to a genuine duplicate on resubmit.
    final existingOrder = await _ordersRepo.findActiveOrder(normalizeEgyptianPhone(phone));
    if (existingOrder != null) {
      if (!mounted) return;
      final proceedAnyway = await _confirmProceedDespiteActiveOrder(existingOrder);
      if (!proceedAnyway) return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final code = 'WSL-${DateTime.now().year}-${100000 + Random().nextInt(900000)}';
      final normPhone = normalizeEgyptianPhone(phone);
      final itemsSummary = _cart.lines.map((l) => '${l.qty}× ${l.product.name}').join('، ');

      // Deliberately NOT wrapped in withConnectivityRetry: 'orders' has no
      // unique constraint beyond its server-generated id (confirmed live —
      // only orders_pkey on id), so if the insert actually reached and
      // committed on the server but the success response itself was lost
      // to the same connection drop, a blind retry here would silently
      // create a second, real duplicate order — unlike the idempotent
      // upsert_driver_location / status-gated merchant_accept_order calls
      // this mechanism is otherwise used for. A manual resubmit (the
      // existing behavior) at least keeps the retry decision visible to
      // the customer instead of risking an invisible double order.
      await sb.from('orders').insert({
        'code': code,
        'store_id': _cart.storeId,
        'store_name': _cart.storeName,
        'store_lat': _cart.storeLat,
        'store_lng': _cart.storeLng,
        'customer_name': name,
        'customer_phone': normPhone,
        'area': area,
        'address': address,
        'items': _cart.lines.map((l) => {
              'id': l.product.id,
              'qty': l.qty,
              'name': l.product.name,
              'emoji': l.product.emoji,
              'price': l.product.price,
            }).toList(),
        'items_summary': itemsSummary,
        'subtotal': _cart.subtotal,
        'delivery_fee': _cart.deliveryFee,
        'total': _cart.total,
        'payment': _payment,
        'status': 'pending',
      });

      _cart.clear();
      if (!mounted) return;
      _showSuccess(code);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('checkout_error_submit');
        _submitting = false;
      });
    }
  }

  /// Same dialog as rides_screen.dart's _confirmProceedDespiteActiveRide —
  /// see its doc comment for why. Any outcome other than the explicit
  /// "create a new one anyway" tap is treated as "go look at the existing
  /// order" rather than silent permission to create a second one.
  Future<bool> _confirmProceedDespiteActiveOrder(Map<String, dynamic> existingOrder) async {
    final createNew = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('checkout_active_order_found_title')),
        content: Text(context.tr('checkout_active_order_found_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('checkout_active_order_view_button')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('checkout_active_order_new_button'), style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (createNew == true) return true;
    final existingId = existingOrder['id']?.toString();
    if (mounted && existingId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderInvoiceScreen(orderId: existingId)),
      );
    }
    return false;
  }

  void _showSuccess(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('checkout_success_title')),
        content: Text('${context.tr('checkout_success_order_number_label')}: $code\n${context.tr('checkout_success_update_note')}'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).popUntil((r) => r.isFirst);
            },
            child: Text(context.tr('checkout_ok_button')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.mutedSurface,
      appBar: AppBar(title: Text(context.tr('checkout_appbar_title'))),
      body: SafeArea(
        top: false,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: context.surfaceColor, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                ..._cart.lines.map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text('${l.qty}×', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary)),
                          const SizedBox(width: 6),
                          Expanded(child: Text('${l.product.emoji} ${l.product.name}', style: const TextStyle(fontSize: 13))),
                          Text('${l.qty * l.product.price} ج.م', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                    )),
                const Divider(height: 20),
                _summaryRow(context.tr('checkout_subtotal_label'), '${_cart.subtotal.toStringAsFixed(0)} ج.م'),
                _summaryRow(context.tr('checkout_delivery_fee_label'), '${_cart.deliveryFee.toStringAsFixed(0)} ج.م'),
                const SizedBox(height: 4),
                _summaryRow(context.tr('checkout_total_label'), '${_cart.total.toStringAsFixed(0)} ج.م', bold: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: context.tr('checkout_name_label'))),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: context.tr('checkout_phone_label'))),
          const SizedBox(height: 10),
          if (_savedAddresses.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _pickSavedAddress,
                icon: const Icon(Icons.location_on_outlined, size: 18),
                label: Text(context.tr('checkout_pick_saved_address')),
              ),
            ),
          ],
          TextField(controller: _areaCtrl, decoration: InputDecoration(labelText: context.tr('checkout_area_label'))),
          const SizedBox(height: 10),
          TextField(controller: _addressCtrl, maxLines: 2, decoration: InputDecoration(labelText: context.tr('checkout_address_label'))),
          const SizedBox(height: 14),
          Text(context.tr('checkout_payment_method_label'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            // Internal values kept as-is (not translated): they're persisted
            // verbatim into orders.payment, same shape the web checkout uses.
            children: ['كاش', 'تحويل بنكي', 'محفظة'].map((p) {
              final selected = _payment == p;
              return ChoiceChip(
                label: Text(_paymentLabel(context, p), style: TextStyle(color: selected ? Colors.white : AppColors.textFaint, fontWeight: FontWeight.w800, fontSize: 12)),
                selected: selected,
                selectedColor: AppColors.primary,
                backgroundColor: context.surfaceColor,
                onSelected: (_) => setState(() => _payment = p),
              );
            }).toList(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 12), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('${context.tr('checkout_confirm_order_button')} — ${_cart.total.toStringAsFixed(0)} ج.م'),
          ),
        ],
      ),
      ),
    );
  }

  String _paymentLabel(BuildContext context, String code) {
    switch (code) {
      case 'كاش':
        return context.tr('checkout_payment_cash');
      case 'تحويل بنكي':
        return context.tr('checkout_payment_bank_transfer');
      case 'محفظة':
        return context.tr('checkout_payment_wallet');
      default:
        return code;
    }
  }

  // Delegates to KeyValueRow (shared/widgets/key_value_row.dart) — see
  // that widget's doc comment for why.
  Widget _summaryRow(String label, String value, {bool bold = false}) => KeyValueRow(
        label: label,
        value: value,
        padding: const EdgeInsets.symmetric(vertical: 2),
        labelStyle: TextStyle(fontSize: bold ? 14 : 12, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: bold ? context.bodyText : AppColors.textFaint),
        valueStyle: TextStyle(fontSize: bold ? 14 : 12, fontWeight: FontWeight.w800, color: bold ? AppColors.primary : context.bodyText),
      );
}
