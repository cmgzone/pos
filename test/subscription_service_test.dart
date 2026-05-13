import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/core/services/subscription_service.dart';

void main() {
  test('subscription plans expose only backend configured billing periods', () {
    const market = SubscriptionMarket(
      countryCode: 'KE',
      label: 'Kenya',
      currency: 'KES',
      provider: 'mpesa',
      providerLabel: 'M-Pesa',
    );
    const plan = SubscriptionPlanSummary(
      code: 'pro',
      name: 'Pro',
      description: 'Full POS suite',
      features: ['pos', 'products', 'services'],
      sellingModes: ['products', 'services', 'combo'],
      entitlements: SubscriptionEntitlements.empty(),
      prices: [
        SubscriptionPlanPrice(
          id: 'pro-ke-monthly',
          planCode: 'pro',
          countryCode: 'KE',
          currency: 'KES',
          amountMinor: 750000,
          billingPeriod: 'monthly',
          provider: 'mpesa',
        ),
        SubscriptionPlanPrice(
          id: 'pro-ke-yearly',
          planCode: 'pro',
          countryCode: 'KE',
          currency: 'KES',
          amountMinor: 7200000,
          billingPeriod: 'yearly',
          provider: 'mpesa',
        ),
      ],
      price: null,
    );

    expect(plan.billingPeriodsFor(market), ['monthly', 'yearly']);
    expect(
      plan.priceFor(market, billingPeriod: 'monthly')?.displayAmount,
      'KES 7,500',
    );
    expect(
      plan.priceFor(market, billingPeriod: 'yearly')?.displayAmount,
      'KES 72,000',
    );
    expect(plan.priceFor(market, billingPeriod: 'weekly'), isNull);
  });
}
