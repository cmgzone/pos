import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/unit_utils.dart';

class CartItem {
  final String productId;
  final String productName;
  final double unitPrice;
  final double cost;
  final double maxStock;
  final double stockOnHand;
  final double saleToStockFactor;
  final String unit;
  final String stockUnit;
  final String lineType;
  final String? serviceOrderId;
  final String? serviceTemplateId;
  final String? variantId;
  final String? variantName;
  final bool tracksStock;
  int get precision => UnitUtils.allowsDecimal(unit) ? 3 : 0;
  double quantity;

  /// Unique key used for cart deduplication. Combines productId + variantId
  /// so that different variants of the same product can coexist in the cart.
  String get cartKey =>
      variantId != null ? '${productId}_$variantId' : productId;

  CartItem({
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.cost,
    required this.maxStock,
    required this.stockOnHand,
    required this.saleToStockFactor,
    required this.unit,
    required this.stockUnit,
    this.lineType = 'product',
    this.serviceOrderId,
    this.serviceTemplateId,
    this.variantId,
    this.variantName,
    this.tracksStock = true,
    this.quantity = 1,
  });

  double get total => unitPrice * quantity;
  double get profit => (unitPrice - cost) * quantity;
  double get quantityInStockUnit => quantity * saleToStockFactor;
  bool get usesConversion => unit != stockUnit;
  bool get isService => lineType == 'service';

  Map<String, dynamic> toSaleItem() => {
    'line_type': lineType,
    'product_id': productId,
    'product_name': productName,
    'unit_price': unitPrice,
    'unit_cost': cost,
    'quantity': quantity,
    'unit': unit,
    'sale_to_stock_factor': saleToStockFactor,
    'stock_unit': stockUnit,
    'track_stock': tracksStock ? 1 : 0,
    'service_order_id': serviceOrderId,
    'service_id': serviceTemplateId,
    'variant_id': variantId,
  };

  Map<String, dynamic> toHeldItem() => {
    'line_type': lineType,
    'product_id': productId,
    'product_name': productName,
    'unit_price': unitPrice,
    'cost': cost,
    'max_stock': maxStock,
    'stock_on_hand': stockOnHand,
    'sale_to_stock_factor': saleToStockFactor,
    'quantity': quantity,
    'unit': unit,
    'stock_unit': stockUnit,
    'track_stock': tracksStock ? 1 : 0,
    'service_order_id': serviceOrderId,
    'service_id': serviceTemplateId,
    'variant_id': variantId,
    'variant_name': variantName,
  };

  Map<String, dynamic> toQuotationItem() => {
    'product_id': productId,
    'variant_id': variantId,
    'product_name': productName,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'discount': 0,
    'tax': 0,
  };

  factory CartItem.fromHeldItem(Map<String, dynamic> row) {
    return CartItem(
      productId: row['product_id'] as String? ?? '',
      productName: row['product_name'] as String? ?? '',
      unitPrice: _asDouble(row['unit_price']),
      cost: _asDouble(row['cost']),
      maxStock: _asDouble(row['max_stock']),
      stockOnHand: _asDouble(row['stock_on_hand']),
      saleToStockFactor: _asDouble(row['sale_to_stock_factor'], fallback: 1),
      unit: row['unit'] as String? ?? 'pcs',
      stockUnit:
          row['stock_unit'] as String? ?? row['unit'] as String? ?? 'pcs',
      lineType: row['line_type'] as String? ?? 'product',
      serviceOrderId: row['service_order_id'] as String?,
      serviceTemplateId: row['service_id'] as String?,
      variantId: row['variant_id'] as String?,
      variantName: row['variant_name'] as String?,
      tracksStock: _asBool(row['track_stock']),
      quantity: _asDouble(row['quantity'], fallback: 1),
    );
  }

  static double _asDouble(Object? value, {double fallback = 0}) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _asBool(Object? value, {bool fallback = true}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) {
        return fallback;
      }
      return normalized != '0' &&
          normalized != 'false' &&
          normalized != 'no' &&
          normalized != 'off';
    }
    return fallback;
  }
}

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  double _roundQuantity(double value) {
    return double.parse(value.toStringAsFixed(3));
  }

  /// Add a product to the cart, optionally selecting a specific [variant].
  /// When a variant is supplied its price, cost, and stock override the parent.
  bool addProduct(
    Map<String, dynamic> product, {
    Map<String, dynamic>? variant,
  }) {
    final unit = UnitUtils.saleUnitForProduct(product);
    final stockUnit = UnitUtils.stockUnitForProduct(product);
    final saleToStockFactor = UnitUtils.saleToStockFactor(product);
    final tracksStock = UnitUtils.tracksStock(product);
    final step = UnitUtils.step(unit);

    // Resolve stock and pricing from variant or parent product
    final stockSource = variant ?? product;
    final stock = (stockSource['stock'] as num? ?? 0).toDouble();
    final availableSaleQuantity = (() {
      if (!tracksStock) return 999999.0;
      if (saleToStockFactor <= 0) return stock;
      return _roundQuantity(stock / saleToStockFactor);
    })();
    final rawCost = (stockSource['cost'] as num? ?? 0).toDouble();
    final costPerSaleUnit = rawCost * saleToStockFactor;
    final price = variant != null
        ? (variant['price'] as num?)?.toDouble() ??
              (product['price'] as num).toDouble()
        : (product['price'] as num).toDouble();

    final variantId = variant?['id'] as String?;
    final variantName = variant?['name'] as String?;
    final cartKey = variantId != null
        ? '${product['id']}_$variantId'
        : product['id'] as String;

    if (tracksStock && (stock <= 0 || availableSaleQuantity <= 0)) {
      return false;
    }

    final existing = state.where((item) => item.cartKey == cartKey).toList();
    if (existing.isNotEmpty) {
      final item = existing.first;
      if (item.tracksStock && item.quantity + 0.001 >= item.maxStock) {
        return false;
      }
      final nextQuantity = _roundQuantity(item.quantity + step);
      item.quantity = item.tracksStock && nextQuantity > item.maxStock
          ? item.maxStock
          : nextQuantity;
      state = [...state];
      return true;
    } else {
      final initialQuantity = _roundQuantity(
        availableSaleQuantity >= step ? step : availableSaleQuantity,
      );
      state = [
        ...state,
        CartItem(
          productId: product['id'] as String,
          productName: product['name'] as String,
          unitPrice: price,
          cost: costPerSaleUnit,
          maxStock: availableSaleQuantity,
          stockOnHand: stock,
          saleToStockFactor: saleToStockFactor,
          unit: unit,
          stockUnit: stockUnit,
          variantId: variantId,
          variantName: variantName,
          tracksStock: tracksStock,
          quantity: initialQuantity,
        ),
      ];
      return true;
    }
  }

  bool addService({
    required String serviceOrderId,
    required String serviceId,
    required String serviceName,
    required double price,
  }) {
    final existing = state
        .where((item) => item.serviceOrderId == serviceOrderId)
        .toList();
    if (existing.isNotEmpty) {
      return false;
    }

    state = [
      ...state,
      CartItem(
        productId: 'service:$serviceOrderId',
        productName: serviceName,
        unitPrice: price,
        cost: 0,
        maxStock: 999999,
        stockOnHand: 999999,
        saleToStockFactor: 1,
        unit: 'job',
        stockUnit: 'job',
        lineType: 'service',
        serviceOrderId: serviceOrderId,
        serviceTemplateId: serviceId,
        tracksStock: false,
      ),
    ];
    return true;
  }

  /// [cartKey] is either a plain productId or the composite 'productId_variantId'.
  void removeProduct(String cartKey) {
    state = state.where((item) => item.cartKey != cartKey).toList();
  }

  bool incrementQuantity(String cartKey) {
    final item = state.firstWhere((i) => i.cartKey == cartKey);
    if (item.isService) return false;
    if (item.tracksStock && item.quantity + 0.001 >= item.maxStock) {
      return false;
    }
    final nextQuantity = _roundQuantity(
      item.quantity + UnitUtils.step(item.unit),
    );
    item.quantity = item.tracksStock && nextQuantity > item.maxStock
        ? item.maxStock
        : nextQuantity;
    state = [...state];
    return true;
  }

  void decrementQuantity(String cartKey) {
    final item = state.firstWhere((i) => i.cartKey == cartKey);
    if (item.isService) {
      removeProduct(cartKey);
      return;
    }
    final nextQuantity = _roundQuantity(
      item.quantity - UnitUtils.step(item.unit),
    );
    if (nextQuantity > 0) {
      item.quantity = nextQuantity;
      state = [...state];
    } else {
      removeProduct(cartKey);
    }
  }

  bool setQuantity(String cartKey, double quantity) {
    final item = state.firstWhere((i) => i.cartKey == cartKey);
    if (item.isService) {
      item.quantity = 1;
      state = [...state];
      return quantity == 1;
    }
    if (quantity <= 0) return false;
    if (item.tracksStock && quantity - item.maxStock > 0.001) return false;
    item.quantity = _roundQuantity(quantity);
    state = [...state];
    return true;
  }

  void clear() {
    state = [];
  }

  void restoreHeldItems(List<Map<String, dynamic>> heldItems) {
    state = heldItems.map(CartItem.fromHeldItem).toList();
  }

  /// Restore quotation line items into the cart so they can be paid for as a
  /// normal sale. Items arrive already stock-validated by
  /// [QuotationRepository.loadForConvert].
  void restoreQuotationItems(List<Map<String, dynamic>> items) {
    final restored = <CartItem>[];
    for (final item in items) {
      final lineType = item['line_type'] as String? ?? 'product';
      if (lineType == 'service') {
        // Quotations currently only capture product lines; skip service rows.
        continue;
      }
      restored.add(
        CartItem(
          productId: item['product_id'] as String? ?? '',
          productName: item['product_name'] as String? ?? 'Product',
          unitPrice: _asDouble(item['unit_price']),
          cost: _asDouble(item['cost']),
          maxStock: _asDouble(item['max_stock'], fallback: 999999),
          stockOnHand: _asDouble(item['stock_on_hand']),
          saleToStockFactor: _asDouble(
            item['sale_to_stock_factor'],
            fallback: 1,
          ),
          unit: item['unit'] as String? ?? 'pcs',
          stockUnit:
              item['stock_unit'] as String? ?? item['unit'] as String? ?? 'pcs',
          variantId: item['variant_id'] as String?,
          variantName: item['variant_name'] as String?,
          tracksStock: _asBool(item['track_stock']),
          quantity: _asDouble(item['quantity'], fallback: 1),
        ),
      );
    }
    state = restored;
  }

  static double _asDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _asBool(Object? value, {bool fallback = true}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final n = value.trim().toLowerCase();
      if (n.isEmpty) return fallback;
      return n != '0' && n != 'false' && n != 'no' && n != 'off';
    }
    return fallback;
  }

  double get subtotal =>
      state.fold<double>(0.0, (sum, item) => sum + item.total);
}

final cartProvider = NotifierProvider<CartNotifier, List<CartItem>>(
  CartNotifier.new,
);

final taxRateProvider = Provider<double>((ref) => ShopSettings.taxRate / 100);
final discountProvider = StateProvider<double>((ref) => 0.0);

final cartSubtotalProvider = Provider<double>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.fold<double>(0.0, (sum, item) => sum + item.total);
});

final cartTaxProvider = Provider<double>((ref) {
  final subtotal = ref.watch(cartSubtotalProvider);
  final taxRate = ref.watch(taxRateProvider);
  return subtotal * taxRate;
});

final cartTotalProvider = Provider<double>((ref) {
  final subtotal = ref.watch(cartSubtotalProvider);
  final tax = ref.watch(cartTaxProvider);
  final discount = ref.watch(discountProvider);
  return subtotal + tax - discount;
});

final cartProfitProvider = Provider<double>((ref) {
  final cart = ref.watch(cartProvider);
  final discount = ref.watch(discountProvider);
  final profitItems = cart.fold<double>(0.0, (sum, item) => sum + item.profit);
  return profitItems - discount;
});
