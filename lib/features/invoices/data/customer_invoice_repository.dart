import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../sales/data/sale_repository.dart';

const _uuid = Uuid();

class CustomerInvoiceLineDraft {
  final String lineType;
  final String? productId;
  final String? variantId;
  final String? serviceId;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double unitCost;
  final double saleToStockFactor;
  final String stockUnit;
  final bool trackStock;

  const CustomerInvoiceLineDraft({
    required this.lineType,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.productId,
    this.variantId,
    this.serviceId,
    this.unitCost = 0,
    this.saleToStockFactor = 1,
    this.stockUnit = 'pcs',
    this.trackStock = true,
  });

  double get lineTotal => quantity * unitPrice;
}

class CustomerInvoiceRepository {
  static const invoicesTable = 'customer_invoices';
  static const itemsTable = 'customer_invoice_items';

  static const statusDraft = 'draft';
  static const statusSent = 'sent';
  static const statusPartial = 'partial';
  static const statusPaid = 'paid';
  static const statusCancelled = 'cancelled';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<void> _ensureInvoiceWriteAccess(String action) async {
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: 'sales',
      action: action,
    );
  }

  static double _money(num value) => double.parse(value.toStringAsFixed(2));

  static String cleanStatus(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case statusSent:
      case statusPartial:
      case statusPaid:
      case statusCancelled:
      case statusDraft:
        return status!.trim().toLowerCase();
      default:
        return statusDraft;
    }
  }

  static Future<String> nextInvoiceNumber() async {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM $invoicesTable
      WHERE invoice_number LIKE ?
        AND COALESCE(branch_id, ?) = ?
      ''',
      ['INV-$date-%', ..._currentBranchArgs],
    );
    final count =
        (rows.isEmpty ? 0 : (rows.first['count'] as num? ?? 0).toInt()) + 1;
    return 'INV-$date-${count.toString().padLeft(3, '0')}';
  }

  static Future<List<Map<String, dynamic>>> getAll({
    String filter = 'open',
    String query = '',
  }) async {
    final clauses = <String>[
      'ci.deleted_at IS NULL',
      'COALESCE(ci.branch_id, ?) = ?',
    ];
    final args = <dynamic>[..._currentBranchArgs];
    final cleanFilter = filter.trim().toLowerCase();
    switch (cleanFilter) {
      case 'draft':
      case 'sent':
      case 'partial':
      case 'paid':
      case 'cancelled':
        clauses.add('ci.status = ?');
        args.add(cleanFilter);
        break;
      case 'overdue':
        clauses.add(
          "ci.balance_due > 0 AND ci.status NOT IN ('paid', 'cancelled') AND ci.due_date IS NOT NULL AND date(ci.due_date) < date('now', 'localtime')",
        );
        break;
      case 'all':
        break;
      default:
        clauses.add("ci.status NOT IN ('paid', 'cancelled')");
        break;
    }
    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      final pattern = '%$trimmedQuery%';
      clauses.add(
        '(ci.invoice_number LIKE ? OR ci.customer_name LIKE ? OR ci.customer_phone LIKE ? OR ci.customer_email LIKE ?)',
      );
      args.addAll([pattern, pattern, pattern, pattern]);
    }

    return DatabaseService.rawQuery('''
      SELECT
        ci.*,
        CASE
          WHEN ci.balance_due > 0
           AND ci.status NOT IN ('paid', 'cancelled')
           AND ci.due_date IS NOT NULL
           AND date(ci.due_date) < date('now', 'localtime')
          THEN 'overdue'
          ELSE ci.status
        END AS display_status,
        COALESCE((SELECT COUNT(*) FROM $itemsTable ii WHERE ii.invoice_id = ci.id AND ii.deleted_at IS NULL), 0) AS item_count
      FROM $invoicesTable ci
      WHERE ${clauses.join(' AND ')}
      ORDER BY ci.created_at DESC
      ''', args);
  }

  static Future<Map<String, dynamic>> getStats() async {
    final rows = await DatabaseService.rawQuery('''
      SELECT
        COUNT(*) AS total_count,
        COALESCE(SUM(CASE WHEN status NOT IN ('paid', 'cancelled') THEN balance_due ELSE 0 END), 0) AS open_amount,
        COALESCE(SUM(CASE WHEN status = 'paid' THEN total_amount ELSE 0 END), 0) AS paid_amount,
        COUNT(CASE WHEN balance_due > 0 AND status NOT IN ('paid', 'cancelled') AND due_date IS NOT NULL AND date(due_date) < date('now', 'localtime') THEN 1 END) AS overdue_count
      FROM $invoicesTable
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ''', _currentBranchArgs);
    return rows.isEmpty ? const <String, dynamic>{} : rows.first;
  }

  static Future<Map<String, dynamic>?> getInvoiceWithItems(String id) async {
    final invoiceRows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $invoicesTable
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [id, ..._currentBranchArgs],
    );
    if (invoiceRows.isEmpty) return null;

    final items = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $itemsTable
      WHERE invoice_id = ?
        AND deleted_at IS NULL
      ORDER BY sort_order ASC, created_at ASC
      ''',
      [id],
    );
    return {'invoice': invoiceRows.first, 'items': items};
  }

  static Future<String> createInvoice({
    String? customerId,
    required String customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerKraPin,
    String? invoiceNumber,
    String status = statusDraft,
    required DateTime issueDate,
    DateTime? dueDate,
    double discount = 0,
    String? note,
    required List<CustomerInvoiceLineDraft> lines,
  }) async {
    await _ensureInvoiceWriteAccess('create invoices');
    final cleanName = customerName.trim();
    if (cleanName.isEmpty) {
      throw Exception('Customer name is required');
    }
    if (lines.isEmpty) {
      throw Exception('Add at least one invoice item');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final resolvedInvoiceNumber = invoiceNumber?.trim().isNotEmpty == true
        ? invoiceNumber!.trim()
        : await nextInvoiceNumber();
    final subtotal = _money(
      lines.fold<double>(0, (sum, line) => sum + line.lineTotal),
    );
    final tax = _money(subtotal * (ShopSettings.taxRate / 100));
    final safeDiscount = discount < 0 ? 0.0 : _money(discount);
    final total = _money(subtotal + tax - safeDiscount);
    final paid = 0.0;
    final cleanStatus = CustomerInvoiceRepository.cleanStatus(status);

    await DatabaseService.db.transaction((txn) async {
      await txn.insert(invoicesTable, {
        'id': id,
        'branch_id': DatabaseService.currentBranchId,
        'invoice_number': resolvedInvoiceNumber,
        'customer_id': customerId?.trim().isEmpty == true ? null : customerId,
        'customer_name': cleanName,
        'customer_phone': _clean(customerPhone),
        'customer_email': _clean(customerEmail),
        'customer_kra_pin': _clean(customerKraPin),
        'status': cleanStatus,
        'issue_date': issueDate.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'subtotal': subtotal,
        'tax': tax,
        'discount': safeDiscount,
        'total_amount': total,
        'amount_paid': paid,
        'balance_due': total,
        'note': _clean(note),
        'sent_at': cleanStatus == statusSent ? now : null,
        'created_by': SessionService.currentUserId,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        await txn.insert(itemsTable, {
          'id': _uuid.v4(),
          'branch_id': DatabaseService.currentBranchId,
          'invoice_id': id,
          'line_type': line.lineType,
          'product_id': _clean(line.productId),
          'variant_id': _clean(line.variantId),
          'service_id': _clean(line.serviceId),
          'description': line.description.trim(),
          'quantity': line.quantity,
          'unit': line.unit.trim().isEmpty ? 'pcs' : line.unit.trim(),
          'unit_price': line.unitPrice,
          'unit_cost': line.unitCost,
          'sale_to_stock_factor': line.saleToStockFactor <= 0
              ? 1.0
              : line.saleToStockFactor,
          'stock_unit': line.stockUnit.trim().isEmpty
              ? line.unit
              : line.stockUnit.trim(),
          'track_stock': line.trackStock ? 1 : 0,
          'line_total': _money(line.lineTotal),
          'sort_order': index,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: invoicesTable,
      entityId: id,
    );
    return id;
  }

  static Future<void> markSent(String id) async {
    await _ensureInvoiceWriteAccess('send invoices');
    final data = await getInvoiceWithItems(id);
    final invoice = data?['invoice'] as Map<String, dynamic>?;
    if (invoice == null) {
      throw Exception('Invoice not found');
    }
    final currentStatus = cleanStatus(invoice['status'] as String?);
    if (currentStatus == statusCancelled) {
      throw Exception('Cancelled invoices cannot be sent');
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(invoicesTable, {
      'status': currentStatus == statusDraft ? statusSent : currentStatus,
      'sent_at': now,
      'updated_at': now,
    }, id);
  }

  static Future<void> cancel(String id) async {
    await _ensureInvoiceWriteAccess('cancel invoices');
    final data = await getInvoiceWithItems(id);
    final invoice = data?['invoice'] as Map<String, dynamic>?;
    if (invoice == null) {
      throw Exception('Invoice not found');
    }
    if ((invoice['sale_id'] as String?)?.trim().isNotEmpty == true) {
      throw Exception(
        'Invoices already converted to sales cannot be cancelled',
      );
    }
    if ((invoice['amount_paid'] as num? ?? 0) > 0) {
      throw Exception('Invoices with recorded payments cannot be cancelled');
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(invoicesTable, {
      'status': statusCancelled,
      'updated_at': now,
    }, id);
  }

  static Future<void> recordPayment({
    required String id,
    required double amount,
    String? method,
    String? reference,
  }) async {
    await _ensureInvoiceWriteAccess('record invoice payments');
    if (amount <= 0) {
      throw Exception('Payment amount must be greater than zero');
    }
    final data = await getInvoiceWithItems(id);
    final invoice = data?['invoice'] as Map<String, dynamic>?;
    if (invoice == null) {
      throw Exception('Invoice not found');
    }
    if ((invoice['status'] as String?) == statusCancelled) {
      throw Exception('Cancelled invoices cannot receive payments');
    }

    final total = (invoice['total_amount'] as num? ?? 0).toDouble();
    final currentPaid = (invoice['amount_paid'] as num? ?? 0).toDouble();
    final newPaid = _money((currentPaid + amount).clamp(0, total));
    final balance = _money((total - newPaid).clamp(0, total));
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(invoicesTable, {
      'amount_paid': newPaid,
      'balance_due': balance,
      'status': balance <= 0 ? statusPaid : statusPartial,
      'payment_method': _clean(method),
      'payment_reference': _clean(reference),
      'paid_at': balance <= 0 ? now : null,
      'updated_at': now,
    }, id);
  }

  static Future<String> convertToSale({
    required String id,
    String paymentType = 'cash',
  }) async {
    await _ensureInvoiceWriteAccess('convert invoices to sales');
    final data = await getInvoiceWithItems(id);
    final invoice = data?['invoice'] as Map<String, dynamic>?;
    final items =
        (data?['items'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    if (invoice == null) {
      throw Exception('Invoice not found');
    }
    if ((invoice['sale_id'] as String?)?.trim().isNotEmpty == true) {
      return invoice['sale_id'] as String;
    }
    if ((invoice['status'] as String?) == statusCancelled) {
      throw Exception('Cancelled invoices cannot be converted to sales');
    }
    final balance = (invoice['balance_due'] as num? ?? 0).toDouble();
    if (balance > 0.001) {
      throw Exception(
        'Record full payment before converting this invoice to a sale',
      );
    }

    final saleItems = <Map<String, dynamic>>[];
    for (final item in items) {
      final lineType = (item['line_type'] as String? ?? 'product').trim();
      if (lineType == 'product') {
        final productId = (item['product_id'] as String?)?.trim();
        if (productId == null || productId.isEmpty) {
          throw Exception(
            'Product invoice lines need a product before sale conversion',
          );
        }
        saleItems.add({
          'line_type': 'product',
          'product_id': productId,
          'variant_id': _clean(item['variant_id'] as String?),
          'product_name': item['description'] ?? 'Product',
          'quantity': (item['quantity'] as num? ?? 1).toDouble(),
          'unit_price': (item['unit_price'] as num? ?? 0).toDouble(),
          'unit_cost': (item['unit_cost'] as num? ?? 0).toDouble(),
          'unit': item['unit'] as String? ?? 'pcs',
          'sale_to_stock_factor': (item['sale_to_stock_factor'] as num? ?? 1)
              .toDouble(),
          'stock_unit': item['stock_unit'] as String? ?? 'pcs',
          'track_stock': item['track_stock'] ?? 1,
        });
      } else {
        saleItems.add({
          'line_type': 'service',
          'service_id': _clean(item['service_id'] as String?),
          'product_name': item['description'] ?? 'Service',
          'quantity': (item['quantity'] as num? ?? 1).toDouble(),
          'unit_price': (item['unit_price'] as num? ?? 0).toDouble(),
          'service_order_id': null,
        });
      }
    }

    final saleId = await SaleRepository.createSale(
      totalAmount: (invoice['total_amount'] as num? ?? 0).toDouble(),
      tax: (invoice['tax'] as num? ?? 0).toDouble(),
      discount: (invoice['discount'] as num? ?? 0).toDouble(),
      paymentType: paymentType.trim().isEmpty ? 'cash' : paymentType.trim(),
      userId: SessionService.currentUserId,
      customerId: _clean(invoice['customer_id'] as String?),
      customerName: invoice['customer_name'] as String?,
      items: saleItems,
      paymentReference: invoice['invoice_number'] as String?,
      paymentStatus: 'paid',
      paymentMetadata: {'source': 'customer_invoice', 'invoiceId': id},
    );

    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(invoicesTable, {
      'sale_id': saleId,
      'status': statusPaid,
      'paid_at': invoice['paid_at'] ?? now,
      'updated_at': now,
    }, id);
    return saleId;
  }

  static String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}
