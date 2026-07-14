import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/storefront_theme_service.dart';
import 'package:pos_app/features/agent/data/piki_agent_service.dart';

void main() {
  test('storefront theme parses validated design and checkout settings', () {
    final theme = StorefrontTheme.fromJson({
      'id': 'theme_1',
      'branchId': 'main_branch',
      'storefrontType': 'retail',
      'name': 'Minimal shop',
      'preset': 'minimal',
      'isPublished': false,
      'source': 'ai',
      'design': {
        'accentColor': '#123456',
        'heroStyle': 'split',
        'cardStyle': 'minimal',
        'imageRatio': 'square',
      },
      'checkout': {
        'paymentMethods': ['manual', 'mpesa'],
        'fulfillmentMethods': ['pickup'],
        'showOrderNote': false,
        'checkoutTitle': 'Complete your order',
      },
    });

    expect(theme.id, 'theme_1');
    expect(theme.design.accentColor, '#123456');
    expect(theme.design.heroStyle, 'split');
    expect(theme.checkout.paymentMethods, ['manual', 'mpesa']);
    expect(theme.checkout.fulfillmentMethods, ['pickup']);
    expect(theme.checkout.showOrderNote, isFalse);
    expect(theme.isPublished, isFalse);
  });

  test('Piki storefront and payment tools always require confirmation', () {
    expect(
      PikiAgentService.requiresConfirmation(
        PikiAgentService.toolBuildStorefront,
      ),
      isTrue,
    );
    expect(
      PikiAgentService.requiresConfirmation(
        PikiAgentService.toolCustomizeCheckout,
      ),
      isTrue,
    );
    expect(
      PikiAgentService.requiresConfirmation(
        PikiAgentService.toolSetupPaymentGateway,
      ),
      isTrue,
    );
  });
}
