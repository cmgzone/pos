import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
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
        'Margin %',
        'Stock Qty',
        'Reorder Level',
        'Stock Value (KES)',
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
        '',
        '106',
        '30',
        '25440',
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

  test('messy Excel product workbook bytes map to product fields', () {
    final book = xl.Excel.createExcel();
    final sheet = book['Products'];
    sheet.appendRow([
      xl.TextCellValue('Product ID'),
      xl.TextCellValue('SKU'),
      xl.TextCellValue('Product Name'),
      xl.TextCellValue('Category'),
      xl.TextCellValue('Unit'),
      xl.TextCellValue('Cost Price (KES)'),
      xl.TextCellValue('Selling Price (KES)'),
      xl.TextCellValue('Margin %'),
      xl.TextCellValue('Stock Qty'),
      xl.TextCellValue('Reorder Level'),
      xl.TextCellValue('Stock Value (KES)'),
      xl.TextCellValue('Barcode'),
    ]);
    sheet.appendRow([
      xl.TextCellValue('P0001'),
      xl.TextCellValue('SKU-0001'),
      xl.TextCellValue('Bottled Water 500ml'),
      xl.TextCellValue('Beverages'),
      xl.TextCellValue('Each'),
      xl.IntCellValue(190),
      xl.IntCellValue(240),
      null,
      xl.IntCellValue(106),
      xl.IntCellValue(30),
      xl.IntCellValue(25440),
      xl.TextCellValue('616100000001'),
    ]);

    final bytes = Uint8List.fromList(book.encode()!);
    final rows = SpreadsheetImportReader.readExcelRows(bytes);
    final preview = SpreadsheetImportReader.readExcelWorkbookText(bytes);
    final plan = ProductImportService.buildPlan(
      rows,
      fileName: 'product_categories_price_test_data.xlsx',
    );

    expect(preview, contains('Sheet: Products'));
    expect(preview, contains('Product Name'));
    expect(preview, contains('Bottled Water 500ml'));

    final row = SpreadsheetImportReader.rowMap(plan.headers, plan.rows[1]);
    expect(row['name'], 'Bottled Water 500ml');
    expect(row['cost'], '190');
    expect(row['price'], '240');
    expect(row['stock'], '106');
    expect(row['low_stock'], '30');
  });

  test('xlsx XML fallback reads workbook when style parsing fails', () {
    final bytes = _buildMinimalXlsxBytes();
    final rows = SpreadsheetImportReader.readExcelRows(bytes);
    final preview = SpreadsheetImportReader.readExcelWorkbookText(bytes);
    final plan = ProductImportService.buildPlan(
      rows,
      fileName: 'supplier-price-list.xlsx',
    );

    expect(preview, contains('Sheet: Products'));
    expect(preview, contains('Cooking Oil 1L'));

    final row = SpreadsheetImportReader.rowMap(plan.headers, plan.rows[1]);
    expect(row['name'], 'Cooking Oil 1L');
    expect(row['price'], '250');
    expect(row['stock'], '12');
  });
}

Uint8List _buildMinimalXlsxBytes() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('xl/workbook.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <x:sheets>
    <x:sheet name="Products" sheetId="1" r:id="rId1"/>
  </x:sheets>
</x:workbook>
'''),
    )
    ..addFile(
      ArchiveFile.string('xl/_rels/workbook.xml.rels', '''
<?xml version="1.0" encoding="utf-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
'''),
    )
    ..addFile(
      ArchiveFile.string('xl/worksheets/sheet1.xml', '''
<?xml version="1.0" encoding="utf-8"?>
<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <x:sheetData>
    <x:row r="1">
      <x:c r="A1" t="str"><x:v>Product Name</x:v></x:c>
      <x:c r="B1" t="str"><x:v>Selling Price (KES)</x:v></x:c>
      <x:c r="C1" t="str"><x:v>Stock Qty</x:v></x:c>
      <x:c r="D1" t="str"><x:v>Stock Value (KES)</x:v></x:c>
    </x:row>
    <x:row r="2">
      <x:c r="A2" t="str"><x:v>Cooking Oil 1L</x:v></x:c>
      <x:c r="B2"><x:v>250</x:v></x:c>
      <x:c r="C2"><x:v>12</x:v></x:c>
      <x:c r="D2"><x:v>3000</x:v></x:c>
    </x:row>
  </x:sheetData>
</x:worksheet>
'''),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
