import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'catalog_share_service.dart';

class CatalogQrPosterService {
  static Future<Uint8List> buildPoster(CatalogShareInfo info) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(30),
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              info.businessName,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 25, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Scan to view products and place your order',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 26),
            pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: info.url,
                width: 210,
                height: 210,
              ),
            ),
            pw.SizedBox(height: 22),
            pw.Text(
              'Open the camera on your phone and point it at this QR code.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              info.url,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 8),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  static Future<Uint8List?> buildPreviewPng(CatalogShareInfo info) async {
    try {
      final poster = await buildPoster(info);
      await for (final page in Printing.raster(poster, pages: const [0])) {
        return page.toPng();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<void> sharePoster(CatalogShareInfo info) async {
    await Printing.sharePdf(
      bytes: await buildPoster(info),
      filename: '${_fileName(info.businessName)}-catalog-qr.pdf',
    );
  }

  static Future<void> printPoster(CatalogShareInfo info) async {
    await Printing.layoutPdf(
      name: '${info.businessName} Catalog QR',
      onLayout: (_) => buildPoster(info),
    );
  }

  static String _fileName(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'shop' : normalized;
  }
}
