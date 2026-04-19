class UnitUtils {
  static const String defaultUnit = 'pcs';
  static const String _weightFamily = 'weight';
  static const String _volumeFamily = 'volume';
  static const String _lengthFamily = 'length';

  static const List<String> supportedUnits = <String>[
    'pcs',
    'kg',
    'g',
    'litre',
    'ml',
    'pack',
    'box',
    'bottle',
    'dozen',
    'm',
    'cm',
  ];

  static String normalize(String? unit) {
    final value = (unit ?? '').trim().toLowerCase();
    return supportedUnits.contains(value) ? value : defaultUnit;
  }

  static String family(String? unit) {
    switch (normalize(unit)) {
      case 'kg':
      case 'g':
        return _weightFamily;
      case 'litre':
      case 'ml':
        return _volumeFamily;
      case 'm':
      case 'cm':
        return _lengthFamily;
      default:
        return normalize(unit);
    }
  }

  static List<String> relatedUnits(String? unit) {
    switch (family(unit)) {
      case _weightFamily:
        return const <String>['kg', 'g'];
      case _volumeFamily:
        return const <String>['litre', 'ml'];
      case _lengthFamily:
        return const <String>['m', 'cm'];
      default:
        return <String>[normalize(unit)];
    }
  }

  static bool canConvert(String? fromUnit, String? toUnit) {
    return family(fromUnit) == family(toUnit);
  }

  static double? conversionFactor(String? fromUnit, String? toUnit) {
    final from = normalize(fromUnit);
    final to = normalize(toUnit);
    if (from == to) return 1.0;
    if (!canConvert(from, to)) return null;
    final fromCanonical = _toCanonicalFactor(from);
    final toCanonical = _toCanonicalFactor(to);
    return fromCanonical / toCanonical;
  }

  static double? convertQuantity(num? value, String? fromUnit, String? toUnit) {
    final factor = conversionFactor(fromUnit, toUnit);
    if (factor == null) return null;
    return (value ?? 0).toDouble() * factor;
  }

  static String stockUnitForProduct(Map<String, dynamic> product) {
    return normalize(
      product['stock_unit'] as String? ?? product['unit'] as String?,
    );
  }

  static String saleUnitForProduct(Map<String, dynamic> product) {
    return normalize(
      product['sale_unit'] as String? ??
          product['unit'] as String? ??
          product['stock_unit'] as String?,
    );
  }

  static String purchaseUnitForProduct(Map<String, dynamic> product) {
    return normalize(
      product['purchase_unit'] as String? ??
          product['unit'] as String? ??
          product['stock_unit'] as String?,
    );
  }

  static double saleToStockFactor(Map<String, dynamic> product) {
    return _resolveProductFactor(
      rawFactor: product['sale_to_stock_factor'],
      fromUnit: saleUnitForProduct(product),
      toUnit: stockUnitForProduct(product),
    );
  }

  static double purchaseToStockFactor(Map<String, dynamic> product) {
    return _resolveProductFactor(
      rawFactor: product['purchase_to_stock_factor'],
      fromUnit: purchaseUnitForProduct(product),
      toUnit: stockUnitForProduct(product),
    );
  }

  static bool usesConversion(Map<String, dynamic> product) {
    final stockUnit = stockUnitForProduct(product);
    return saleUnitForProduct(product) != stockUnit ||
        purchaseUnitForProduct(product) != stockUnit;
  }

  static double? convertSaleQuantityToStock(
    Map<String, dynamic> product,
    num? saleQuantity,
  ) {
    return (saleQuantity ?? 0).toDouble() * saleToStockFactor(product);
  }

  static double? convertPurchaseQuantityToStock(
    Map<String, dynamic> product,
    num? purchaseQuantity,
  ) {
    return (purchaseQuantity ?? 0).toDouble() * purchaseToStockFactor(product);
  }

  static String label(String? unit) {
    switch (normalize(unit)) {
      case 'pcs':
        return 'pcs';
      case 'kg':
        return 'kg';
      case 'g':
        return 'g';
      case 'litre':
        return 'litre';
      case 'ml':
        return 'ml';
      case 'pack':
        return 'pack';
      case 'box':
        return 'box';
      case 'bottle':
        return 'bottle';
      case 'dozen':
        return 'dozen';
      case 'm':
        return 'm';
      case 'cm':
        return 'cm';
      default:
        return defaultUnit;
    }
  }

  static String priceLabel(String? unit) {
    final normalized = normalize(unit);
    return normalized == defaultUnit ? 'each' : 'per ${label(normalized)}';
  }

  static double step(String? unit) {
    switch (normalize(unit)) {
      case 'kg':
      case 'litre':
        return 0.25;
      case 'g':
      case 'ml':
        return 50.0;
      case 'm':
        return 0.5;
      case 'cm':
        return 10.0;
      default:
        return 1.0;
    }
  }

  static bool allowsDecimal(String? unit) {
    return step(unit) % 1 != 0;
  }

  static String formatQuantity(num? value, {int maxDecimals = 3}) {
    final quantity = (value ?? 0).toDouble();
    final fixed = quantity.toStringAsFixed(maxDecimals);
    return fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
        : fixed;
  }

  static String formatWithUnit(num? value, String? unit) {
    return '${formatQuantity(value)} ${label(unit)}';
  }

  static double _resolveProductFactor({
    required Object? rawFactor,
    required String fromUnit,
    required String toUnit,
  }) {
    final parsed = switch (rawFactor) {
      num value => value.toDouble(),
      String value => double.tryParse(value),
      _ => null,
    };

    if (parsed != null && parsed > 0) {
      return parsed;
    }

    return conversionFactor(fromUnit, toUnit) ?? 1.0;
  }

  static double _toCanonicalFactor(String unit) {
    switch (unit) {
      case 'kg':
      case 'litre':
        return 1000.0;
      case 'm':
        return 100.0;
      case 'g':
      case 'ml':
      case 'cm':
        return 1.0;
      default:
        return 1.0;
    }
  }
}
