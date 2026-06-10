import '../../../core/data/cloud_spreadsheet_import_planner.dart';
import '../../../core/data/spreadsheet_import_reader.dart';
import '../../../core/services/database_service.dart';
import 'customer_repository.dart';

class CustomerImportResult {
  final int created;
  final int updated;
  final int skipped;
  final List<String> errors;
  final String? fileName;

  const CustomerImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.errors,
    this.fileName,
  });

  int get imported => created + updated;
}

class CustomerImportService {
  static const columnAliases = {
    'customer_id': ['id', 'customer id', 'client_id'],
    'name': [
      'customer_name',
      'client',
      'client_name',
      'contact_name',
      'full_name',
    ],
    'phone': ['customer_phone', 'mobile', 'phone_number', 'tel', 'telephone'],
    'email': ['customer_email', 'email_address', 'mail'],
  };
  static const _nameKeys = ['name', 'customer_name', 'client'];
  static const _phoneKeys = ['phone', 'customer_phone', 'mobile'];
  static const _emailKeys = ['email', 'customer_email'];

  static Future<CustomerImportResult?> pickAndImportCustomers({
    Future<bool> Function(SpreadsheetImportPlan plan)? confirmPlan,
  }) async {
    final file = await SpreadsheetImportReader.pickRows(
      dialogTitle: 'Import Customers from Excel or CSV',
    );
    if (file == null) {
      return null;
    }
    final plan = await buildPlanWithCloud(file.rows, fileName: file.fileName);
    if (confirmPlan != null && !await confirmPlan(plan)) {
      return null;
    }
    return importPlan(plan);
  }

  static Future<CustomerImportResult> importRows(
    List<List<String>> rows, {
    String? fileName,
  }) async {
    return importPlan(buildPlan(rows, fileName: fileName));
  }

  static SpreadsheetImportPlan buildPlan(
    List<List<String>> rows, {
    String? fileName,
  }) {
    final plan = _buildRawPlan(rows, fileName: fileName);
    _validatePlan(plan);
    return plan;
  }

  static Future<SpreadsheetImportPlan> buildPlanWithCloud(
    List<List<String>> rows, {
    String? fileName,
  }) async {
    final plan = await CloudSpreadsheetImportPlanner.buildPlan(
      rows: rows,
      fileName: fileName,
      importType: 'customers',
      importLabel: 'customers',
      columnAliases: columnAliases,
      localPlanBuilder: () => _buildRawPlan(rows, fileName: fileName),
    );
    _validatePlan(plan);
    return plan;
  }

  static SpreadsheetImportPlan _buildRawPlan(
    List<List<String>> rows, {
    String? fileName,
  }) {
    return SpreadsheetImportReader.buildPlan(
      rows: rows,
      fileName: fileName,
      columnAliases: columnAliases,
      requiredAny: const ['name'],
      importLabel: 'customers',
    );
  }

  static void _validatePlan(SpreadsheetImportPlan plan) {
    if (!SpreadsheetImportReader.hasAnyHeader(plan.headers, _nameKeys)) {
      throw Exception('Add a customer name column before importing customers.');
    }
  }

  static Future<CustomerImportResult> importPlan(
    SpreadsheetImportPlan plan,
  ) async {
    final headers = plan.headers;
    var created = 0;
    var updated = 0;
    var skipped = 0;
    final errors = <String>[];

    for (
      var index = plan.headerIndex + 1;
      index < plan.rows.length;
      index += 1
    ) {
      final sourceRow = plan.rows[index];
      if (sourceRow.every((cell) => cell.trim().isEmpty)) {
        continue;
      }

      try {
        final row = SpreadsheetImportReader.rowMap(headers, sourceRow);
        final result = await _importCustomerRow(row);
        if (result.created) {
          created += 1;
        } else if (result.updated) {
          updated += 1;
        }
      } catch (error) {
        skipped += 1;
        if (errors.length < 8) {
          errors.add(
            'Row ${index + 1}: ${error.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }
    }

    return CustomerImportResult(
      created: created,
      updated: updated,
      skipped: skipped,
      errors: errors,
      fileName: plan.fileName,
    );
  }

  static Future<_CustomerRowImportResult> _importCustomerRow(
    Map<String, String> row,
  ) async {
    final name = SpreadsheetImportReader.readText(row, _nameKeys);
    if (name == null) {
      throw Exception('Customer name is required.');
    }
    final phone = SpreadsheetImportReader.readText(row, _phoneKeys);
    final email = SpreadsheetImportReader.readText(row, _emailKeys);
    final existing = await _findExistingCustomer(row);

    if (existing == null) {
      await CustomerRepository.create(name: name, phone: phone, email: email);
      return const _CustomerRowImportResult(created: true);
    }

    await CustomerRepository.update(
      id: existing['id'] as String,
      name: name,
      phone: phone ?? existing['phone'] as String?,
      email: email ?? existing['email'] as String?,
    );
    return const _CustomerRowImportResult(updated: true);
  }

  static Future<Map<String, dynamic>?> _findExistingCustomer(
    Map<String, String> row,
  ) async {
    final customerId = SpreadsheetImportReader.readText(row, ['customer_id']);
    if (customerId != null) {
      final customer = await CustomerRepository.getById(customerId);
      if (customer != null) return customer;
    }

    final phone = SpreadsheetImportReader.readText(row, _phoneKeys);
    if (phone != null) {
      final rows = await _queryCustomer(
        'LOWER(TRIM(phone)) = ?',
        phone.trim().toLowerCase(),
      );
      if (rows.isNotEmpty) return rows.first;
    }

    final email = SpreadsheetImportReader.readText(row, _emailKeys);
    if (email != null) {
      final rows = await _queryCustomer(
        'LOWER(TRIM(email)) = ?',
        email.trim().toLowerCase(),
      );
      if (rows.isNotEmpty) return rows.first;
    }

    final name = SpreadsheetImportReader.readText(row, _nameKeys);
    if (name != null) {
      final rows = await _queryCustomer(
        'LOWER(TRIM(name)) = ?',
        name.trim().toLowerCase(),
      );
      if (rows.isNotEmpty) return rows.first;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _queryCustomer(
    String condition,
    String value,
  ) {
    return DatabaseService.rawQuery(
      '''
      SELECT *
      FROM customers
      WHERE $condition
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [value, DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );
  }
}

class _CustomerRowImportResult {
  final bool created;
  final bool updated;

  const _CustomerRowImportResult({this.created = false, this.updated = false});
}
