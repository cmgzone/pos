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
}
