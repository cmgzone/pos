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

  test('messy Excel product price sheet headers map to product fields', () {
    final plan = ProductImportService.buildPlan([
      [
        'Product ID',
        'SKU',
        'Product Name',
        'Category',
        'Unit',
        'Cost Price (KES)',
        'Selling Price (KES)',
        'Stock Qty',
        'Reorder Level',
        'Barcode',
      ],
      [
        'P0001',
        'SKU-0001',
        'Bottled Water 500ml',
        'Beverages',
        'Each',
        '190',
        '240',
        '106',
        '30',
        '616100000001',
      ],
    ], fileName: 'product_categories_price_test_data.xlsx');

    expect(
      plan.headers,
      containsAll([
        'product_id',
        'sku',
        'name',
        'category',
        'unit',
        'cost',
        'price',
        'stock',
        'low_stock',
        'barcode',
      ]),
    );

    final row = SpreadsheetImportReader.rowMap(plan.headers, plan.rows[1]);
    expect(row['product_id'], 'P0001');
    expect(row['name'], 'Bottled Water 500ml');
    expect(row['cost'], '190');
    expect(row['price'], '240');
    expect(row['stock'], '106');
    expect(row['low_stock'], '30');
    expect(row['barcode'], '616100000001');
  });
}
