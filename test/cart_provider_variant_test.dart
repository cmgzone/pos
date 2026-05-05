import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/features/sales/data/cart_provider.dart';

void main() {
  test('variant cart actions use cartKey so sibling variants stay isolated', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    const product = <String, dynamic>{
      'id': 'product-1',
      'name': 'T-Shirt',
      'price': 20.0,
      'cost': 8.0,
      'stock': 20.0,
      'unit': 'pcs',
      'stock_unit': 'pcs',
      'sale_unit': 'pcs',
      'sale_to_stock_factor': 1.0,
      'has_variants': 1,
    };
    const redVariant = <String, dynamic>{
      'id': 'variant-red',
      'name': 'Red',
      'price': 22.0,
      'cost': 9.0,
      'stock': 5.0,
    };
    const blueVariant = <String, dynamic>{
      'id': 'variant-blue',
      'name': 'Blue',
      'price': 24.0,
      'cost': 10.0,
      'stock': 7.0,
    };

    final notifier = container.read(cartProvider.notifier);
    expect(notifier.addProduct(product, variant: redVariant), isTrue);
    expect(notifier.addProduct(product, variant: blueVariant), isTrue);

    expect(container.read(cartProvider), hasLength(2));
    expect(notifier.incrementQuantity('product-1_variant-red'), isTrue);
    expect(notifier.setQuantity('product-1_variant-blue', 3), isTrue);
    notifier.decrementQuantity('product-1_variant-red');

    final items = container.read(cartProvider);
    final redItem = items.firstWhere((item) => item.variantId == 'variant-red');
    final blueItem = items.firstWhere(
      (item) => item.variantId == 'variant-blue',
    );

    expect(redItem.quantity, 1);
    expect(blueItem.quantity, 3);
  });
}
