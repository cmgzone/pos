import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ShopSettings.init();
    prefs = await SharedPreferences.getInstance();
  });

  setUp(() async {
    await prefs.clear();
  });

  test('resetForBusinessSwitch clears business-owned preferences', () async {
    await ShopSettings.setShopName('Biz A');
    await ShopSettings.setShopAddress('42 Market Street');
    await ShopSettings.setShopPhone('0712345678');
    await ShopSettings.setShopEmail('owner@biza.test');
    await ShopSettings.setTaxRate(16);
    await ShopSettings.setCurrency('KES');
    await ShopSettings.setReceiptFooter('Come again');

    expect(ShopSettings.isConfigured, isTrue);

    await ShopSettings.resetForBusinessSwitch();

    expect(ShopSettings.shopName, 'My Shop');
    expect(ShopSettings.shopAddress, '');
    expect(ShopSettings.shopPhone, '');
    expect(ShopSettings.shopEmail, '');
    expect(ShopSettings.taxRate, 8.0);
    expect(ShopSettings.currency, r'$');
    expect(ShopSettings.receiptFooter, 'Thank you for your purchase!');
    expect(ShopSettings.isConfigured, isFalse);
  });

  test('suggested registration currency follows the selected country', () {
    expect(ShopSettings.suggestedCurrencyForCountry('KE'), 'KSh');
    expect(ShopSettings.suggestedCurrencyForCountry('TZ'), 'TSh');
    expect(ShopSettings.suggestedCurrencyForCountry('UG'), 'USh');
    expect(ShopSettings.suggestedCurrencyForCountry('RW'), 'FRw');
    expect(ShopSettings.suggestedCurrencyForCountry('GLOBAL'), r'$');
  });

  test('currencySymbolFor maps ISO codes to display symbols', () {
    expect(ShopSettings.currencySymbolFor('KES'), 'KSh');
    expect(ShopSettings.currencySymbolFor('USD'), r'$');
    expect(ShopSettings.currencySymbolFor('GBP'), '\u00A3');
    expect(ShopSettings.currencySymbolFor('EUR'), '\u20AC');
    expect(ShopSettings.currencySymbolFor('TZS'), 'TSh');
    expect(ShopSettings.currencySymbolFor('ZAR'), 'R');
    expect(ShopSettings.currencySymbolFor('usd'), r'$');
    expect(ShopSettings.currencySymbolFor(null), r'$');
    expect(ShopSettings.currencySymbolFor('XYZ'), 'XYZ');
  });

  test('currencySymbolUsesSpace separates letter symbols from amounts', () {
    expect(ShopSettings.currencySymbolUsesSpace('KSh'), isTrue);
    expect(ShopSettings.currencySymbolUsesSpace('R'), isTrue);
    expect(ShopSettings.currencySymbolUsesSpace(r'$'), isFalse);
    expect(ShopSettings.currencySymbolUsesSpace('\u00A3'), isFalse);
    expect(ShopSettings.currencySymbolUsesSpace('\u20AC'), isFalse);
  });

  test('setCurrency trims input and keeps a safe default', () async {
    await ShopSettings.setCurrency('  KSh  ');
    expect(ShopSettings.currency, 'KSh');

    await ShopSettings.setCurrency('   ');
    expect(ShopSettings.currency, r'$');
  });
}
