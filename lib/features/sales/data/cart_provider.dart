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
  int get precision => UnitUtils.allowsDecimal(unit) ? 3 : 0;
  double quantity;

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
    this.quantity = 1,
  });

  double get total => unitPrice * quantity;
  double get profit => (unitPrice - cost) * quantity;
  double get quantityInStockUnit => quantity * saleToStockFactor;
  bool get usesConversion => unit != stockUnit;

  Map<String, dynamic> toSaleItem() => {
    'product_id': productId,
    'unit_price': unitPrice,
    'quantity': quantity,
    'unit': unit,
    'sale_to_stock_factor': saleToStockFactor,
    'stock_unit': stockUnit,
  };
}

class CartNotifier extends Notifier<List<CartItem>> {
  @override
  List<CartItem> build() => [];

  double _roundQuantity(double value) {
    return double.parse(value.toStringAsFixed(3));
  }

  double _availableInSaleUnit(Map<String, dynamic> product) {
    final stock = (product['stock'] as num? ?? 0).toDouble();
    final factor = UnitUtils.saleToStockFactor(product);
    if (factor <= 0) return stock;
    return _roundQuantity(stock / factor);
  }

  bool addProduct(Map<String, dynamic> product) {
    final stock = (product['stock'] as num? ?? 0).toDouble();
    final unit = UnitUtils.saleUnitForProduct(product);
    final stockUnit = UnitUtils.stockUnitForProduct(product);
    final saleToStockFactor = UnitUtils.saleToStockFactor(product);
    final availableSaleQuantity = _availableInSaleUnit(product);
    final costPerSaleUnit =
        ((product['cost'] as num? ?? 0).toDouble()) * saleToStockFactor;
    final step = UnitUtils.step(unit);
    if (stock <= 0 || availableSaleQuantity <= 0) return false;

    final existing = state
        .where((item) => item.productId == product['id'])
        .toList();
    if (existing.isNotEmpty) {
      final item = existing.first;
      if (item.quantity + 0.001 >= item.maxStock) return false;
      final nextQuantity = _roundQuantity(item.quantity + step);
      item.quantity = nextQuantity > item.maxStock
          ? item.maxStock
          : nextQuantity;
      state = [...state]; // trigger rebuild
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
          unitPrice: (product['price'] as num).toDouble(),
          cost: costPerSaleUnit,
          maxStock: availableSaleQuantity,
          stockOnHand: stock,
          saleToStockFactor: saleToStockFactor,
          unit: unit,
          stockUnit: stockUnit,
          quantity: initialQuantity,
        ),
      ];
      return true;
    }
  }

  void removeProduct(String productId) {
    state = state.where((item) => item.productId != productId).toList();
  }

  bool incrementQuantity(String productId) {
    final item = state.firstWhere((i) => i.productId == productId);
    if (item.quantity + 0.001 >= item.maxStock) return false;
    final nextQuantity = _roundQuantity(
      item.quantity + UnitUtils.step(item.unit),
    );
    item.quantity = nextQuantity > item.maxStock ? item.maxStock : nextQuantity;
    state = [...state];
    return true;
  }

  void decrementQuantity(String productId) {
    final item = state.firstWhere((i) => i.productId == productId);
    final nextQuantity = _roundQuantity(
      item.quantity - UnitUtils.step(item.unit),
    );
    if (nextQuantity > 0) {
      item.quantity = nextQuantity;
      state = [...state];
    } else {
      removeProduct(productId);
    }
  }

  bool setQuantity(String productId, double quantity) {
    final item = state.firstWhere((i) => i.productId == productId);
    if (quantity <= 0 || quantity - item.maxStock > 0.001) return false;
    item.quantity = _roundQuantity(quantity);
    state = [...state];
    return true;
  }

  void clear() {
    state = [];
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
