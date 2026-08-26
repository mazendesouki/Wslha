/// Structured invoice content — feeds the colorful/professional PDF layout
/// (invoice_pdf.dart). Kept separate from the plain-text builders in
/// invoice_text.dart (used for the WhatsApp share, which can't render
/// colors/tables anyway) so each output format gets the shape it actually
/// needs instead of one format compromising for the other.
class InvoiceLineItem {
  final String name;
  final num qty;
  final num? price;
  const InvoiceLineItem({required this.name, required this.qty, this.price});
}

class InvoiceRow {
  final String label;
  final String value;
  const InvoiceRow(this.label, this.value);
}

class InvoiceData {
  final String kind; // order | ride | airport
  final String title;
  final String invoiceNumber;
  final String statusLabel;
  final int statusColor; // ARGB int, matches Flutter Color.value / PdfColor.fromInt
  final String? dateLabel;
  final String? customerName;
  final String? customerPhone;
  final List<InvoiceRow> details;
  final List<InvoiceLineItem> items;
  final List<InvoiceRow> totals;
  final num total;

  const InvoiceData({
    required this.kind,
    required this.title,
    required this.invoiceNumber,
    required this.statusLabel,
    required this.statusColor,
    this.dateLabel,
    this.customerName,
    this.customerPhone,
    this.details = const [],
    this.items = const [],
    this.totals = const [],
    required this.total,
  });
}
