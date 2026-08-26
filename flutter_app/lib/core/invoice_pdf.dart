import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'invoice_data.dart';

// Brand palette, mirrored from AppColors (core/theme.dart) as PdfColor —
// this file avoids importing package:flutter, so the same ARGB ints are
// re-declared here rather than shared directly.
final _pdfPrimary = PdfColor.fromInt(0xFF0E4B49);
final _pdfPrimaryDark = PdfColor.fromInt(0xFF082F2E);
final _pdfAccent = PdfColor.fromInt(0xFFB8863B);
final _pdfLightBg = PdfColor.fromInt(0xFFF7FAF9);
final _pdfBorder = PdfColor.fromInt(0xFFE5E7EB);
final _pdfTextFaint = PdfColor.fromInt(0xFF6B7280);

/// Renders [data] as a colorful, branded one-page PDF (teal header banner,
/// status pill, bordered detail/items tables, a highlighted total) and
/// hands it to the OS print/save dialog — covers both "اطبع" (a real
/// printer) and "احفظ كـ PDF", per the request for a professional,
/// company-style printed invoice instead of plain text.
Future<void> printInvoice(InvoiceData data) async {
  final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
  final bold = await PdfGoogleFonts.notoNaskhArabicBold();
  final doc = pw.Document();
  final statusColor = PdfColor.fromInt(data.statusColor);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.all(0),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(data),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(28, 20, 28, 28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _statusAndDateRow(data, statusColor),
                if (data.customerName != null || data.customerPhone != null) ...[
                  pw.SizedBox(height: 16),
                  _customerBox(data),
                ],
                if (data.details.isNotEmpty) ...[
                  pw.SizedBox(height: 16),
                  _detailsTable(data),
                ],
                if (data.items.isNotEmpty) ...[
                  pw.SizedBox(height: 16),
                  _itemsTable(data),
                ],
                pw.SizedBox(height: 16),
                _totalsBox(data),
                pw.SizedBox(height: 28),
                _footer(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}

pw.Widget _header(InvoiceData data) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(28, 26, 28, 22),
    decoration: pw.BoxDecoration(
      gradient: pw.LinearGradient(colors: [_pdfPrimaryDark, _pdfPrimary]),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('وصّلها', style: pw.TextStyle(color: PdfColors.white, fontSize: 26, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('تطبيق النقل والتوصيل', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(data.title, style: pw.TextStyle(color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('فاتورة رقم #${data.invoiceNumber}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _statusAndDateRow(InvoiceData data, PdfColor statusColor) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: pw.BoxDecoration(
          color: PdfColor(statusColor.red, statusColor.green, statusColor.blue, 0.12),
          borderRadius: pw.BorderRadius.circular(999),
        ),
        child: pw.Text(data.statusLabel, style: pw.TextStyle(color: statusColor, fontSize: 11, fontWeight: pw.FontWeight.bold)),
      ),
      if (data.dateLabel != null) pw.Text(data.dateLabel!, style: pw.TextStyle(color: _pdfTextFaint, fontSize: 10)),
    ],
  );
}

pw.Widget _customerBox(InvoiceData data) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(color: _pdfLightBg, borderRadius: pw.BorderRadius.circular(8)),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (data.customerName != null)
          pw.Text(data.customerName!, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        if (data.customerPhone != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(data.customerPhone!, style: pw.TextStyle(fontSize: 10, color: _pdfTextFaint)),
        ],
      ],
    ),
  );
}

pw.Widget _detailsTable(InvoiceData data) {
  return pw.Table(
    border: pw.TableBorder.all(color: _pdfBorder, width: 0.6),
    columnWidths: const {0: pw.FlexColumnWidth(1.2), 1: pw.FlexColumnWidth(2)},
    children: [
      for (var i = 0; i < data.details.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isEven ? PdfColors.white : _pdfLightBg),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: pw.Text(data.details[i].label, style: pw.TextStyle(fontSize: 10.5, color: _pdfTextFaint, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: pw.Text(data.details[i].value, style: const pw.TextStyle(fontSize: 11)),
            ),
          ],
        ),
    ],
  );
}

pw.Widget _itemsTable(InvoiceData data) {
  return pw.TableHelper.fromTextArray(
    headers: const ['الصنف', 'الكمية', 'السعر'],
    data: data.items.map((it) => [it.name, '${it.qty}', it.price != null ? '${it.price} ج.م' : '—']).toList(),
    headerDecoration: pw.BoxDecoration(color: _pdfPrimary),
    headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 10.5, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 10.5),
    cellAlignments: {0: pw.Alignment.centerRight, 1: pw.Alignment.center, 2: pw.Alignment.center},
    oddRowDecoration: pw.BoxDecoration(color: _pdfLightBg),
    border: pw.TableBorder.all(color: _pdfBorder, width: 0.6),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  );
}

pw.Widget _totalsBox(InvoiceData data) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: _pdfLightBg,
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: _pdfBorder, width: 0.6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (final row in data.totals)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(row.label, style: pw.TextStyle(fontSize: 10.5, color: _pdfTextFaint)),
                pw.Text(row.value, style: const pw.TextStyle(fontSize: 10.5)),
              ],
            ),
          ),
        if (data.totals.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Divider(color: _pdfBorder)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('الإجمالي', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('${data.total} ج.م', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _pdfAccent)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _footer() {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Divider(color: _pdfAccent, thickness: 1.2),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text('شكرًا لاستخدامك وصّلها 🧡', style: pw.TextStyle(fontSize: 11, color: _pdfTextFaint, fontWeight: pw.FontWeight.bold)),
      ),
    ],
  );
}
