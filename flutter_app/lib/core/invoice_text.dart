import 'date_format_ar.dart';
import '../features/orders/orders_repository.dart' show statusAr;

/// Shared invoice text builders — used both for the WhatsApp share text
/// (shareTextViaWhatsApp) and as the body of the printed PDF (invoice_pdf.dart),
/// so both surfaces show the exact same content, always headed with the app
/// name/brand per the "يظهر اسم التطبيق وكل البيانات" requirement.
const String appInvoiceHeader = '🧾 فاتورة وصّلها\nتطبيق النقل والتوصيل — Wslha';

String buildRideInvoiceText(Map<String, dynamic> r) {
  final status = r['status'] as String? ?? 'pending';
  final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
  final rideType = (r['ride_type'] as String?) ?? 'local';
  final isAirport = rideType == 'airport';
  final fare = r['fare'] ?? 0;

  final lines = <String>[
    appInvoiceHeader,
    '',
    'النوع: ${isAirport ? '✈️ توصيل مطار' : '🚖 رحلة'}',
    'الحالة: ${statusAr[status] ?? status}',
    if (createdAt != null) 'التاريخ: ${arDateTime(createdAt)}',
    '',
    if ((r['customer_name'] as String?)?.isNotEmpty == true) 'العميل: ${r['customer_name']}',
    if ((r['customer_phone'] as String?)?.isNotEmpty == true) 'الهاتف: ${r['customer_phone']}',
    '',
    'من: ${r['from_area'] ?? '—'}',
    'إلى: ${r['to_area'] ?? '—'}',
    if ((r['driver_name'] as String?)?.isNotEmpty == true) 'السائق: ${r['driver_name']}',
  ];

  if (isAirport) {
    final flightTimeRaw = r['flight_time'];
    final flightTime = flightTimeRaw == null ? null : DateTime.tryParse(flightTimeRaw.toString());
    final direction = r['airport_direction'] as String? ?? 'departure';
    if (flightTime != null) {
      lines.add('${direction == 'departure' ? 'موعد الإقلاع' : 'موعد الهبوط'}: ${arDateTime(flightTime)}');
    }
  }

  lines.addAll([
    '',
    'طريقة الدفع: ${r['payment'] ?? 'كاش'}',
    'الإجمالي: $fare ج.م',
  ]);

  return lines.join('\n');
}

String buildOrderInvoiceText(Map<String, dynamic> o) {
  final status = o['status'] as String? ?? 'pending';
  final createdAt = DateTime.tryParse(o['created_at'] as String? ?? '');
  final total = (o['total'] as num?) ?? 0;
  final subtotal = (o['subtotal'] as num?) ?? total;
  final deliveryFee = (o['delivery_fee'] as num?) ?? (total - subtotal);

  final items = (o['items'] is List) ? (o['items'] as List).whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];

  final lines = <String>[
    appInvoiceHeader,
    '',
    'النوع: 📦 طلب من ${o['store_name'] ?? 'المتجر'}',
    'الحالة: ${statusAr[status] ?? status}',
    if (createdAt != null) 'التاريخ: ${arDateTime(createdAt)}',
    '',
    if ((o['customer_name'] as String?)?.isNotEmpty == true) 'العميل: ${o['customer_name']}',
    if ((o['customer_phone'] as String?)?.isNotEmpty == true) 'الهاتف: ${o['customer_phone']}',
    '${o['area'] ?? ''} — ${o['address'] ?? ''}',
    '',
  ];

  if (items.isNotEmpty) {
    lines.add('الأصناف:');
    for (final it in items) {
      final qty = it['qty'] ?? 1;
      final name = it['name'] ?? '';
      final price = it['price'];
      lines.add(price != null ? '  • $name × $qty — $price ج.م' : '  • $name × $qty');
    }
    lines.add('');
  } else if ((o['items_summary'] as String?)?.isNotEmpty == true) {
    lines.add('الأصناف: ${o['items_summary']}');
    lines.add('');
  }

  lines.addAll([
    'المجموع الفرعي: ${subtotal.toStringAsFixed(0)} ج.م',
    'رسوم التوصيل: ${deliveryFee.toStringAsFixed(0)} ج.م',
    'طريقة الدفع: ${o['payment'] ?? 'كاش'}',
    'الإجمالي: ${total.toStringAsFixed(0)} ج.م',
  ]);

  return lines.join('\n');
}
