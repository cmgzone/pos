import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/products/data/product_provider.dart';
import 'package:pos_app/features/products/presentation/product_form_screen.dart';

void main() {
  Future<void> pumpProductForm(
    WidgetTester tester, {
    Map<String, dynamic>? product,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) async => <Map<String, dynamic>>[],
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: ProductFormScreen(product: product),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('applies a conversion preset and refreshes the storage preview', (
    tester,
  ) async {
    await pumpProductForm(tester);

    expect(
      find.text('This product uses pcs for selling, stocking, and purchases.'),
      findsOneWidget,
    );
    expect(find.text('Current stock will be saved as 0 pcs.'), findsOneWidget);
    expect(find.text('Low-stock alert will trigger at 5 pcs.'), findsOneWidget);

    await tester.ensureVisible(find.text('1 kg = 1000 g').first);
    await tester.tap(find.text('1 kg = 1000 g').first);
    await tester.pumpAndSettle();

    expect(find.text('Selling in kg, stocking in g'), findsOneWidget);
    expect(
      find.text(
        'Stock is stored in g. Price is entered per kg. Purchases are received in kg.',
      ),
      findsOneWidget,
    );
    expect(find.text('Current stock will be saved as 0 g.'), findsOneWidget);
    expect(find.text('Low-stock alert will trigger at 5 g.'), findsOneWidget);
    expect(find.text('Current Stock (g)'), findsOneWidget);
    expect(find.text('Low Stock Alert (g)'), findsOneWidget);
    expect(find.text('Selling Price per kg *'), findsOneWidget);
  });

  testWidgets('loads saved conversion settings when editing a product', (
    tester,
  ) async {
    await pumpProductForm(
      tester,
      product: <String, dynamic>{
        'id': 'product-1',
        'name': 'Sugar',
        'price': 12.0,
        'cost': 0.006,
        'stock': 2500.0,
        'low_stock': 500.0,
        'unit': 'kg',
        'sale_unit': 'kg',
        'stock_unit': 'g',
        'sale_to_stock_factor': 1000.0,
        'purchase_unit': 'g',
        'purchase_to_stock_factor': 1.0,
      },
    );

    expect(find.text('Edit Product'), findsOneWidget);
    expect(find.text('Selling in kg, stocking in g'), findsOneWidget);
    expect(
      find.text(
        'Stock is stored in g. Price is entered per kg. Purchases are received in g.',
      ),
      findsOneWidget,
    );
    expect(find.text('1 g = 1 g'), findsOneWidget);
    expect(find.text('Current stock will be saved as 2500 g.'), findsOneWidget);
    expect(find.text('Low-stock alert will trigger at 500 g.'), findsOneWidget);
    expect(find.text('Current Stock (g)'), findsOneWidget);
    expect(find.text('Low Stock Alert (g)'), findsOneWidget);
    expect(find.text('Selling Price per kg *'), findsOneWidget);
  });
}
