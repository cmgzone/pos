import 'package:shared_preferences/shared_preferences.dart';

class ShopCurrencyOption {
  final String prefix;
  final String label;

  const ShopCurrencyOption(this.prefix, this.label);
}

class ShopSettings {
  static const _keyShopName = 'shop_name';
  static const _keyShopAddress = 'shop_address';
  static const _keyShopPhone = 'shop_phone';
  static const _keyShopEmail = 'shop_email';
  static const _keyTaxRate = 'tax_rate';
  static const _keyCurrency = 'currency';
  static const _keyReceiptFooter = 'receipt_footer';
  static const _keyCarwashBays = 'carwash_bays_count';
  static const _keyCashDrawerEnabled = 'cash_drawer_enabled';
  static const _keyCashDrawerPrinterPath = 'cash_drawer_printer_path';

  static SharedPreferences? _prefs;

  static const currencyOptions = <ShopCurrencyOption>[
    ShopCurrencyOption('KSh', 'Kenyan Shilling (KSh)'),
    ShopCurrencyOption('TSh', 'Tanzanian Shilling (TSh)'),
    ShopCurrencyOption('USh', 'Ugandan Shilling (USh)'),
    ShopCurrencyOption('FRw', 'Rwandan Franc (FRw)'),
    ShopCurrencyOption(r'$', 'US Dollar (\$)'),
    ShopCurrencyOption('\u20AC', 'Euro (\u20AC)'),
    ShopCurrencyOption('\u00A3', 'British Pound (\u00A3)'),
    ShopCurrencyOption('R', 'South African Rand (R)'),
  ];

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
  static int get carwashBaysCount => _prefs?.getInt(_keyCarwashBays) ?? 4;
  static bool get cashDrawerEnabled =>
      _prefs?.getBool(_keyCashDrawerEnabled) ?? false;
  static String get cashDrawerPrinterPath =>
      _prefs?.getString(_keyCashDrawerPrinterPath) ?? '';

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
      _prefs!.setString(_keyCurrency, normalizeCurrency(value));
  static Future<void> setReceiptFooter(String value) =>
      _prefs!.setString(_keyReceiptFooter, value);
  static Future<void> setCarwashBaysCount(int value) =>
      _prefs!.setInt(_keyCarwashBays, value);
  static Future<void> setCashDrawerEnabled(bool value) =>
      _prefs!.setBool(_keyCashDrawerEnabled, value);
  static Future<void> setCashDrawerPrinterPath(String value) async {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) {
      await _prefs!.remove(_keyCashDrawerPrinterPath);
      return;
    }
    await _prefs!.setString(_keyCashDrawerPrinterPath, cleanValue);
  }

  static Future<void> resetForBusinessSwitch() async {
    await init();
    await _prefs!.remove(_keyShopName);
    await _prefs!.remove(_keyShopAddress);
    await _prefs!.remove(_keyShopPhone);
    await _prefs!.remove(_keyShopEmail);
    await _prefs!.remove(_keyTaxRate);
    await _prefs!.remove(_keyCurrency);
    await _prefs!.remove(_keyReceiptFooter);
    await _prefs!.remove(_keyCashDrawerEnabled);
    await _prefs!.remove(_keyCashDrawerPrinterPath);
  }

  /// Check if shop has been set up
  static bool get isConfigured =>
      _prefs?.getString(_keyShopName) != null &&
      _prefs!.getString(_keyShopName)!.isNotEmpty &&
      _prefs!.getString(_keyShopName) != 'My Shop';

  static String suggestedCurrencyForCountry(String? countryCode) {
    switch (countryCode?.trim().toUpperCase()) {
      case 'KE':
        return 'KSh';
      case 'TZ':
        return 'TSh';
      case 'UG':
        return 'USh';
      case 'RW':
        return 'FRw';
      case 'ZA':
        return 'R';
      case 'GB':
        return '\u00A3';
      default:
        return r'$';
    }
  }

  static String normalizeCurrency(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? r'$' : normalized;
  }
}
