import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/widgets/overlay_notice.dart';

void main() {
  testWidgets('dialog notice is rendered above an open form dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Edit item'),
                    content: const TextField(),
                    actions: [
                      FilledButton(
                        onPressed: () => AppOverlayNotice.showSnackBar(
                          dialogContext,
                          const SnackBar(
                            content: Text('This warning stays visible'),
                          ),
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 200));

    final notice = find.byKey(const ValueKey('app-overlay-notice'));
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(notice, findsOneWidget);
    expect(
      tester.getBottomLeft(notice).dy,
      lessThan(tester.getTopLeft(find.text('Edit item')).dy),
    );

    AppOverlayNotice.dismiss();
    await tester.pump();
  });
}
