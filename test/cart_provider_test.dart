import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/sales/data/cart_provider.dart';

void main() {
  group('CartNotifier unit conversion', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test(
      'adds a converted product in sale units while tracking stock units',
      () {
        final notifier = container.read(cartProvider.notifier);

        final added = notifier.addProduct({
          'id': 'prod-1',
          'name': 'Sugar',
          'price': 12.0,
          'cost': 0.006,
          'stock': 500.0,
          'unit': 'kg',
          'sale_unit': 'kg',
          'stock_unit': 'g',
          'sale_to_stock_factor': 1000.0,
        });

        expect(added, isTrue);

        final cart = container.read(cartProvider);
        expect(cart, hasLength(1));

        final item = cart.single;
        expect(item.unit, 'kg');
        expect(item.stockUnit, 'g');
        expect(item.maxStock, closeTo(0.5, 0.0001));
        expect(item.stockOnHand, 500.0);
        expect(item.quantity, closeTo(0.25, 0.0001));
        expect(item.quantityInStockUnit, closeTo(250.0, 0.001));
        expect(item.cost, closeTo(6.0, 0.0001));
        expect(item.usesConversion, isTrue);
        expect(item.toSaleItem(), containsPair('sale_to_stock_factor', 1000.0));
        expect(item.toSaleItem(), containsPair('stock_unit', 'g'));
      },
    );

    test('caps converted quantity at available sale quantity', () {
      final notifier = container.read(cartProvider.notifier);

      notifier.addProduct({
        'id': 'prod-2',
        'name': 'Cooking Oil',
        'price': 8.0,
        'cost': 0.004,
        'stock': 1500.0,
        'unit': 'litre',
        'sale_unit': 'litre',
        'stock_unit': 'ml',
        'sale_to_stock_factor': 1000.0,
      });

      expect(notifier.incrementQuantity('prod-2'), isTrue);
      expect(notifier.incrementQuantity('prod-2'), isTrue);
      expect(notifier.incrementQuantity('prod-2'), isTrue);
      expect(notifier.incrementQuantity('prod-2'), isTrue);
      expect(notifier.incrementQuantity('prod-2'), isTrue);
      expect(notifier.incrementQuantity('prod-2'), isFalse);

      final item = container.read(cartProvider).single;
      expect(item.quantity, closeTo(1.5, 0.0001));
      expect(notifier.setQuantity('prod-2', 1.6), isFalse);
      expect(notifier.setQuantity('prod-2', 1.5), isTrue);
    });

    test('keeps simple products on the legacy path', () {
      final notifier = container.read(cartProvider.notifier);

      final added = notifier.addProduct({
        'id': 'prod-3',
        'name': 'Pen',
        'price': 2.0,
        'cost': 1.0,
        'stock': 12.0,
        'unit': 'pcs',
      });

      expect(added, isTrue);
      final item = container.read(cartProvider).single;
      expect(item.unit, 'pcs');
      expect(item.stockUnit, 'pcs');
      expect(item.maxStock, 12.0);
      expect(item.quantity, 1.0);
      expect(item.cost, 1.0);
      expect(item.usesConversion, isFalse);
    });
  });
}
