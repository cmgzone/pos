import 'package:uuid/uuid.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';

const _uuid = Uuid();

class CustomerRepository {
  static const _table = 'customers';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> search(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      return DatabaseService.rawQuery('''
        SELECT *
        FROM $_table
        WHERE deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ORDER BY balance DESC, name COLLATE NOCASE ASC
        ''', _currentBranchArgs);
    }

    final pattern = '%$trimmed%';
    return DatabaseService.rawQuery(
      '''
      SELECT * FROM $_table
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
        AND (name LIKE ? OR phone LIKE ? OR email LIKE ?)
      ORDER BY
        CASE WHEN name LIKE ? THEN 0 ELSE 1 END,
        balance DESC,
        name COLLATE NOCASE ASC
      ''',
      [..._currentBranchArgs, pattern, pattern, pattern, pattern],
    );
  }

  static Future<List<Map<String, dynamic>>> getKopeshaCustomers({
    String query = '',
    String filter = 'all',
  }) async {
    final trimmed = query.trim();
    final pattern = '%$trimmed%';
    final havingClauses = <String>[
      'SUM(CASE WHEN s.balance_due > 0 THEN 1 ELSE 0 END) > 0',
    ];

    switch (filter) {
      case 'due_today':
        havingClauses.add(
          "SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) = date('now', 'localtime') THEN 1 ELSE 0 END) > 0",
        );
        break;
      case 'overdue':
        havingClauses.add(
          "SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) < date('now', 'localtime') THEN 1 ELSE 0 END) > 0",
        );
        break;
      case 'risky':
        havingClauses.add('''
          (
            SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) < date('now', 'localtime') THEN 1 ELSE 0 END) >= 2
            OR SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) < date('now', 'localtime') THEN s.balance_due ELSE 0 END) >= 250
            OR MIN(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) < date('now', 'localtime') THEN s.due_date END) <= date('now', '-7 day', 'localtime')
          )
          ''');
        break;
    }

    return DatabaseService.rawQuery(
      '''
      SELECT
        c.*,
        COALESCE(SUM(CASE WHEN s.balance_due > 0 THEN s.balance_due ELSE 0 END), 0) as outstanding_balance,
        SUM(CASE WHEN s.balance_due > 0 THEN 1 ELSE 0 END) as open_credit_count,
        SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) = date('now', 'localtime') THEN 1 ELSE 0 END) as due_today_count,
        COALESCE(SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) = date('now', 'localtime') THEN s.balance_due ELSE 0 END), 0) as due_today_amount,
        SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) < date('now', 'localtime') THEN 1 ELSE 0 END) as overdue_count,
        COALESCE(SUM(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) < date('now', 'localtime') THEN s.balance_due ELSE 0 END), 0) as overdue_amount,
        MIN(CASE WHEN s.balance_due > 0 THEN s.due_date END) as next_due_date,
        MIN(CASE WHEN s.balance_due > 0 AND s.due_date IS NOT NULL AND date(s.due_date) < date('now', 'localtime') THEN s.due_date END) as oldest_overdue_date
      FROM customers c
      LEFT JOIN sales s ON s.customer_id = c.id
        AND s.deleted_at IS NULL
        AND COALESCE(s.branch_id, ?) = ?
      WHERE c.deleted_at IS NULL
        AND COALESCE(c.branch_id, ?) = ?
        AND (c.name LIKE ? OR c.phone LIKE ? OR c.email LIKE ?)
      GROUP BY c.id
      HAVING ${havingClauses.join(' AND ')}
      ORDER BY overdue_count DESC, overdue_amount DESC, outstanding_balance DESC, c.name COLLATE NOCASE ASC
      ''',
      [..._currentBranchArgs, ..._currentBranchArgs, pattern, pattern, pattern],
    );
  }

  static Future<Map<String, dynamic>?> getById(String id) async {
    final rows = await DatabaseService.queryAll(
      _table,
      where: 'id = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [id, ..._currentBranchArgs],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> getKopeshaStatement(
    String customerId,
  ) async {
    final customer = await getById(customerId);
    if (customer == null) return null;

    final openCredits = await DatabaseService.rawQuery(
      '''
      SELECT
        id,
        total_amount,
        amount_paid,
        balance_due,
        due_date,
        created_at,
        discount,
        tax
      FROM sales
      WHERE customer_id = ?
        AND balance_due > 0
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN due_date IS NULL THEN 1 ELSE 0 END,
        due_date ASC,
        created_at ASC
      ''',
      [customerId, ..._currentBranchArgs],
    );

    final paymentHistory = await DatabaseService.rawQuery(
      '''
      SELECT
        cp.*,
        COALESCE(
          NULLIF(TRIM(u.name), ''),
          CASE
            WHEN cp.user_id = 'admin' THEN 'Admin'
            WHEN COALESCE(cp.user_id, '') = '' THEN 'Unknown Cashier'
            ELSE cp.user_id
          END
        ) as cashier_name,
        s.total_amount as sale_total,
        s.created_at as sale_created_at,
        s.due_date as sale_due_date
      FROM credit_payments cp
      LEFT JOIN sales s ON s.id = cp.sale_id
      LEFT JOIN users u ON u.id = cp.user_id
      WHERE cp.customer_id = ?
        AND cp.deleted_at IS NULL
        AND COALESCE(cp.branch_id, ?) = ?
      ORDER BY cp.received_at DESC
      ''',
      [customerId, ..._currentBranchArgs],
    );

    final summaryList = await getKopeshaCustomers(query: '', filter: 'all');
    Map<String, dynamic>? summary;
    for (final entry in summaryList) {
      if (entry['id'] == customerId) {
        summary = entry;
        break;
      }
    }

    return {
      'customer': customer,
      'summary': summary,
      'openCredits': openCredits,
      'paymentHistory': paymentHistory,
    };
  }

  static Future<String> create({
    required String name,
    String? phone,
    String? email,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create customers');
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await DatabaseService.insert(_table, {
      'id': id,
      'name': name.trim(),
      'phone': phone?.trim().isEmpty == true ? null : phone?.trim(),
      'email': email?.trim().isEmpty == true ? null : email?.trim(),
      'balance': 0.0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    return id;
  }

  static Future<String> recordPayment({
    required String customerId,
    required double amount,
    required String userId,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'record customer payments');
    final normalizedAmount = double.parse(amount.toStringAsFixed(2));
    if (normalizedAmount <= 0) {
      throw Exception('Payment amount must be greater than zero');
    }

    final paymentGroupId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final cleanNote = note?.trim().isEmpty == true ? null : note?.trim();

    await DatabaseService.db.transaction((txn) async {
      final openCredits = await txn.rawQuery(
        '''
        SELECT id, balance_due
        FROM sales
        WHERE customer_id = ?
          AND balance_due > 0
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ORDER BY
          CASE WHEN due_date IS NULL THEN 1 ELSE 0 END,
          due_date ASC,
          created_at ASC
        ''',
        [customerId, ..._currentBranchArgs],
      );

      if (openCredits.isEmpty) {
        throw Exception('This customer has no outstanding Kopesha balance');
      }

      final totalOutstanding = openCredits.fold<double>(
        0,
        (sum, sale) => sum + ((sale['balance_due'] as num?)?.toDouble() ?? 0),
      );

      if (normalizedAmount - totalOutstanding > 0.009) {
        throw Exception(
          'Payment is higher than the customer outstanding balance',
        );
      }

      var remaining = normalizedAmount;

      for (final sale in openCredits) {
        if (remaining <= 0) break;

        final saleBalance = (sale['balance_due'] as num?)?.toDouble() ?? 0;
        if (saleBalance <= 0) continue;

        final appliedAmount = remaining < saleBalance ? remaining : saleBalance;

        await txn.rawUpdate(
          '''
          UPDATE sales
          SET
            balance_due = CASE WHEN balance_due - ? < 0 THEN 0 ELSE balance_due - ? END,
            amount_paid = amount_paid + ?,
            updated_at = ?,
            sync_status = ?
          WHERE id = ?
            AND COALESCE(branch_id, ?) = ?
          ''',
          [
            appliedAmount,
            appliedAmount,
            appliedAmount,
            now,
            'pending',
            sale['id'],
            DatabaseService.defaultBranchId,
            DatabaseService.currentBranchId,
          ],
        );

        await txn.insert('credit_payments', {
          'id': _uuid.v4(),
          'branch_id': DatabaseService.currentBranchId,
          'payment_group_id': paymentGroupId,
          'customer_id': customerId,
          'sale_id': sale['id'],
          'user_id': userId,
          'amount': appliedAmount,
          'note': cleanNote,
          'received_at': now,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });

        remaining = double.parse(
          (remaining - appliedAmount).toStringAsFixed(2),
        );
      }

      final appliedTotal = normalizedAmount - remaining;

      await txn.rawUpdate(
        '''
        UPDATE customers
        SET
          balance = CASE WHEN balance - ? < 0 THEN 0 ELSE balance - ? END,
          updated_at = ?,
          sync_status = ?
        WHERE id = ?
          AND COALESCE(branch_id, ?) = ?
        ''',
        [
          appliedTotal,
          appliedTotal,
          now,
          'pending',
          customerId,
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
    });

    await AuditLogService.log(
      action: 'payment',
      entityTable: 'credit_payments',
      entityId: paymentGroupId,
    );
    return paymentGroupId;
  }

  static Future<Map<String, dynamic>?> getPaymentGroupReceipt(
    String paymentGroupId,
  ) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT
        cp.*,
        c.name as customer_name,
        s.due_date as sale_due_date,
        s.created_at as sale_created_at,
        COALESCE(
          NULLIF(TRIM(u.name), ''),
          CASE
            WHEN cp.user_id = 'admin' THEN 'Admin'
            WHEN COALESCE(cp.user_id, '') = '' THEN 'Unknown Cashier'
            ELSE cp.user_id
          END
        ) as cashier_name
      FROM credit_payments cp
      JOIN customers c ON c.id = cp.customer_id
      LEFT JOIN sales s ON s.id = cp.sale_id
      LEFT JOIN users u ON u.id = cp.user_id
      WHERE cp.payment_group_id = ?
        AND cp.deleted_at IS NULL
        AND COALESCE(cp.branch_id, ?) = ?
      ORDER BY
        CASE WHEN s.due_date IS NULL THEN 1 ELSE 0 END,
        s.due_date ASC,
        s.created_at ASC,
        cp.received_at ASC
      ''',
      [paymentGroupId, ..._currentBranchArgs],
    );

    if (rows.isEmpty) {
      return null;
    }

    final first = rows.first;
    final items = rows.map((row) {
      final amount = (row['amount'] as num? ?? 0).toDouble();
      final saleId = row['sale_id'] as String?;
      final dueDate = row['sale_due_date'] as String?;
      final dueLabel = dueDate == null || dueDate.isEmpty
          ? ''
          : ' · due $dueDate';
      return <String, dynamic>{
        'product_name': saleId == null || saleId.isEmpty
            ? 'Outstanding balance payment'
            : 'Sale #${saleId.substring(0, 8)}$dueLabel',
        'quantity': 1,
        'unit_price': amount,
        'unit': '',
      };
    }).toList();

    final total = rows.fold<double>(
      0.0,
      (sum, row) => sum + ((row['amount'] as num? ?? 0).toDouble()),
    );

    return {
      'payment_group_id': paymentGroupId,
      'customer_name': first['customer_name'] as String? ?? 'Customer',
      'cashier_name': first['cashier_name'] as String? ?? 'Unknown Cashier',
      'received_at': first['received_at'] as String?,
      'note': first['note'] as String?,
      'total_amount': total,
      'items': items,
    };
  }
}
