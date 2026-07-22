import 'package:flutter/material.dart';

import 'features/sales/presentation/checkout_modal.dart';

/// Standalone high-fidelity preview of the Piki POS Checkout Modal.
///
/// Run with: `flutter run -t lib/checkout_modal_demo.dart`
void main() {
  runApp(const _CheckoutDemoApp());
}

class _CheckoutDemoApp extends StatelessWidget {
  const _CheckoutDemoApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        scaffoldBackgroundColor: const Color(0xFFEDEDED),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE86A33),
          surface: Colors.white,
        ),
      ),
      home: const _DemoHome(),
    );
  }
}

class _DemoHome extends StatelessWidget {
  const _DemoHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFEDEDED),
              image: DecorationImage(
                image: NetworkImage(
                  'https://images.unsplash.com/photo-1556742502-ec7c0e9f34b1?w=1600',
                ),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Color(0x66000000),
                  BlendMode.darken,
                ),
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: const _Backdrop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A blurred, dimmed backdrop that hosts the centered checkout modal.
class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withValues(alpha: 0.35),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: const CheckoutModal(
              currency: 'KSh',
              total: 2160.00,
              subtotal: 2000.00,
              tax: 160.00,
              taxRate: 8,
              mpesaConfigured: false,
            ),
          ),
        ),
      ],
    );
  }
}
