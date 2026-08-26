import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Renders an invoice as a one-page PDF and hands it to the OS print/save
/// dialog (Printing.layoutPdf) — covers both "اطبع" (a real printer) and
/// "احفظ كـ PDF"، since that's what the system dialog offers on Android.
/// [body] is the same text buildRideInvoiceText/buildOrderInvoiceText
/// produces for the WhatsApp share, so print and WhatsApp always match.
Future<void> printInvoiceText(String body) async {
  final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
  final bold = await PdfGoogleFonts.notoNaskhArabicBold();
  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      build: (context) => pw.Padding(
        padding: const pw.EdgeInsets.all(24),
        child: pw.Text(body, style: const pw.TextStyle(fontSize: 13, lineSpacing: 4)),
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (format) => doc.save());
}
