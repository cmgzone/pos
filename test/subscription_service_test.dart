import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/core/services/subscription_service.dart';

void main() {
  test('subscription plans expose only backend configured billing periods', () {
    const market = SubscriptionMarket(
      countryCode: 'KE',
      label: 'Kenya',
      currency: 'KES',
      provider: 'google_play',
      providerLabel: 'Google Play',
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
          provider: 'google_play',
          storeProductId: 'piki_pro_monthly',
        ),
        SubscriptionPlanPrice(
          id: 'pro-ke-yearly',
          planCode: 'pro',
          countryCode: 'KE',
          currency: 'KES',
          amountMinor: 7200000,
          billingPeriod: 'yearly',
          provider: 'google_play',
          storeProductId: 'piki_pro_yearly',
        ),
      ],
      price: null,
    );

    expect(plan.billingPeriodsFor(market), ['monthly', 'yearly']);
    expect(
      plan.priceFor(market, billingPeriod: 'monthly')?.displayAmount,
      'KSh 7,500',
    );
    expect(
      plan.priceFor(market, billingPeriod: 'yearly')?.displayAmount,
      'KSh 72,000',
    );
    expect(plan.priceFor(market, billingPeriod: 'weekly'), isNull);
  });

  test(
    'subscription plan prices render non-KES currencies with their symbol',
    () {
      const usdMarket = SubscriptionMarket(
        countryCode: 'GLOBAL',
        label: 'Other Countries',
        currency: 'USD',
        provider: 'paypal',
        providerLabel: 'PayPal',
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
            id: 'pro-global-monthly',
            planCode: 'pro',
            countryCode: 'GLOBAL',
            currency: 'USD',
            amountMinor: 1500,
            billingPeriod: 'monthly',
            provider: 'paypal',
          ),
        ],
        price: null,
      );

      expect(
        plan.priceFor(usdMarket, billingPeriod: 'monthly')?.displayAmount,
        r'$15.00',
      );
      expect(
        plan
            .priceFor(usdMarket, billingPeriod: 'monthly')
            ?.displayAmountWithCode,
        r'$15.00 (USD)',
      );
    },
  );

  test('subscription checkout parses Google Play details', () {
    final checkout = SubscriptionCheckoutResult.fromJson({
      'id': 'payment-1',
      'provider': 'google_play',
      'status': 'pending',
      'message': 'Continue with Google Play.',
      'storeProductId': 'piki_pro_monthly',
    });

    expect(checkout.paymentId, 'payment-1');
    expect(checkout.provider, 'google_play');
    expect(checkout.status, 'pending');
    expect(checkout.message, 'Continue with Google Play.');
    expect(checkout.storeProductId, 'piki_pro_monthly');
  });

  test('subscription checkout parses hosted provider URL', () {
    final checkout = SubscriptionCheckoutResult.fromJson({
      'id': 'payment-2',
      'provider': 'paypal',
      'status': 'pending',
      'checkoutUrl': 'https://www.sandbox.paypal.com/checkoutnow?token=123',
    });

    expect(checkout.provider, 'paypal');
    expect(checkout.checkoutUrl, startsWith('https://'));
  });

  test('subscription plans discard legacy subscription providers', () {
    final plan = SubscriptionPlanSummary.fromJson({
      'code': 'pro',
      'name': 'Pro',
      'prices': [
        {
          'id': 'legacy-mpesa',
          'planCode': 'pro',
          'countryCode': 'KE',
          'currency': 'KES',
          'amountMinor': 750000,
          'billingPeriod': 'monthly',
          'provider': 'mpesa',
        },
        {
          'id': 'legacy-google-pay',
          'planCode': 'pro',
          'countryCode': 'KE',
          'currency': 'KES',
          'amountMinor': 750000,
          'billingPeriod': 'monthly',
          'provider': 'google_pay',
        },
        {
          'id': 'google-play',
          'planCode': 'pro',
          'countryCode': 'KE',
          'currency': 'KES',
          'amountMinor': 750000,
          'billingPeriod': 'monthly',
          'provider': 'google_play',
          'storeProductId': 'piki_pro_monthly',
        },
      ],
      'price': {
        'id': 'legacy-mpesa',
        'planCode': 'pro',
        'countryCode': 'KE',
        'currency': 'KES',
        'amountMinor': 750000,
        'billingPeriod': 'monthly',
        'provider': 'mpesa',
      },
    });

    expect(plan.prices, hasLength(1));
    expect(plan.prices.single.provider, 'google_play');
    expect(plan.price, isNull);
  });

  test('restaurant entitlements do not activate the retail or service POS', () {
    final restaurant = SubscriptionEntitlements.fromJson({
      'features': ['pos', 'products', 'restaurant_mode'],
      'sellingMode': 'restaurant',
      'sellingModes': ['products', 'services', 'restaurant'],
    });
    final products = SubscriptionEntitlements.fromJson({
      'features': ['pos', 'products'],
      'sellingMode': 'products',
      'sellingModes': ['products', 'services', 'restaurant'],
    });

    expect(restaurant.isRestaurant, isTrue);
    expect(restaurant.canSellProducts, isFalse);
    expect(restaurant.canSellServices, isFalse);
    expect(products.isRestaurant, isFalse);
    expect(products.canSellProducts, isTrue);
  });
}
