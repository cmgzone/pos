import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/sales/data/quotation_form_provider.dart';
import 'package:pos_app/features/sales/presentation/quotations_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    ShopSettings.resetForTesting();
    await ShopSettings.init();
  });

  testWidgets('create quotation starts a fresh quotation builder', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer(
      overrides: [quotationsListProvider.overrideWith((ref) async => const [])],
    );
    addTearDown(container.dispose);
    container.read(quotationNotesProvider.notifier).state = 'Old draft';
    container.read(lastSavedQuotationProvider.notifier).state = const {
      'id': 'old-quotation',
    };
    container.read(activeQuotationIdProvider.notifier).state = 'old-quotation';

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const QuotationsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('create-quotation-action')),
      findsOneWidget,
    );
    expect(find.text('Create quotations from the POS screen.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('create-quotation-action')));
    await tester.pump();

    expect(container.read(posModeProvider), PosMode.quotation);
    expect(container.read(quotationNotesProvider), isEmpty);
    expect(container.read(lastSavedQuotationProvider), isNull);
    expect(container.read(activeQuotationIdProvider), isNull);
    expect(tester.takeException(), isNull);
  });
}
