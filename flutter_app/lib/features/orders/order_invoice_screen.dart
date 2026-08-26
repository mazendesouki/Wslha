import 'package:flutter/material.dart';
import '../../core/contact_launcher.dart';
import '../../core/date_format_ar.dart';
import '../../core/invoice_pdf.dart';
import '../../core/invoice_text.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../ratings/order_rating_sheet.dart';
import '../ratings/ratings_repository.dart';
import 'orders_repository.dart';

/// Full invoice view for a single `orders` row — opened by tapping a
/// delivery item in either the customer's or the driver's history list
/// (mirrors merchant-dashboard.astro's renderItems()/order card, which is
/// the only other place `items`/`items_summary` get rendered today).
class OrderInvoiceScreen extends StatefulWidget {
  final String orderId;
  final bool isDriverView;
  const OrderInvoiceScreen({super.key, required this.orderId, this.isDriverView = false});

  @override
  State<OrderInvoiceScreen> createState() => _OrderInvoiceScreenState();
}

class _OrderInvoiceScreenState extends State<OrderInvoiceScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;
  final _ratingsRepo = RatingsRepository();
  bool _ratingPrompted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _maybePromptRating(Map<String, dynamic> o) async {
    if (widget.isDriverView || _ratingPrompted) return;
    final code = o['code'] as String?;
    if (code == null || code.isEmpty) return;
    _ratingPrompted = true;
    final already = await _ratingsRepo.hasRatedOrder(code);
    if (already || !mounted) return;
    final storeName = (o['store_name'] as String?) ?? 'المتجر';
    final driverPhone = o['driver_phone'] as String?;
    final result = await OrderRatingSheet.show(context, storeName: storeName, hasDriver: driverPhone != null && driverPhone.isNotEmpty);
    if (result == null || !mounted) return;
    await _ratingsRepo.rateOrder(
      orderCode: code,
      storeId: o['store_id'] as String? ?? '',
      driverPhone: driverPhone,
      storeRating: result.storeRating,
      driverRating: result.driverRating,
      tags: result.tags,
      comment: result.comment,
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ شكرًا على تقييمك')));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await sb.from('orders').select().eq('id', widget.orderId).single();
      if (!mounted) return;
      setState(() {
        _order = row;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _items {
    final raw = _order?['items'];
    if (raw is List) return raw.whereType<Map<String, dynamic>>().toList();
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('فاتورة الطلب')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(fontSize: 11, color: AppColors.error), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  ),
                )
              : _buildInvoice(_order!),
    );
  }

  Widget _buildInvoice(Map<String, dynamic> o) {
    final status = o['status'] as String? ?? 'pending';
    if (status == 'delivered') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptRating(o));
    }
    final total = (o['total'] as num?) ?? 0;
    final subtotal = (o['subtotal'] as num?) ?? total;
    final deliveryFee = (o['delivery_fee'] as num?) ?? (total - subtotal);
    final createdAt = DateTime.tryParse(o['created_at'] as String? ?? '');

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF0E4D3D)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🧾 وصّلها', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Text(
                  '📦 طلب من ${o['store_name'] ?? 'المتجر'}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  '#${_orderCode(o)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(statusAr[status] ?? status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                    if (createdAt != null)
                      Text(arDateTime(createdAt), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          if (_showOtp(o)) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    '🔑 كود التسليم — اديه للمندوب لما يوصلّك الطلب',
                    style: TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${o['delivery_otp']}',
                    style: const TextStyle(fontSize: 26, color: Color(0xFF15803D), fontWeight: FontWeight.w900, letterSpacing: 4),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_items.isNotEmpty) ...[
            _sectionTitle('🧾 الأصناف'),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: _items.map((it) {
                  final qty = it['qty'] ?? 1;
                  final name = it['name'] ?? '';
                  final emoji = it['emoji'] ?? '';
                  final price = it['price'];
                  return ListTile(
                    dense: true,
                    leading: Text('$emoji', style: const TextStyle(fontSize: 20)),
                    title: Text('$name', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    trailing: Text(
                      price != null ? '$qty× ${price} ج.م' : '$qty×',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textFaint),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ] else if ((o['items_summary'] as String?)?.isNotEmpty == true) ...[
            _sectionTitle('🧾 الأصناف'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Text(o['items_summary'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 16),
          ],
          _sectionTitle('💰 تفاصيل الفاتورة'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                _row('المجموع الفرعي', '${subtotal.toStringAsFixed(0)} ج.م'),
                _row('رسوم التوصيل', '${deliveryFee.toStringAsFixed(0)} ج.م'),
                const Divider(height: 20),
                _row('الإجمالي', '${total.toStringAsFixed(0)} ج.م', bold: true),
                const SizedBox(height: 6),
                _row('طريقة الدفع', (o['payment'] as String?) ?? 'كاش'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('📍 التوصيل'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((o['customer_name'] as String?)?.isNotEmpty == true) ...[
                  Text('العميل: ${o['customer_name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 4),
                ],
                if ((o['customer_phone'] as String?)?.isNotEmpty == true) ...[
                  Text('الهاتف: ${o['customer_phone']}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                  const SizedBox(height: 4),
                ],
                Text(
                  '${o['area'] ?? ''} — ${o['address'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => shareTextViaWhatsApp(buildOrderInvoiceText(o)),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF25D366)),
                  label: const Text('واتساب'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => printInvoice(buildOrderInvoiceData(o)),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('طباعة'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
      );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: bold ? 14 : 12, color: bold ? Colors.black : AppColors.textFaint, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
            Text(value, style: TextStyle(fontSize: bold ? 14 : 12, color: bold ? AppColors.primary : Colors.black87, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  bool _showOtp(Map<String, dynamic> o) {
    final otp = o['delivery_otp'];
    final status = o['status'] as String? ?? '';
    return otp != null && '$otp'.isNotEmpty && status != 'delivered' && status != 'rejected' && status != 'cancelled';
  }

  String _orderCode(Map<String, dynamic> o) {
    final code = o['code'] as String?;
    if (code != null && code.isNotEmpty) return code;
    final id = widget.orderId;
    return id.length > 8 ? id.substring(id.length - 8) : id;
  }
}
