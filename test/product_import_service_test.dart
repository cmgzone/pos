import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/data/spreadsheet_import_reader.dart';
import 'package:pos_app/features/products/data/product_import_service.dart';

void main() {
  test('canonical product description header maps to description', () {
    final plan = ProductImportService.buildPlan([
      ['name', 'description', 'price', 'show_online', 'is_featured'],
      ['Milk 500ml', 'Fresh packet milk', '60', 'yes', 'true'],
    ], fileName: 'products.csv');

    expect(plan.headers, [
      'name',
      'description',
      'price',
      'show_online',
      'is_featured',
    ]);

    final row = SpreadsheetImportReader.rowMap(plan.headers, plan.rows[1]);
    expect(row['name'], 'Milk 500ml');
    expect(row['description'], 'Fresh packet milk');
    expect(row['show_online'], 'yes');
    expect(row['is_featured'], 'true');
  });

  test('TSV product files can be read into rows', () {
    final rows = SpreadsheetImportReader.readTsvRows(
      Uint8List.fromList(utf8.encode('name\tprice\nBread\t55\n')),
    );

    expect(rows, [
      ['name', 'price'],
      ['Bread', '55'],
    ]);
  });
}
