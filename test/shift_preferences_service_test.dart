import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/shifts/data/shift_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  setUp(() async {
    await prefs.clear();
  });

  test('returns null until a cashier opening cash is saved', () async {
    expect(
      await ShiftPreferencesService.getLastOpeningCash('cashier-1'),
      isNull,
    );
  });

  test('stores suggested opening cash per cashier', () async {
    await ShiftPreferencesService.saveLastOpeningCash('cashier-1', 1200);
    await ShiftPreferencesService.saveLastOpeningCash('cashier-2', 875.5);
    await ShiftPreferencesService.saveLastOpeningCash('', 300);

    expect(await ShiftPreferencesService.getLastOpeningCash('cashier-1'), 1200);
    expect(
      await ShiftPreferencesService.getLastOpeningCash('cashier-2'),
      875.5,
    );
    expect(await ShiftPreferencesService.getLastOpeningCash(''), 300);
  });
}
