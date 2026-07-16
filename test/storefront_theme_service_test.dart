import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/piki_ai_job_service.dart';
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
        'catalogLayout': 'sidebar',
      },
      'sections': [
        {
          'id': 'hero',
          'type': 'hero',
          'title': 'A complete storefront',
          'enabled': true,
        },
        {
          'id': 'catalog',
          'type': 'catalog',
          'title': 'Shop everything',
          'enabled': true,
        },
      ],
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
    expect(theme.design.catalogLayout, 'sidebar');
    expect(theme.sections.map((section) => section.type), ['hero', 'catalog']);
    expect(theme.sections.first.title, 'A complete storefront');
    expect(theme.checkout.paymentMethods, ['manual', 'mpesa']);
    expect(theme.checkout.fulfillmentMethods, ['pickup']);
    expect(theme.checkout.showOrderNote, isFalse);
    expect(theme.isPublished, isFalse);
  });

  test('Piki storefront and payment tools always require confirmation', () {
    expect(PikiAgentService.toolCatalogPrompt(), contains('storefront_brief'));
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

  test(
    'storefront background job restores progress and saved theme result',
    () {
      final job = PikiAiJob.fromJson({
        'id': 'job_1',
        'branchId': 'main_branch',
        'jobType': 'storefront_theme',
        'status': 'completed',
        'progress': 100,
        'totalSteps': 5,
        'completedSteps': 5,
        'currentStep': 'Storefront draft ready',
        'payload': {
          'themeId': 'theme_1',
          'storefrontType': 'retail',
          'buildFromScratch': true,
        },
        'result': {
          'themeId': 'theme_2',
          'theme': {'id': 'theme_2', 'name': 'Piki draft'},
        },
      });

      expect(job.jobType, 'storefront_theme');
      expect(job.branchId, 'main_branch');
      expect(job.payload?['buildFromScratch'], isTrue);
      expect(job.result?['themeId'], 'theme_2');
      expect(job.isDone, isTrue);
      expect(job.isRunning, isFalse);
    },
  );
}
