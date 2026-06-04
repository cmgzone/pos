import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/unit_utils.dart';

class ReceiptService {
  static String _pdfSafe(String? value) {
    final text = value ?? '';
    return text
        .replaceAll(RegExp(r'[^\x20-\x7E]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _formatDocumentDate(String? raw) {
    final fallback = DateTime.now();
    final date = raw == null || raw.trim().isEmpty
        ? fallback
        : DateTime.tryParse(raw) ?? fallback;
    return '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Generate a PDF receipt for a sale
  static Future<pw.Document> generateReceipt({
    required String saleId,
    required double total,
    required double subtotal,
    required double tax,
    required double discount,
    required String paymentType,
    required List<Map<String, dynamic>> items,
    double amountTendered = 0,
    double changeGiven = 0,
    String? customerName,
    double balanceDue = 0,
    String? dueDate,
    String? cashierName,
    String? documentDate,
    String documentTitle = 'Sales Receipt',
    String recordLabel = 'Sale',
    String? referenceSaleId,
    String? note,
    String? etimsStatus,
    String? etimsInvoiceNumber,
    String? etimsControlUnitInvoiceNumber,
    String? etimsControlUnitSerial,
    String? etimsVerificationUrl,
    String? etimsQrCode,
    bool useAbsoluteAmounts = false,
    bool showTenderedBreakdown = false,
  }) async {
    final pdf = pw.Document();
    final dateStr = _formatDocumentDate(documentDate);
    final displayTotal = useAbsoluteAmounts ? total.abs() : total;
    final displaySubtotal = useAbsoluteAmounts ? subtotal.abs() : subtotal;
    final displayTax = useAbsoluteAmounts ? tax.abs() : tax;
    final displayDiscount = useAbsoluteAmounts ? discount.abs() : discount;
    final isCash = showTenderedBreakdown || paymentType.toLowerCase() == 'cash';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          72 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 8 * PdfPageFormat.mm,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Store header
              pw.Text(
                _pdfSafe(ShopSettings.shopName).toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (ShopSettings.shopAddress.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  _pdfSafe(ShopSettings.shopAddress),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
              if (ShopSettings.shopPhone.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'Phone: ${_pdfSafe(ShopSettings.shopPhone)}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
              if (ShopSettings.shopEmail.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  _pdfSafe(ShopSettings.shopEmail),
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
              if (ShopSettings.kraPin.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  'KRA PIN: ${_pdfSafe(ShopSettings.kraPin)}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
              pw.SizedBox(height: 8),
              pw.Text(
                _pdfSafe(documentTitle).toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),

              // Divider
              pw.Container(
                width: double.infinity,
                height: 1,
                color: PdfColors.grey400,
              ),
              pw.SizedBox(height: 8),

              // Date & Sale ID
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Date: $dateStr',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    '$recordLabel #${saleId.substring(0, 8)}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Payment: ${_pdfSafe(paymentType).toUpperCase()}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    'Cashier: ${_pdfSafe(cashierName ?? 'Unknown Cashier')}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
              if (referenceSaleId != null &&
                  referenceSaleId.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Original Sale: ${_pdfSafe(referenceSaleId.substring(0, 8))}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
              if (customerName != null && customerName.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Customer: ${_pdfSafe(customerName)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    if (balanceDue > 0)
                      pw.Text(
                        'Kopesha Due: ${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ],
              if (note != null && note.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Note: ${_pdfSafe(note)}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ],
                ),
              ],
              if (dueDate != null && dueDate.trim().isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Due Date: ${_pdfSafe(dueDate)}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ],
              pw.SizedBox(height: 8),

              // Dashed divider
              pw.Container(
                width: double.infinity,
                height: 1,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(
                      width: 0.5,
                      style: pw.BorderStyle.dashed,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 6),

              // Column headers
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 4,
                    child: pw.Text(
                      'Item',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      'Qty',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'Price',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text(
                      'Total',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                height: 0.5,
                color: PdfColors.grey400,
              ),
              pw.SizedBox(height: 4),

              // Items
              ...items.map((item) {
                final rawQty = (item['quantity'] as num).toDouble();
                final qty = useAbsoluteAmounts ? rawQty.abs() : rawQty;
                final price = (item['unit_price'] as num).toDouble();
                final itemTotal = useAbsoluteAmounts
                    ? (rawQty * price).abs()
                    : qty * price;
                final unit = item['unit'] as String?;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 4,
                        child: pw.Text(
                          _pdfSafe(item['product_name'] as String? ?? 'Item'),
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          _pdfSafe(UnitUtils.formatWithUnit(qty, unit)),
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          '${ShopSettings.currency}${price.toStringAsFixed(2)}',
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          '${ShopSettings.currency}${itemTotal.toStringAsFixed(2)}',
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              pw.SizedBox(height: 6),
              pw.Container(
                width: double.infinity,
                height: 1,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(
                      width: 0.5,
                      style: pw.BorderStyle.dashed,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(height: 8),

              // Totals
              _pdfTotalRow(
                'Subtotal',
                '${ShopSettings.currency}${displaySubtotal.toStringAsFixed(2)}',
              ),
              _pdfTotalRow(
                'Tax (${ShopSettings.taxRate}%)',
                '${ShopSettings.currency}${displayTax.toStringAsFixed(2)}',
              ),
              if (discount > 0)
                _pdfTotalRow(
                  'Discount',
                  '-${ShopSettings.currency}${displayDiscount.toStringAsFixed(2)}',
                ),
              pw.SizedBox(height: 4),
              pw.Container(
                width: double.infinity,
                height: 1,
                color: PdfColors.grey800,
              ),
              pw.SizedBox(height: 4),

              // Grand total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    useAbsoluteAmounts ? 'REFUND TOTAL' : 'TOTAL',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '${ShopSettings.currency}${displayTotal.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              if (isCash) ...[
                pw.SizedBox(height: 6),
                _pdfTotalRow(
                  'Cash Received',
                  '${ShopSettings.currency}${amountTendered.toStringAsFixed(2)}',
                ),
                _pdfTotalRow(
                  'Change Returned',
                  '${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}',
                ),
              ],

              if (_hasEtimsDetails(
                etimsStatus: etimsStatus,
                etimsInvoiceNumber: etimsInvoiceNumber,
                etimsControlUnitInvoiceNumber: etimsControlUnitInvoiceNumber,
                etimsControlUnitSerial: etimsControlUnitSerial,
                etimsVerificationUrl: etimsVerificationUrl,
                etimsQrCode: etimsQrCode,
              )) ...[
                pw.SizedBox(height: 10),
                pw.Container(
                  width: double.infinity,
                  height: 0.5,
                  color: PdfColors.grey400,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'KRA eTIMS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                if ((etimsStatus ?? '').trim().isNotEmpty)
                  _pdfTotalRow('Status', _pdfSafe(etimsStatus)),
                if ((etimsInvoiceNumber ?? '').trim().isNotEmpty)
                  _pdfTotalRow('Invoice', _pdfSafe(etimsInvoiceNumber)),
                if ((etimsControlUnitInvoiceNumber ?? '').trim().isNotEmpty)
                  _pdfTotalRow(
                    'CU Invoice',
                    _pdfSafe(etimsControlUnitInvoiceNumber),
                  ),
                if ((etimsControlUnitSerial ?? '').trim().isNotEmpty)
                  _pdfTotalRow('CU Serial', _pdfSafe(etimsControlUnitSerial)),
                if ((etimsVerificationUrl ?? '').trim().isNotEmpty)
                  pw.Text(
                    _pdfSafe(etimsVerificationUrl),
                    style: const pw.TextStyle(
                      fontSize: 6,
                      color: PdfColors.grey600,
                    ),
                  ),
                if (((etimsQrCode ?? etimsVerificationUrl) ?? '')
                    .trim()
                    .isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: (etimsQrCode ?? etimsVerificationUrl)!.trim(),
                    width: 64,
                    height: 64,
                  ),
                ],
              ],

              pw.SizedBox(height: 12),

              // Footer
              pw.Container(
                width: double.infinity,
                height: 0.5,
                color: PdfColors.grey400,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                _pdfSafe(ShopSettings.receiptFooter),
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.SizedBox(height: 8),
              // Barcode-style sale ID
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: saleId,
                width: 150,
                height: 40,
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                saleId,
                style: const pw.TextStyle(
                  fontSize: 6,
                  color: PdfColors.grey500,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static bool _hasEtimsDetails({
    String? etimsStatus,
    String? etimsInvoiceNumber,
    String? etimsControlUnitInvoiceNumber,
    String? etimsControlUnitSerial,
    String? etimsVerificationUrl,
    String? etimsQrCode,
  }) {
    return [
      etimsStatus,
      etimsInvoiceNumber,
      etimsControlUnitInvoiceNumber,
      etimsControlUnitSerial,
      etimsVerificationUrl,
      etimsQrCode,
    ].any((value) => value != null && value.trim().isNotEmpty);
  }

  static pw.Widget _pdfTotalRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  /// Show print preview dialog
  static Future<void> showReceiptPreview(
    BuildContext context, {
    required String saleId,
    required double total,
    required double subtotal,
    required double tax,
    required double discount,
    required String paymentType,
    required List<Map<String, dynamic>> items,
    double amountTendered = 0,
    double changeGiven = 0,
    String? customerName,
    double balanceDue = 0,
    String? dueDate,
    String? cashierName,
    String? documentDate,
    String previewTitle = 'Receipt Preview',
    String fileNamePrefix = 'receipt',
    String documentTitle = 'Sales Receipt',
    String recordLabel = 'Sale',
    String? referenceSaleId,
    String? note,
    String? etimsStatus,
    String? etimsInvoiceNumber,
    String? etimsControlUnitInvoiceNumber,
    String? etimsControlUnitSerial,
    String? etimsVerificationUrl,
    String? etimsQrCode,
    bool useAbsoluteAmounts = false,
    bool showTenderedBreakdown = false,
  }) async {
    final pdf = await generateReceipt(
      saleId: saleId,
      total: total,
      subtotal: subtotal,
      tax: tax,
      discount: discount,
      paymentType: paymentType,
      items: items,
      amountTendered: amountTendered,
      changeGiven: changeGiven,
      customerName: customerName,
      balanceDue: balanceDue,
      dueDate: dueDate,
      cashierName: cashierName,
      documentDate: documentDate,
      documentTitle: documentTitle,
      recordLabel: recordLabel,
      referenceSaleId: referenceSaleId,
      note: note,
      etimsStatus: etimsStatus,
      etimsInvoiceNumber: etimsInvoiceNumber,
      etimsControlUnitInvoiceNumber: etimsControlUnitInvoiceNumber,
      etimsControlUnitSerial: etimsControlUnitSerial,
      etimsVerificationUrl: etimsVerificationUrl,
      etimsQrCode: etimsQrCode,
      useAbsoluteAmounts: useAbsoluteAmounts,
      showTenderedBreakdown: showTenderedBreakdown,
    );

    if (!context.mounted) {
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 500,
          height: 700,
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.primaryLight),
                  const SizedBox(width: 12),
                  Text(
                    previewTitle,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),

              // PDF Preview
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: PdfPreview(
                    build: (_) => pdf.save(),
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pdfFileName: '${fileNamePrefix}_$saleId.pdf',
                    actions: [
                      IconButton(
                        icon: const Icon(
                          Icons.download,
                          color: AppColors.primaryLight,
                        ),
                        tooltip: 'Save PDF',
                        onPressed: () async {
                          await Printing.sharePdf(
                            bytes: await pdf.save(),
                            filename: '${fileNamePrefix}_$saleId.pdf',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
