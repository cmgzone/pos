import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/features/onboarding/data/business_onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('filters recommended setup to features supported by the plan', () {
    final recommended = BusinessOnboardingService.recommendedFeatures(
      businessType: 'retail',
      sellingFocus: 'products',
      stockTracking: 'yes',
      creditSales: 'yes',
      onlineSelling: 'yes',
    );

    final supported = BusinessOnboardingService.planSupportedFeatures(
      recommendedFeatures: recommended,
      planFeatures: const [
        UserAccessProfile.featureDashboard,
        UserAccessProfile.featurePos,
        UserAccessProfile.featureSales,
        UserAccessProfile.featureProducts,
        UserAccessProfile.featureSettings,
      ],
    );

    expect(supported, contains(UserAccessProfile.featureProducts));
    expect(supported, isNot(contains(UserAccessProfile.featureKopesha)));
    expect(supported, isNot(contains(UserAccessProfile.featureStockList)));
  });

  test('does not recommend features when plan features are unknown', () {
    final recommended = BusinessOnboardingService.recommendedFeatures(
      businessType: 'services',
      sellingFocus: 'services',
      stockTracking: 'no',
      creditSales: 'no',
      onlineSelling: 'no',
    );

    final supported = BusinessOnboardingService.planSupportedFeatures(
      recommendedFeatures: recommended,
      planFeatures: const [],
    );

    expect(supported, isEmpty);
  });

  test('restaurant setup recommends restaurant mode instead of services', () {
    final recommended = BusinessOnboardingService.recommendedFeatures(
      businessType: 'restaurant',
      sellingFocus: 'products',
      stockTracking: 'no',
      creditSales: 'no',
      onlineSelling: 'no',
    );

    expect(recommended, contains(UserAccessProfile.featureRestaurantMode));
    expect(recommended, contains(UserAccessProfile.featureProducts));
    expect(recommended, isNot(contains(UserAccessProfile.featureServices)));
  });

  test('stores onboarding answers per business', () async {
    final answers = BusinessOnboardingAnswers(
      businessId: 'biz-1',
      businessName: 'Piki Shop',
      planCode: 'starter',
      heardFrom: 'google',
      businessType: 'retail',
      sellingFocus: 'products',
      stockTracking: 'yes',
      creditSales: 'no',
      onlineSelling: 'later',
      recommendedFeatures: const [
        UserAccessProfile.featurePos,
        UserAccessProfile.featureSales,
      ],
      completedAt: DateTime.utc(2026, 6, 18),
    );

    await BusinessOnboardingService.save(answers);

    final loaded = await BusinessOnboardingService.loadForBusiness('biz-1');

    expect(loaded, isNotNull);
    expect(loaded!.businessName, 'Piki Shop');
    expect(loaded.recommendedFeatures, [
      UserAccessProfile.featurePos,
      UserAccessProfile.featureSales,
    ]);
  });
}
