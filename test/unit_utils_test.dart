import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/utils/unit_utils.dart';

void main() {
  group('UnitUtils conversion helpers', () {
    test('detects compatible unit families', () {
      expect(UnitUtils.family('kg'), 'weight');
      expect(UnitUtils.family('ml'), 'volume');
      expect(UnitUtils.family('cm'), 'length');
      expect(UnitUtils.family('pack'), 'pack');
    });

    test('converts between related units', () {
      expect(UnitUtils.conversionFactor('kg', 'g'), 1000);
      expect(UnitUtils.conversionFactor('g', 'kg'), 0.001);
      expect(UnitUtils.conversionFactor('litre', 'ml'), 1000);
      expect(UnitUtils.conversionFactor('m', 'cm'), 100);
      expect(UnitUtils.convertQuantity(2, 'kg', 'g'), 2000);
      expect(UnitUtils.convertQuantity(500, 'ml', 'litre'), 0.5);
      expect(UnitUtils.convertQuantity(3, 'm', 'cm'), 300);
    });

    test('blocks unsupported cross-family conversions', () {
      expect(UnitUtils.canConvert('kg', 'ml'), isFalse);
      expect(UnitUtils.conversionFactor('pack', 'box'), isNull);
      expect(UnitUtils.convertQuantity(1, 'kg', 'ml'), isNull);
    });

    test('resolves product conversion fields with legacy fallback', () {
      final legacyProduct = <String, dynamic>{'unit': 'kg'};

      expect(UnitUtils.stockUnitForProduct(legacyProduct), 'kg');
      expect(UnitUtils.saleUnitForProduct(legacyProduct), 'kg');
      expect(UnitUtils.purchaseUnitForProduct(legacyProduct), 'kg');
      expect(UnitUtils.saleToStockFactor(legacyProduct), 1);
      expect(UnitUtils.purchaseToStockFactor(legacyProduct), 1);
      expect(UnitUtils.usesConversion(legacyProduct), isFalse);
    });

    test('resolves explicit product conversion config', () {
      final product = <String, dynamic>{
        'unit': 'g',
        'stock_unit': 'g',
        'sale_unit': 'kg',
        'sale_to_stock_factor': 1000,
        'purchase_unit': 'kg',
        'purchase_to_stock_factor': 1000,
      };

      expect(UnitUtils.usesConversion(product), isTrue);
      expect(UnitUtils.saleToStockFactor(product), 1000);
      expect(UnitUtils.purchaseToStockFactor(product), 1000);
      expect(UnitUtils.convertSaleQuantityToStock(product, 1.5), 1500);
      expect(UnitUtils.convertPurchaseQuantityToStock(product, 2), 2000);
    });
  });
}
