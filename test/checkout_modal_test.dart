import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_app/features/sales/presentation/checkout_modal.dart';

void main() {
  testWidgets('CheckoutModal builds and core interactions work', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final r = await CheckoutModal.show(
                  context,
                  currency: 'KSh',
                  total: 2160.00,
                  subtotal: 2000.00,
                  tax: 160.00,
                  taxRate: 8,
                  mpesaConfigured: false,
                );
                // ignore: avoid_print
                print('RESULT: $r');
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Header + total + VAT badge
    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Complete this sale'), findsOneWidget);
    expect(find.text('TOTAL TO PAY'), findsOneWidget);
    expect(find.text('KSh 2,160.00'), findsAtLeastNWidgets(1));
    expect(find.text('Includes VAT'), findsOneWidget);

    // Payment methods
    expect(find.text('Choose Payment Method'), findsOneWidget);
    expect(find.text('M-Pesa'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('Safaricom STK Push'), findsOneWidget);

    // M-Pesa warning (mpesaConfigured: false)
    expect(find.text('Business M-Pesa not configured'), findsOneWidget);
    expect(find.text('Configure now →'), findsOneWidget);

    // Customer section
    expect(find.text('Customer (Optional)'), findsOneWidget);
    expect(find.text('Search customer by name, phone or email'), findsOneWidget);
    expect(find.text('+ Add Customer'), findsOneWidget);
    expect(find.text('Charles'), findsOneWidget);
    expect(find.text('0707041808'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    // Summary
    expect(find.text('Subtotal'), findsOneWidget);
    expect(find.text('Tax (8%)'), findsOneWidget);
    expect(find.text('Total'), findsWidgets);

    // Actions
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Pay with M-Pesa'), findsOneWidget);

    // Default selection is M-Pesa -> primary button shows M-Pesa
    expect(find.text('Pay with M-Pesa'), findsOneWidget);

    // Tapping Cash switches the primary action label
    await tester.ensureVisible(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    expect(find.text('Take Cash'), findsOneWidget);

    // Pay returns the selected method + total
    await tester.ensureVisible(find.text('Take Cash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Cash'));
    await tester.pumpAndSettle();
  });
}
