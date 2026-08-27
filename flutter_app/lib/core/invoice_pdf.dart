import 'package:flutter/services.dart' show rootBundle;
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

/// Renders [data] as a branded, professional-looking one-page PDF and hands
/// it to the OS print/save dialog — covers both "اطبع" (a real printer) and
/// "احفظ كـ PDF".
///
/// Uses pw.MultiPage (not a fixed pw.Page) so content that doesn't fit one
/// page flows onto a second instead of the previous single-Page layout
/// silently mis-rendering when content overflowed its bounds. The logo load
/// is wrapped in try/catch — a decode failure just skips the image instead
/// of leaving a broken/blank box in a fixed-size container.
Future<void> printInvoice(InvoiceData data) async {
  final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
  final bold = await PdfGoogleFonts.notoNaskhArabicBold();
  pw.MemoryImage? logo;
  try {
    final logoBytes = (await rootBundle.load('assets/branding/logo.png')).buffer.asUint8List();
    logo = pw.MemoryImage(logoBytes);
  } catch (_) {
    logo = null;
  }
  final doc = pw.Document();
  final statusColor = PdfColor.fromInt(data.statusColor);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 26),
      header: (context) => context.pageNumber == 1 ? _header(data, logo) : pw.SizedBox(),
      build: (context) => [
        pw.SizedBox(height: 18),
        _statusAndDateRow(data, statusColor),
        if (data.customerName != null || data.customerPhone != null) ...[
          pw.SizedBox(height: 14),
          _customerBox(data),
        ],
        if (data.details.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _detailsTable(data),
        ],
        if (data.items.isNotEmpty) ...[
          pw.SizedBox(height: 14),
          _itemsTable(data),
        ],
        pw.SizedBox(height: 14),
        _totalsBox(data),
        pw.SizedBox(height: 24),
        _footer(),
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}

/// Simple two-line masthead: bold app name + invoice title/number under a
/// thin accent rule — no gradients, no overlapping containers, so it can't
/// mis-render regardless of page content below it.
pw.Widget _header(InvoiceData data, pw.MemoryImage? logo) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 42,
              height: 42,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                color: _pdfLightBg,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _pdfBorder, width: 0.6),
              ),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 10),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('وصّلها', style: pw.TextStyle(color: _pdfPrimaryDark, fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.Text('تطبيق النقل والتوصيل', style: pw.TextStyle(color: _pdfTextFaint, fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(data.title, style: pw.TextStyle(color: _pdfPrimaryDark, fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text('فاتورة رقم #${data.invoiceNumber}', style: pw.TextStyle(color: _pdfTextFaint, fontSize: 10, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 14),
      pw.Container(height: 2.5, color: _pdfAccent),
    ],
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
        child: pw.Text(data.statusLabel, style: pw.TextStyle(color: statusColor, fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ),
      if (data.dateLabel != null) pw.Text(data.dateLabel!, style: pw.TextStyle(color: _pdfTextFaint, fontSize: 11, fontWeight: pw.FontWeight.bold)),
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
          pw.Text(data.customerName!, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        if (data.customerPhone != null) ...[
          pw.SizedBox(height: 3),
          pw.Text(data.customerPhone!, style: pw.TextStyle(fontSize: 11, color: _pdfTextFaint, fontWeight: pw.FontWeight.bold)),
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
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: pw.Text(data.details[i].label, style: pw.TextStyle(fontSize: 11.5, color: _pdfTextFaint, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: pw.Text(data.details[i].value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
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
    headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 11.5, fontWeight: pw.FontWeight.bold),
    cellStyle: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold),
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
                pw.Text(row.label, style: pw.TextStyle(fontSize: 11.5, color: _pdfTextFaint, fontWeight: pw.FontWeight.bold)),
                pw.Text(row.value, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        if (data.totals.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Divider(color: _pdfBorder)),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('الإجمالي', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text('${data.total} ج.م', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _pdfAccent)),
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
        child: pw.Text('شكرًا لاستخدامك وصّلها', style: pw.TextStyle(fontSize: 11, color: _pdfTextFaint, fontWeight: pw.FontWeight.bold)),
      ),
    ],
  );
}
