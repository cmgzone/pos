import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/auth/presentation/login_screen.dart';
import 'package:pos_app/features/auth/presentation/sign_up_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAuthScreen(
    WidgetTester tester, {
    required Size size,
    required Widget screen,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: screen,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('login fits a compact phone with enlarged text', (tester) async {
    await pumpAuthScreen(
      tester,
      size: const Size(320, 568),
      screen: const LoginScreen(),
      textScale: 1.2,
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login story and form fit a Windows-sized viewport', (
    tester,
  ) async {
    await pumpAuthScreen(
      tester,
      size: const Size(1280, 720),
      screen: const LoginScreen(),
    );

    expect(find.textContaining('A clear counter'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff sign-up stays scrollable on a compact phone', (
    tester,
  ) async {
    await pumpAuthScreen(
      tester,
      size: const Size(320, 568),
      screen: const SignUpScreen(initialRole: 'STAFF'),
      textScale: 1.2,
    );

    expect(find.text('Create Staff Account'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
