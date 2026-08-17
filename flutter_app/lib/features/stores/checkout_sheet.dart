import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/phone_utils.dart';
import '../../core/session.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
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
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _payment = 'كاش';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SessionStore.load().then((s) {
      if (s == null || !mounted) return;
      _nameCtrl.text = s.name;
      _phoneCtrl.text = s.phone;
      setState(() {});
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
      setState(() => _error = 'يرجى إدخال اسم المستلم.');
      return;
    }
    if (!isEgyptianMobile(phone)) {
      setState(() => _error = egPhoneError);
      return;
    }
    if (address.length < 5) {
      setState(() => _error = 'يرجى إدخال العنوان بالتفصيل.');
      return;
    }
    if (_cart.subtotal < _cart.minOrder) {
      setState(() => _error = 'الحد الأدنى للطلب ${_cart.minOrder.toStringAsFixed(0)} ج.م.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final code = 'WSL-${DateTime.now().year}-${100000 + Random().nextInt(900000)}';
      final normPhone = normalizeEgyptianPhone(phone);
      final itemsSummary = _cart.lines.map((l) => '${l.qty}× ${l.product.name}').join('، ');

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
        _error = 'حصل خطأ في إرسال الطلب — حاول تاني.';
        _submitting = false;
      });
    }
  }

  void _showSuccess(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('✅ تم إرسال طلبك'),
        content: Text('رقم الطلب: $code\nهيوصلك تحديث لحظة ما المتجر يقبل طلبك.'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('تمام'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('إتمام الطلب')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
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
                _summaryRow('المجموع الفرعي', '${_cart.subtotal.toStringAsFixed(0)} ج.م'),
                _summaryRow('رسوم التوصيل', '${_cart.deliveryFee.toStringAsFixed(0)} ج.م'),
                const SizedBox(height: 4),
                _summaryRow('الإجمالي', '${_cart.total.toStringAsFixed(0)} ج.م', bold: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'اسم المستلم')),
          const SizedBox(height: 10),
          TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الجوال')),
          const SizedBox(height: 10),
          TextField(controller: _areaCtrl, decoration: const InputDecoration(labelText: 'المنطقة')),
          const SizedBox(height: 10),
          TextField(controller: _addressCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'العنوان بالتفصيل')),
          const SizedBox(height: 14),
          const Text('طريقة الدفع', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['كاش', 'تحويل بنكي', 'محفظة'].map((p) {
              final selected = _payment == p;
              return ChoiceChip(
                label: Text(p, style: TextStyle(color: selected ? Colors.white : AppColors.textFaint, fontWeight: FontWeight.w800, fontSize: 12)),
                selected: selected,
                selectedColor: AppColors.primary,
                backgroundColor: Colors.white,
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
                : Text('تأكيد الطلب — ${_cart.total.toStringAsFixed(0)} ج.م'),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: bold ? 14 : 12, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: bold ? Colors.black : AppColors.textFaint)),
            Text(value, style: TextStyle(fontSize: bold ? 14 : 12, fontWeight: FontWeight.w800, color: bold ? AppColors.primary : Colors.black87)),
          ],
        ),
      );
}
