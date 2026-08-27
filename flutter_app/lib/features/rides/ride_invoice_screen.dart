import 'package:flutter/material.dart';
import '../../core/contact_launcher.dart';
import '../../core/date_format_ar.dart';
import '../../core/invoice_pdf.dart';
import '../../core/invoice_text.dart';
import '../../core/supabase_client.dart';
import '../../core/theme.dart';
import '../orders/orders_repository.dart' show statusAr;

/// Full invoice view for a single `rides` row (local/external/airport
/// alike) — the ride-side counterpart of OrderInvoiceScreen, opened from
/// the "فواتير" list (InvoicesScreen) since rides never had a dedicated
/// invoice screen before, only the live-tracking one.
class RideInvoiceScreen extends StatefulWidget {
  final String rideId;
  const RideInvoiceScreen({super.key, required this.rideId});

  @override
  State<RideInvoiceScreen> createState() => _RideInvoiceScreenState();
}

class _RideInvoiceScreenState extends State<RideInvoiceScreen> {
  Map<String, dynamic>? _ride;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await sb.from('rides').select().eq('id', widget.rideId).single();
      if (!mounted) return;
      setState(() {
        _ride = row;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF9),
      appBar: AppBar(title: const Text('فاتورة الرحلة')),
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
              : _buildInvoice(_ride!),
    );
  }

  Widget _buildInvoice(Map<String, dynamic> r) {
    final status = r['status'] as String? ?? 'pending';
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    final rideType = (r['ride_type'] as String?) ?? 'local';
    final isAirport = rideType == 'airport';
    final fare = r['fare'] ?? 0;
    final flightTimeRaw = r['flight_time'];
    final flightTime = flightTimeRaw == null ? null : DateTime.tryParse(flightTimeRaw.toString());
    final direction = r['airport_direction'] as String? ?? 'departure';

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
                  isAirport ? '✈️ توصيل مطار' : '🚖 رحلة',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
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
          const SizedBox(height: 16),
          _sectionTitle('📍 الرحلة'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('من', '${r['from_area'] ?? '—'}'),
                const Divider(height: 20),
                _row('إلى', '${r['to_area'] ?? '—'}'),
                if ((r['driver_name'] as String?)?.isNotEmpty == true) ...[
                  const Divider(height: 20),
                  _row('السائق', '${r['driver_name']}'),
                ],
                if (isAirport && flightTime != null) ...[
                  const Divider(height: 20),
                  _row(direction == 'departure' ? 'موعد الإقلاع' : 'موعد الهبوط', arDateTime(flightTime)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('💰 تفاصيل الفاتورة'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                _row('طريقة الدفع', (r['payment'] as String?) ?? 'كاش'),
                const Divider(height: 20),
                _row('الإجمالي', '$fare ج.م', bold: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('👤 العميل'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((r['customer_name'] as String?)?.isNotEmpty == true) ...[
                  Text('${r['customer_name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 4),
                ],
                if ((r['customer_phone'] as String?)?.isNotEmpty == true)
                  Text('${r['customer_phone']}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => shareTextViaWhatsApp(buildRideInvoiceText(r)),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF25D366)),
                  label: const Text('نص واتساب'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => printInvoice(buildRideInvoiceData(r)),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('طباعة'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => downloadInvoicePdf(buildRideInvoiceData(r)),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('تحميل PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => shareInvoicePdfViaWhatsApp(buildRideInvoiceData(r)),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Color(0xFF25D366)),
                  label: const Text('PDF واتساب'),
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

  Widget _row(String label, String value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: bold ? 14 : 12, color: bold ? Colors.black : AppColors.textFaint, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: bold ? 14 : 12, color: bold ? AppColors.primary : Colors.black87, fontWeight: FontWeight.w800)),
        ],
      );
}
