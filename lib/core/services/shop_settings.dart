import 'package:flutter/foundation.dart';
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
  static const _keySecondaryCurrency = 'secondary_currency';
  static const _keySecondaryCurrencyRate = 'secondary_currency_rate';
  static const _keyDualCurrencyEnabled = 'dual_currency_enabled';
  static const _keyReceiptFooter = 'receipt_footer';
  static const _keyShopLogoUrl = 'shop_logo_url';
  static const _keyCarwashBays = 'carwash_bays_count';
  static const _keyCashDrawerEnabled = 'cash_drawer_enabled';
  static const _keyCashDrawerPrinterPath = 'cash_drawer_printer_path';
  static const _keyEtimsEnabled = 'etims_enabled';
  static const _keyEtimsAutoSubmit = 'etims_auto_submit';
  static const _keyKraPin = 'kra_pin';
  static const _keyEtimsVatNumber = 'etims_vat_number';
  static const _keyEtimsSolutionType = 'etims_solution_type';
  static const _keyEtimsBranchCode = 'etims_branch_code';
  static const _keyEtimsDeviceSerial = 'etims_device_serial';
  static const _keyQuotationsEnabled = 'sales_enable_quotations';

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
    _prefs ??= await SharedPreferences.getInstance();
  }

  @visibleForTesting
  static void resetForTesting() {
    _prefs = null;
  }

  // Getters
  static String get shopName => _prefs?.getString(_keyShopName) ?? 'My Shop';
  static String get shopAddress => _prefs?.getString(_keyShopAddress) ?? '';
  static String get shopPhone => _prefs?.getString(_keyShopPhone) ?? '';
  static String get shopEmail => _prefs?.getString(_keyShopEmail) ?? '';
  static double get taxRate => _prefs?.getDouble(_keyTaxRate) ?? 8.0;
  static String get currency => _prefs?.getString(_keyCurrency) ?? '\$';
  static String get secondaryCurrency =>
      _prefs?.getString(_keySecondaryCurrency) ?? r'$';
  static double get secondaryCurrencyRate =>
      _prefs?.getDouble(_keySecondaryCurrencyRate) ?? 0;
  static bool get dualCurrencyEnabled =>
      _prefs?.getBool(_keyDualCurrencyEnabled) ?? false;
  static String get receiptFooter =>
      _prefs?.getString(_keyReceiptFooter) ?? 'Thank you for your purchase!';
  static String get shopLogoUrl => _prefs?.getString(_keyShopLogoUrl) ?? '';
  static int get carwashBaysCount => _prefs?.getInt(_keyCarwashBays) ?? 4;
  static bool get cashDrawerEnabled =>
      _prefs?.getBool(_keyCashDrawerEnabled) ?? false;
  static String get cashDrawerPrinterPath =>
      _prefs?.getString(_keyCashDrawerPrinterPath) ?? '';
  static bool get etimsEnabled => _prefs?.getBool(_keyEtimsEnabled) ?? false;
  static bool get etimsAutoSubmit =>
      _prefs?.getBool(_keyEtimsAutoSubmit) ?? true;
  static String get kraPin => _prefs?.getString(_keyKraPin) ?? '';
  static String get etimsVatNumber =>
      _prefs?.getString(_keyEtimsVatNumber) ?? '';
  static String get etimsSolutionType =>
      _prefs?.getString(_keyEtimsSolutionType) ?? 'OSCU';
  static String get etimsBranchCode =>
      _prefs?.getString(_keyEtimsBranchCode) ?? '';
  static String get etimsDeviceSerial =>
      _prefs?.getString(_keyEtimsDeviceSerial) ?? '';
  static bool get quotationsEnabled =>
      _prefs?.getBool(_keyQuotationsEnabled) ?? true;

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
  static Future<void> setSecondaryCurrency(String value) =>
      _prefs!.setString(_keySecondaryCurrency, normalizeCurrency(value));
  static Future<void> setSecondaryCurrencyRate(double value) =>
      _prefs!.setDouble(_keySecondaryCurrencyRate, value <= 0 ? 0 : value);
  static Future<void> setDualCurrencyEnabled(bool value) =>
      _prefs!.setBool(_keyDualCurrencyEnabled, value);
  static Future<void> setReceiptFooter(String value) =>
      _prefs!.setString(_keyReceiptFooter, value);
  static Future<void> setShopLogoUrl(String value) async {
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) {
      await _prefs!.remove(_keyShopLogoUrl);
      return;
    }
    await _prefs!.setString(_keyShopLogoUrl, cleanValue);
  }
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

  static Future<void> setEtimsEnabled(bool value) =>
      _prefs!.setBool(_keyEtimsEnabled, value);
  static Future<void> setEtimsAutoSubmit(bool value) =>
      _prefs!.setBool(_keyEtimsAutoSubmit, value);
  static Future<void> setKraPin(String value) =>
      _prefs!.setString(_keyKraPin, value.trim().toUpperCase());
  static Future<void> setEtimsVatNumber(String value) =>
      _prefs!.setString(_keyEtimsVatNumber, value.trim());
  static Future<void> setEtimsSolutionType(String value) {
    final clean = value.trim().toUpperCase();
    return _prefs!.setString(
      _keyEtimsSolutionType,
      clean == 'VSCU' ? 'VSCU' : 'OSCU',
    );
  }

  static Future<void> setEtimsBranchCode(String value) =>
      _prefs!.setString(_keyEtimsBranchCode, value.trim());
  static Future<void> setEtimsDeviceSerial(String value) =>
      _prefs!.setString(_keyEtimsDeviceSerial, value.trim());

  static Future<void> setQuotationsEnabled(bool value) =>
      _prefs!.setBool(_keyQuotationsEnabled, value);

  static Future<void> resetForBusinessSwitch() async {
    await init();
    await _prefs!.remove(_keyShopName);
    await _prefs!.remove(_keyShopAddress);
    await _prefs!.remove(_keyShopPhone);
    await _prefs!.remove(_keyShopEmail);
    await _prefs!.remove(_keyTaxRate);
    await _prefs!.remove(_keyCurrency);
    await _prefs!.remove(_keySecondaryCurrency);
    await _prefs!.remove(_keySecondaryCurrencyRate);
    await _prefs!.remove(_keyDualCurrencyEnabled);
    await _prefs!.remove(_keyReceiptFooter);
    await _prefs!.remove(_keyShopLogoUrl);
    await _prefs!.remove(_keyCashDrawerEnabled);
    await _prefs!.remove(_keyCashDrawerPrinterPath);
    await _prefs!.remove(_keyEtimsEnabled);
    await _prefs!.remove(_keyEtimsAutoSubmit);
    await _prefs!.remove(_keyKraPin);
    await _prefs!.remove(_keyEtimsVatNumber);
    await _prefs!.remove(_keyEtimsSolutionType);
    await _prefs!.remove(_keyEtimsBranchCode);
    await _prefs!.remove(_keyEtimsDeviceSerial);
    await _prefs!.remove(_keyQuotationsEnabled);
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

  /// Maps an ISO 4217 currency code (e.g. `KES`, `USD`) to the display symbol
  /// used throughout the app. Unknown codes fall back to the uppercased code
  /// itself, or `$` when missing.
  static String currencySymbolFor(String? currencyCode) {
    switch (currencyCode?.trim().toUpperCase()) {
      case 'KES':
        return 'KSh';
      case 'TZS':
        return 'TSh';
      case 'UGX':
        return 'USh';
      case 'RWF':
        return 'FRw';
      case 'ZAR':
        return 'R';
      case 'GBP':
        return '\u00A3';
      case 'EUR':
        return '\u20AC';
      case 'USD':
        return r'$';
      default:
        final code = currencyCode?.trim().toUpperCase();
        return (code != null && code.isNotEmpty) ? code : r'$';
    }
  }

  /// Letter-based currency symbols (KSh, TSh, USh, FRw, R) are typeset with a
  /// separating space before the amount; sign-based symbols ($, £, €) are not.
  static bool currencySymbolUsesSpace(String symbol) {
    return RegExp(r'^[A-Za-z]').hasMatch(symbol);
  }

  static String normalizeCurrency(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? r'$' : normalized;
  }
}
