const test = require('node:test');
const assert = require('node:assert/strict');

const {
  DEFAULT_PLANS,
  applySellingModeToEntitlements,
  isPriceAvailableForPublicCatalog,
  isPriceVisibleInPublicCatalog,
  isProviderRuntimeReady,
  isSubscriptionPaymentProviderAllowed,
  normalizeSellingMode,
  normalizeGraceDays,
  normalizeTrialDays,
  renewalBaseDate,
  validatePaymentGatewayConfiguration,
  validateSellingModeEntitlement,
} = require('../src/subscriptionPlans');

test('Flutterwave accepts complete v3 and v4 credential sets together', () => {
  assert.doesNotThrow(() =>
    validatePaymentGatewayConfiguration({
      provider: 'flutterwave',
      isActive: true,
      publicConfig: { baseUrl: 'https://api.flutterwave.com/v3' },
      secretConfig: {
        secretKey: 'FLWSECK_TEST-example',
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: 'v4-encryption-key',
        webhookHash: 'webhook-secret',
      },
    }),
  );
});

test('Flutterwave accepts a complete v4 credential set without v3 credentials', () => {
  assert.doesNotThrow(() =>
    validatePaymentGatewayConfiguration({
      provider: 'flutterwave',
      isActive: true,
      publicConfig: {},
      secretConfig: {
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: 'v4-encryption-key',
      },
    }),
  );
});

test('Flutterwave rejects an incomplete v4 credential set', () => {
  assert.throws(
    () =>
      validatePaymentGatewayConfiguration({
        provider: 'flutterwave',
        isActive: true,
        publicConfig: { baseUrl: 'https://api.flutterwave.com/v3' },
        secretConfig: {
          secretKey: 'FLWSECK_TEST-example',
          clientId: 'v4-client-id',
          webhookHash: 'webhook-secret',
        },
      }),
    /Complete all Flutterwave v4 credentials/,
  );
});

test('hosted subscription providers require a public HTTPS return origin', () => {
  const flutterwaveV3Credentials = {
    secretKey: 'FLWSECK_TEST-example',
    webhookHash: 'webhook-secret',
  };
  assert.equal(
    isProviderRuntimeReady('flutterwave', {
      publicBaseUrl: '',
      secretConfig: flutterwaveV3Credentials,
    }),
    false,
  );
  assert.equal(
    isProviderRuntimeReady('flutterwave', {
      publicBaseUrl: 'http://localhost:3000',
      secretConfig: flutterwaveV3Credentials,
    }),
    false,
  );
  assert.equal(
    isProviderRuntimeReady('flutterwave', {
      publicBaseUrl: 'https://pikipos.com',
      secretConfig: flutterwaveV3Credentials,
    }),
    true,
  );
  assert.equal(
    isProviderRuntimeReady('flutterwave', {
      publicBaseUrl: 'https://pikipos.com',
      secretConfig: {
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: 'v4-encryption-key',
      },
    }),
    false,
  );
  assert.equal(
    isProviderRuntimeReady('google_play', { publicBaseUrl: '' }),
    true,
  );
});

test('selling mode labels normalize to entitlement modes', () => {
  assert.equal(normalizeSellingMode('Service only'), 'services');
  assert.equal(normalizeSellingMode('Services only'), 'services');
  assert.equal(normalizeSellingMode('Product only'), 'products');
  assert.equal(normalizeSellingMode('Products only'), 'products');
  assert.equal(normalizeSellingMode('Restaurant'), 'restaurant');
  assert.equal(normalizeSellingMode('Food service'), 'restaurant');
  assert.equal(normalizeSellingMode('Products + Services'), 'combo');
});

test('default trial can onboard product, service, and restaurant businesses', () => {
  const trialPlan = DEFAULT_PLANS.find((plan) => plan.code === 'trial');

  assert.ok(trialPlan);
  assert.equal(trialPlan.features.includes('services'), true);
  assert.equal(trialPlan.features.includes('restaurant_mode'), true);
  assert.deepEqual(trialPlan.sellingModes, ['products', 'services', 'restaurant', 'combo']);
  assert.equal(
    validateSellingModeEntitlement(
      {
        features: trialPlan.features,
        allowedSellingModes: trialPlan.sellingModes,
      },
      'Service only',
    ).ok,
    true,
  );
  assert.equal(
    validateSellingModeEntitlement(
      {
        features: trialPlan.features,
        allowedSellingModes: trialPlan.sellingModes,
      },
      'Restaurant',
    ).ok,
    true,
  );
});

test('service selling mode hides product inventory features', () => {
  const entitlements = applySellingModeToEntitlements(
    {
      features: [
        'pos',
        'products',
        'services',
        'categories',
        'purchases',
        'stock_list',
        'transfers',
        'sales',
        'restaurant_mode',
      ],
      allowedSellingModes: ['products', 'services', 'restaurant', 'combo'],
      maxBranches: 3,
      maxEmployees: 10,
      maxAiAgents: 3,
      aiRateLimits: { hourly: 200, weekly: 5000, monthly: 15000 },
    },
    'services',
  );

  assert.equal(entitlements.sellingMode, 'services');
  assert.equal(entitlements.features.includes('services'), true);
  assert.equal(entitlements.features.includes('products'), false);
  assert.equal(entitlements.features.includes('categories'), false);
  assert.equal(entitlements.features.includes('purchases'), false);
  assert.equal(entitlements.features.includes('stock_list'), false);
  assert.equal(entitlements.features.includes('transfers'), false);
  assert.equal(entitlements.features.includes('restaurant_mode'), false);
});

test('product and restaurant registrations receive separate workspaces', () => {
  const source = {
    features: [
      'pos',
      'products',
      'services',
      'categories',
      'sales',
      'restaurant_mode',
    ],
    allowedSellingModes: ['products', 'services', 'restaurant', 'combo'],
  };

  const products = applySellingModeToEntitlements(source, 'products');
  assert.equal(products.sellingMode, 'products');
  assert.equal(products.features.includes('products'), true);
  assert.equal(products.features.includes('restaurant_mode'), false);
  assert.equal(products.features.includes('services'), false);

  const restaurant = applySellingModeToEntitlements(source, 'restaurant');
  assert.equal(restaurant.sellingMode, 'restaurant');
  assert.equal(restaurant.features.includes('restaurant_mode'), true);
  assert.equal(restaurant.features.includes('products'), true);
  assert.equal(restaurant.features.includes('services'), false);
});

test('selling mode validation requires the selected plan to support the mode', () => {
  const productOnlyPlan = {
    features: ['pos', 'products', 'sales'],
    allowedSellingModes: ['products'],
  };
  const comboPlan = {
    features: ['pos', 'products', 'services', 'sales', 'restaurant_mode'],
    allowedSellingModes: ['products', 'services', 'restaurant', 'combo'],
  };

  assert.equal(validateSellingModeEntitlement(productOnlyPlan, 'products').ok, true);
  assert.equal(validateSellingModeEntitlement(productOnlyPlan, 'services').ok, false);
  assert.equal(validateSellingModeEntitlement(productOnlyPlan, 'combo').ok, false);
  assert.deepEqual(validateSellingModeEntitlement(comboPlan, 'restaurant'), {
    ok: true,
    mode: 'restaurant',
  });
  assert.deepEqual(validateSellingModeEntitlement(comboPlan, 'combo'), {
    ok: true,
    mode: 'combo',
  });
});

test('public catalog keeps free plans visible without an active payment gateway', () => {
  assert.equal(
    isPriceAvailableForPublicCatalog(
      {
        isActive: true,
        amountMinor: 0,
        countryCode: 'KE',
      },
      {
        isActive: false,
        countries: ['KE'],
      },
    ),
    true,
  );

  assert.equal(
    isPriceAvailableForPublicCatalog(
      {
        isActive: true,
        amountMinor: 150000,
        countryCode: 'KE',
      },
      {
        isActive: false,
        countries: ['KE'],
      },
    ),
    false,
  );

  assert.equal(
    isPriceAvailableForPublicCatalog(
      {
        isActive: true,
        amountMinor: 150000,
        countryCode: 'KE',
      },
      {
        isActive: true,
        countries: ['KE'],
      },
    ),
    true,
  );
});

test('public catalog visibility follows active plan prices', () => {
  assert.equal(
    isPriceVisibleInPublicCatalog({
      isActive: true,
      amountMinor: 150000,
      countryCode: 'KE',
    }),
    true,
  );

  assert.equal(
    isPriceVisibleInPublicCatalog({
      isActive: false,
      amountMinor: 150000,
      countryCode: 'KE',
    }),
    false,
  );
});

test('only supported subscription providers are enabled', () => {
  assert.equal(isSubscriptionPaymentProviderAllowed('mpesa'), false);
  assert.equal(isSubscriptionPaymentProviderAllowed('google_pay'), false);
  assert.equal(isSubscriptionPaymentProviderAllowed('google_play'), true);
  assert.equal(isSubscriptionPaymentProviderAllowed('paypal'), true);
  assert.equal(isSubscriptionPaymentProviderAllowed('flutterwave'), true);
  assert.equal(isSubscriptionPaymentProviderAllowed('unknown'), false);
});

test('renewal keeps remaining subscription time', () => {
  const now = new Date('2026-05-31T00:00:00.000Z');
  const futureExpiry = new Date('2026-06-15T00:00:00.000Z');
  const expired = new Date('2026-05-01T00:00:00.000Z');

  assert.equal(renewalBaseDate(futureExpiry, now).toISOString(), futureExpiry.toISOString());
  assert.equal(renewalBaseDate(expired, now).toISOString(), now.toISOString());
});

test('trial period accepts whole days within the admin range', () => {
  assert.equal(normalizeTrialDays(30), 30);
  assert.equal(normalizeTrialDays('45'), 45);
  assert.throws(() => normalizeTrialDays(0), /between 1 and 365 days/);
  assert.throws(() => normalizeTrialDays(365.5), /between 1 and 365 days/);
  assert.throws(() => normalizeTrialDays(366), /between 1 and 365 days/);
});

test('grace period accepts whole days within the admin range', () => {
  assert.equal(normalizeGraceDays(5), 5);
  assert.equal(normalizeGraceDays('0'), 0);
  assert.equal(normalizeGraceDays('30'), 30);
  assert.throws(() => normalizeGraceDays(-1), /between 0 and 30 days/);
  assert.throws(() => normalizeGraceDays(5.5), /between 0 and 30 days/);
  assert.throws(() => normalizeGraceDays(31), /between 0 and 30 days/);
});
