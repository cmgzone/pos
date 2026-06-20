import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/data/spreadsheet_import_reader.dart';
import 'package:pos_app/features/sales/data/sale_import_service.dart';

void main() {
  test('sales import accepts canonical itemized sale headers', () {
    final plan = SaleImportService.buildPlan([
      ['date', 'product', 'quantity', 'unit_price', 'payment_type'],
      ['2026-06-20', 'Milk 500ml', '2', '60', 'Cash'],
    ], fileName: 'sales.csv');

    expect(plan.headers, [
      'date',
      'product',
      'quantity',
      'unit_price',
      'payment_type',
    ]);

    final row = SpreadsheetImportReader.rowMap(plan.headers, plan.rows[1]);
    expect(row['product'], 'Milk 500ml');
    expect(row['payment_type'], 'Cash');
  });

  test('shared TSV reader supports sales files', () {
    final rows = SpreadsheetImportReader.readTsvRows(
      Uint8List.fromList(utf8.encode('total\tpayment_type\n120\tM-Pesa\n')),
    );

    expect(rows, [
      ['total', 'payment_type'],
      ['120', 'M-Pesa'],
    ]);
  });
}
