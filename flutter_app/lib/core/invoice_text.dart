import 'date_format_ar.dart';
import 'invoice_data.dart';
import '../features/orders/orders_repository.dart' show statusAr;

// ARGB ints matching AppColors (core/theme.dart) — kept as plain ints here
// (not importing Flutter's Color) so this file stays usable from the
// PDF builder without pulling in package:flutter.
const int _colorPrimary = 0xFF0E4B49;
const int _colorSuccess = 0xFF16A34A;
const int _colorError = 0xFFDC2626;
const int _colorFaint = 0xFF9CA3AF;

const Map<String, int> _statusColor = {
  'delivered': _colorSuccess,
  'completed': _colorSuccess,
  'rejected': _colorError,
  'cancelled': _colorError,
  'pending': _colorFaint,
  'preparing': _colorPrimary,
  'on_the_way': _colorPrimary,
  'accepted': _colorPrimary,
  'arrived': _colorPrimary,
  'in_progress': _colorPrimary,
};

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

String _shortId(dynamic id) {
  final s = '$id';
  return s.length > 8 ? s.substring(s.length - 8) : s;
}

/// Structured version of buildRideInvoiceText — feeds the colorful PDF
/// layout (invoice_pdf.dart) instead of a flat string.
InvoiceData buildRideInvoiceData(Map<String, dynamic> r) {
  final status = r['status'] as String? ?? 'pending';
  final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
  final rideType = (r['ride_type'] as String?) ?? 'local';
  final isAirport = rideType == 'airport';
  final fare = (r['fare'] as num?) ?? 0;

  final details = <InvoiceRow>[
    InvoiceRow('من', '${r['from_area'] ?? '—'}'),
    InvoiceRow('إلى', '${r['to_area'] ?? '—'}'),
    if ((r['driver_name'] as String?)?.isNotEmpty == true) InvoiceRow('السائق', '${r['driver_name']}'),
  ];

  if (isAirport) {
    final flightTimeRaw = r['flight_time'];
    final flightTime = flightTimeRaw == null ? null : DateTime.tryParse(flightTimeRaw.toString());
    final direction = r['airport_direction'] as String? ?? 'departure';
    if (flightTime != null) {
      details.add(InvoiceRow(direction == 'departure' ? 'موعد الإقلاع' : 'موعد الهبوط', arDateTime(flightTime)));
    }
  }

  return InvoiceData(
    kind: isAirport ? 'airport' : 'ride',
    title: isAirport ? 'فاتورة توصيل مطار' : 'فاتورة رحلة',
    invoiceNumber: _shortId(r['id']),
    statusLabel: statusAr[status] ?? status,
    statusColor: _statusColor[status] ?? _colorFaint,
    dateLabel: createdAt != null ? arDateTime(createdAt) : null,
    customerName: r['customer_name'] as String?,
    customerPhone: r['customer_phone'] as String?,
    details: details,
    totals: [InvoiceRow('طريقة الدفع', '${r['payment'] ?? 'كاش'}')],
    total: fare,
  );
}

/// Structured version of buildOrderInvoiceText — feeds the colorful PDF
/// layout (invoice_pdf.dart) instead of a flat string.
InvoiceData buildOrderInvoiceData(Map<String, dynamic> o) {
  final status = o['status'] as String? ?? 'pending';
  final createdAt = DateTime.tryParse(o['created_at'] as String? ?? '');
  final total = (o['total'] as num?) ?? 0;
  final subtotal = (o['subtotal'] as num?) ?? total;
  final deliveryFee = (o['delivery_fee'] as num?) ?? (total - subtotal);

  final rawItems = (o['items'] is List) ? (o['items'] as List).whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
  final items = rawItems
      .map((it) => InvoiceLineItem(name: '${it['name'] ?? ''}', qty: (it['qty'] as num?) ?? 1, price: it['price'] as num?))
      .toList();

  return InvoiceData(
    kind: 'order',
    title: 'فاتورة طلب من ${o['store_name'] ?? 'المتجر'}',
    invoiceNumber: _shortId(o['code'] ?? o['id']),
    statusLabel: statusAr[status] ?? status,
    statusColor: _statusColor[status] ?? _colorFaint,
    dateLabel: createdAt != null ? arDateTime(createdAt) : null,
    customerName: o['customer_name'] as String?,
    customerPhone: o['customer_phone'] as String?,
    details: [
      InvoiceRow('العنوان', '${o['area'] ?? ''} — ${o['address'] ?? ''}'),
      if ((o['items_summary'] as String?)?.isNotEmpty == true && items.isEmpty)
        InvoiceRow('الأصناف', '${o['items_summary']}'),
    ],
    items: items,
    totals: [
      InvoiceRow('المجموع الفرعي', '${subtotal.toStringAsFixed(0)} ج.م'),
      InvoiceRow('رسوم التوصيل', '${deliveryFee.toStringAsFixed(0)} ج.م'),
      InvoiceRow('طريقة الدفع', '${o['payment'] ?? 'كاش'}'),
    ],
    total: total,
  );
}
