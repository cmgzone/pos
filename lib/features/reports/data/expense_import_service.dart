import '../../../core/data/cloud_spreadsheet_import_planner.dart';
import '../../../core/data/spreadsheet_import_reader.dart';
import 'expense_repository.dart';

class ExpenseImportResult {
  final int imported;
  final int categoriesCreated;
  final int skipped;
  final List<String> errors;
  final String? fileName;

  const ExpenseImportResult({
    required this.imported,
    required this.categoriesCreated,
    required this.skipped,
    required this.errors,
    this.fileName,
  });
}

class ExpenseImportService {
  static const columnAliases = {
    'title': [
      'expense',
      'expense_title',
      'description',
      'details',
      'item',
      'name',
    ],
    'amount': ['total', 'cost', 'value', 'paid', 'expense_amount'],
    'date': ['incurred_on', 'expense_date', 'paid_on', 'transaction_date'],
    'category': ['category_name', 'type', 'expense_type'],
    'note': ['notes', 'remarks', 'comment'],
  };
  static const _titleKeys = [
    'title',
    'expense',
    'expense_title',
    'description',
  ];
  static const _amountKeys = ['amount', 'total', 'cost'];
  static const _dateKeys = ['date', 'incurred_on', 'expense_date', 'paid_on'];
  static const _categoryKeys = ['category', 'category_name'];

  static Future<ExpenseImportResult?> pickAndImportExpenses({
    Future<bool> Function(SpreadsheetImportPlan plan)? confirmPlan,
  }) async {
    final file = await SpreadsheetImportReader.pickRows(
      dialogTitle: 'Import Expenses from Excel or CSV',
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

  static Future<ExpenseImportResult> importRows(
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
      importType: 'expenses',
      importLabel: 'expenses',
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
      requiredAll: const ['title', 'amount'],
      importLabel: 'expenses',
    );
  }

  static void _validatePlan(SpreadsheetImportPlan plan) {
    if (!SpreadsheetImportReader.hasAnyHeader(plan.headers, _titleKeys) ||
        !SpreadsheetImportReader.hasAnyHeader(plan.headers, _amountKeys)) {
      throw Exception(
        'Add expense title and amount columns before importing expenses.',
      );
    }
  }

  static Future<ExpenseImportResult> importPlan(
    SpreadsheetImportPlan plan,
  ) async {
    final headers = plan.headers;
    final categoryCache = await _categoryCache();
    var imported = 0;
    var skipped = 0;
    var categoriesCreated = 0;
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
        final categoryResult = await _resolveCategory(row, categoryCache);
        if (categoryResult.created) {
          categoriesCreated += 1;
        }
        await _importExpenseRow(row, categoryResult.category);
        imported += 1;
      } catch (error) {
        skipped += 1;
        if (errors.length < 8) {
          errors.add(
            'Row ${index + 1}: ${error.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }
    }

    return ExpenseImportResult(
      imported: imported,
      categoriesCreated: categoriesCreated,
      skipped: skipped,
      errors: errors,
      fileName: plan.fileName,
    );
  }

  static Future<void> _importExpenseRow(
    Map<String, String> row,
    _ExpenseCategoryMatch? category,
  ) async {
    final title = SpreadsheetImportReader.readText(row, _titleKeys);
    if (title == null) {
      throw Exception('Expense title is required.');
    }

    final amount = SpreadsheetImportReader.readMoney(row, _amountKeys);
    if (amount == null || amount <= 0) {
      throw Exception('Expense amount must be greater than zero.');
    }

    final incurredOn =
        SpreadsheetImportReader.readDate(row, _dateKeys) ?? DateTime.now();
    await ExpenseRepository.createExpense(
      title: title,
      amount: amount,
      incurredOn: incurredOn.toIso8601String(),
      categoryId: category?.id,
      categoryName: category?.name,
      note: SpreadsheetImportReader.readText(row, ['note', 'notes']),
    );
  }

  static Future<Map<String, _ExpenseCategoryMatch>> _categoryCache() async {
    final categories = await ExpenseRepository.getCategories();
    return {
      for (final category in categories)
        (category['name'] as String? ?? '')
            .trim()
            .toLowerCase(): _ExpenseCategoryMatch(
          id: category['id'] as String,
          name: category['name'] as String? ?? 'Expense',
        ),
    };
  }

  static Future<_CategoryResolveResult> _resolveCategory(
    Map<String, String> row,
    Map<String, _ExpenseCategoryMatch> categoryCache,
  ) async {
    final categoryName = SpreadsheetImportReader.readText(row, _categoryKeys);
    if (categoryName == null) {
      return const _CategoryResolveResult(null, created: false);
    }

    final key = categoryName.trim().toLowerCase();
    final existing = categoryCache[key];
    if (existing != null) {
      return _CategoryResolveResult(existing, created: false);
    }

    final id = await ExpenseRepository.createCategory(name: categoryName);
    final category = _ExpenseCategoryMatch(id: id, name: categoryName);
    categoryCache[key] = category;
    return _CategoryResolveResult(category, created: true);
  }
}

class _ExpenseCategoryMatch {
  final String id;
  final String name;

  const _ExpenseCategoryMatch({required this.id, required this.name});
}

class _CategoryResolveResult {
  final _ExpenseCategoryMatch? category;
  final bool created;

  const _CategoryResolveResult(this.category, {required this.created});
}
