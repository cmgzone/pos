import 'package:shared_preferences/shared_preferences.dart';

class ShopSettings {
  static const _keyShopName = 'shop_name';
  static const _keyShopAddress = 'shop_address';
  static const _keyShopPhone = 'shop_phone';
  static const _keyShopEmail = 'shop_email';
  static const _keyTaxRate = 'tax_rate';
  static const _keyCurrency = 'currency';
  static const _keyReceiptFooter = 'receipt_footer';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Getters
  static String get shopName => _prefs?.getString(_keyShopName) ?? 'My Shop';
  static String get shopAddress => _prefs?.getString(_keyShopAddress) ?? '';
  static String get shopPhone => _prefs?.getString(_keyShopPhone) ?? '';
  static String get shopEmail => _prefs?.getString(_keyShopEmail) ?? '';
  static double get taxRate => _prefs?.getDouble(_keyTaxRate) ?? 8.0;
  static String get currency => _prefs?.getString(_keyCurrency) ?? '\$';
  static String get receiptFooter =>
      _prefs?.getString(_keyReceiptFooter) ?? 'Thank you for your purchase!';

  // Setters
  static Future<void> setShopName(String value) =>
      _prefs!.setString(_keyShopName, value);
  static Future<void> setShopAddress(String value) =>
      _prefs!.setString(_keyShopAddress, value);
  static Future<void> setShopPhone(String value) =>
      _prefs!.setString(_keyShopPhone, value);
  static Future<void> setShopEmail(String value) =>
      _prefs!.setString(_keyShopEmail, value);
  static Future<void> setTaxRate(double value) =>
      _prefs!.setDouble(_keyTaxRate, value);
  static Future<void> setCurrency(String value) =>
      _prefs!.setString(_keyCurrency, value);
  static Future<void> setReceiptFooter(String value) =>
      _prefs!.setString(_keyReceiptFooter, value);

  /// Check if shop has been set up
  static bool get isConfigured =>
      _prefs?.getString(_keyShopName) != null &&
      _prefs!.getString(_keyShopName)!.isNotEmpty &&
      _prefs!.getString(_keyShopName) != 'My Shop';
}
