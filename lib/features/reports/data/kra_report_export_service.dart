import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/shop_settings.dart';

class KraReportExportService {
  static final DateFormat _fileDate = DateFormat('yyyyMMdd_HHmmss');

  static Future<String?> saveCsv({
    required Map<String, dynamic> zReport,
    required Map<String, dynamic> vat,
    required Map<String, dynamic> etims,
    required List<Map<String, dynamic>> rows,
  }) async {
    final fileName = _fileName('csv');
    final bytes = Uint8List.fromList(
      utf8.encode(
        buildCsv(zReport: zReport, vat: vat, etims: etims, rows: rows),
      ),
    );
    return FilePicker.platform.saveFile(
      dialogTitle: 'Save KRA CSV Report',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: bytes,
    );
  }

  static Future<String?> savePdf({
    required Map<String, dynamic> zReport,
    required Map<String, dynamic> vat,
    required Map<String, dynamic> etims,
    required List<Map<String, dynamic>> rows,
  }) async {
    final fileName = _fileName('pdf');
    final bytes = await buildPdf(
      zReport: zReport,
      vat: vat,
      etims: etims,
      rows: rows,
    );
    return FilePicker.platform.saveFile(
      dialogTitle: 'Save KRA PDF Report',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: bytes,
    );
  }

  static String buildCsv({
    required Map<String, dynamic> zReport,
    required Map<String, dynamic> vat,
    required Map<String, dynamic> etims,
    required List<Map<String, dynamic>> rows,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Piki POS KRA Report');
    buffer.writeln('Shop,${_csv(ShopSettings.shopName)}');
    buffer.writeln('KRA PIN,${_csv(ShopSettings.kraPin)}');
    buffer.writeln(
      'Period,${_csv('${vat['from'] ?? ''} to ${vat['to'] ?? ''}')}',
    );
    buffer.writeln();
    buffer.writeln('Summary,Value');
    buffer.writeln('Today sales,${_number(zReport['total_sales'])}');
    buffer.writeln('Today tax,${_number(zReport['total_tax'])}');
    buffer.writeln('Gross sales,${_number(vat['gross_sales'])}');
    buffer.writeln('Net sales,${_number(vat['net_sales'])}');
    buffer.writeln('Output VAT,${_number(vat['output_vat'])}');
    buffer.writeln('Discounts,${_number(vat['discounts'])}');
    buffer.writeln('Receipts,${_number(vat['receipt_count'])}');
    buffer.writeln('eTIMS submitted,${_number(etims['submitted_count'])}');
    buffer.writeln('eTIMS pending,${_number(etims['pending_count'])}');
    buffer.writeln('eTIMS failed,${_number(etims['failed_count'])}');
    buffer.writeln();
    final columns = <String>[
      'Sale ID',
      'Date',
      'Customer',
      'Payment',
      'Total',
      'Tax',
      'Discount',
      'Paid',
      'Balance',
      'Payment Reference',
      'eTIMS Status',
      'eTIMS Invoice',
      'CU Invoice',
      'CU Serial',
      'Submitted At',
      'eTIMS Error',
      'Refund For',
      'Refund Note',
    ];
    buffer.writeln(columns.map(_csv).join(','));
    for (final row in rows) {
      buffer.writeln(
        [
          row['id'],
          row['created_at'],
          row['customer_name'],
          row['payment_type'],
          _number(row['total_amount']),
          _number(row['tax']),
          _number(row['discount']),
          _number(row['amount_paid']),
          _number(row['balance_due']),
          row['payment_reference'],
          row['etims_status'],
          row['etims_invoice_number'],
          row['etims_control_unit_invoice_number'],
          row['etims_control_unit_serial'],
          row['etims_submitted_at'],
          row['etims_error'],
          row['refund_for_sale_id'],
          row['refund_note'],
        ].map(_csv).join(','),
      );
    }
    return buffer.toString();
  }

  static Future<Uint8List> buildPdf({
    required Map<String, dynamic> zReport,
    required Map<String, dynamic> vat,
    required Map<String, dynamic> etims,
    required List<Map<String, dynamic>> rows,
  }) async {
    final document = pw.Document();
    final period = '${vat['from'] ?? ''} to ${vat['to'] ?? ''}'.trim();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
            _pdfSafe(ShopSettings.shopName).toUpperCase(),
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Piki POS KRA Report',
            style: const pw.TextStyle(fontSize: 12),
          ),
          if (ShopSettings.kraPin.trim().isNotEmpty)
            pw.Text(
              'KRA PIN: ${_pdfSafe(ShopSettings.kraPin)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          if (period.isNotEmpty)
            pw.Text(
              'Period: ${_pdfSafe(period)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const ['Summary', 'Value'],
            data: [
              ['Today sales', _money(zReport['total_sales'])],
              ['Today tax', _money(zReport['total_tax'])],
              ['Gross sales', _money(vat['gross_sales'])],
              ['Net sales', _money(vat['net_sales'])],
              ['Output VAT', _money(vat['output_vat'])],
              ['Discounts', _money(vat['discounts'])],
              ['Receipts', '${vat['receipt_count'] ?? 0}'],
              ['eTIMS submitted', '${etims['submitted_count'] ?? 0}'],
              ['eTIMS pending', '${etims['pending_count'] ?? 0}'],
              ['eTIMS failed', '${etims['failed_count'] ?? 0}'],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Sales and eTIMS Records',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Sale',
              'Total',
              'Tax',
              'eTIMS',
              'CU Invoice',
            ],
            data: rows.map((row) {
              return [
                _shortDate(row['created_at']),
                _shortId(row['id']),
                _money(row['total_amount']),
                _money(row['tax']),
                _pdfSafe(row['etims_status']?.toString() ?? ''),
                _pdfSafe(
                  row['etims_control_unit_invoice_number']?.toString() ??
                      row['etims_invoice_number']?.toString() ??
                      '',
                ),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Generated ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
    return document.save();
  }

  static String _fileName(String extension) {
    return 'piki_kra_report_${_fileDate.format(DateTime.now())}.$extension';
  }

  static String _csv(Object? value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    return '"$escaped"';
  }

  static String _number(Object? value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    if (amount == null) {
      return '0.00';
    }
    return amount.toStringAsFixed(2);
  }

  static String _money(Object? value) {
    return '${ShopSettings.currency}${_number(value)}';
  }

  static String _shortId(Object? value) {
    final id = value?.toString() ?? '';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  static String _shortDate(Object? value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return _pdfSafe(raw);
    }
    return DateFormat('yyyy-MM-dd').format(parsed);
  }

  static String _pdfSafe(String value) {
    return value
        .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
