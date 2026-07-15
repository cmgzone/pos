import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/storefront/presentation/online_store_screen.dart';

void main() {
  testWidgets('online store groups every storefront task in one workspace', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(860, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const OnlineStoreScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Online Store'), findsWidgets);
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Products'), findsWidgets);
    expect(find.text('Orders'), findsWidgets);
    expect(find.text('Branding'), findsWidgets);
    expect(find.text('Website & Checkout'), findsWidgets);
    expect(find.text('Payments'), findsWidgets);
    expect(find.text('Share Store Link'), findsOneWidget);
    expect(find.text('QR Poster'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
