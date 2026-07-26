const test = require('node:test');
const assert = require('node:assert/strict');

const VALID_V4_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');

const {
  DEFAULT_PLANS,
  applySellingModeToEntitlements,
  buildFlutterwaveWebhookUrl,
  flutterwaveWebhookFingerprint,
  isPriceAvailableForPublicCatalog,
  isPriceVisibleInPublicCatalog,
  isProviderRuntimeReady,
  isSubscriptionPaymentProviderAllowed,
  listPublicMarkets,
  normalizeSellingMode,
  normalizeGraceDays,
  normalizePublicHttpsOrigin,
  normalizeTrialDays,
  resolveFlutterwaveWebhookStatus,
  renewalBaseDate,
  validatePaymentGatewayConfiguration,
  validateSellingModeEntitlement,
} = require('../src/subscriptionPlans');

test('public market readiness query projects gateway secrets for server-side checks', async () => {
  let publicMarketsSql = '';
  await listPublicMarkets(async (sql) => {
    if (sql.includes('SELECT DISTINCT') && sql.includes('ORDER BY sort_rank')) {
      publicMarketsSql = sql;
    }
    return { rows: [] };
  });

  assert.ok(publicMarketsSql, 'expected the public markets query to run');
  const outerSelect = publicMarketsSql.slice(
    publicMarketsSql.indexOf('SELECT'),
    publicMarketsSql.indexOf('FROM ('),
  );
  assert.match(outerSelect, /\bsecret_config_json\b/);
});

test('Flutterwave accepts complete v3 and v4 credential sets together', () => {
  assert.doesNotThrow(() =>
    validatePaymentGatewayConfiguration({
      provider: 'flutterwave',
      isActive: true,
      publicConfig: {
        apiVersion: 'v4',
        baseUrl: 'https://api.flutterwave.com/v3',
      },
      secretConfig: {
        secretKey: 'FLWSECK_TEST-example',
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
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
      publicConfig: { apiVersion: 'v4' },
      secretConfig: {
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
        webhookHash: 'webhook-secret',
      },
    }),
  );
});

test('Flutterwave rejects active v4 checkout without a webhook secret hash', () => {
  assert.throws(
    () =>
      validatePaymentGatewayConfiguration({
        provider: 'flutterwave',
        isActive: true,
        publicConfig: { apiVersion: 'v4' },
        secretConfig: {
          clientId: 'v4-client-id',
          clientSecret: 'v4-client-secret',
          encryptionKey: VALID_V4_ENCRYPTION_KEY,
        },
      }),
    /v4 Webhook Secret Hash is required/,
  );
});

test('Flutterwave allows incomplete v4 recovery settings while inactive', () => {
  assert.doesNotThrow(() =>
    validatePaymentGatewayConfiguration({
      provider: 'flutterwave',
      isActive: false,
      publicConfig: { apiVersion: 'v4' },
      secretConfig: {
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
      },
    }),
  );
});

test('Flutterwave accepts complete v4 credentials alongside partial legacy v3 settings', () => {
  assert.doesNotThrow(() =>
    validatePaymentGatewayConfiguration({
      provider: 'flutterwave',
      isActive: true,
      publicConfig: { apiVersion: 'v4' },
      secretConfig: {
        webhookHash: 'legacy-webhook-only',
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
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
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
      },
    }),
    false,
  );
  assert.equal(
    isProviderRuntimeReady('flutterwave', {
      publicBaseUrl: 'https://pikipos.com',
      secretConfig: {
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
        webhookHash: 'webhook-secret',
      },
      publicConfig: { apiVersion: 'v4' },
    }),
    false,
  );
  const verifiedWebhookFingerprint = flutterwaveWebhookFingerprint({
    webhookUrl:
      'https://pikipos.com/api/subscription/flutterwave/webhook',
    webhookHash: 'webhook-secret',
  });
  assert.equal(
    isProviderRuntimeReady('flutterwave', {
      publicBaseUrl: 'https://pikipos.com',
      secretConfig: {
        clientId: 'v4-client-id',
        clientSecret: 'v4-client-secret',
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
        webhookHash: 'webhook-secret',
      },
      publicConfig: {
        apiVersion: 'v4',
        webhookVerificationFingerprint: verifiedWebhookFingerprint,
        webhookLastVerifiedAt: '2026-07-27T10:00:00.000Z',
      },
    }),
    true,
  );
  assert.equal(
    isProviderRuntimeReady('flutterwave', {
      publicBaseUrl: 'https://pikipos.com',
      secretConfig: {
        clientId: 'v4-client-id',
        clientSecret: 'changed-client-secret',
        encryptionKey: VALID_V4_ENCRYPTION_KEY,
        webhookHash: 'changed-webhook-secret',
      },
      publicConfig: {
        apiVersion: 'v4',
        webhookVerificationFingerprint: verifiedWebhookFingerprint,
        webhookLastVerifiedAt: '2026-07-27T10:00:00.000Z',
      },
    }),
    false,
  );
  assert.equal(
    isProviderRuntimeReady('google_play', { publicBaseUrl: '' }),
    true,
  );
});

test('Flutterwave callback URL is derived from backend PUBLIC_BASE_URL', () => {
  assert.equal(
    buildFlutterwaveWebhookUrl('https://api.pikipos.com/'),
    'https://api.pikipos.com/api/subscription/flutterwave/webhook',
  );
  assert.equal(buildFlutterwaveWebhookUrl('http://localhost:3000'), null);
  assert.equal(buildFlutterwaveWebhookUrl(''), null);
});

test('payment callback origins are canonical public HTTPS origins', () => {
  assert.equal(
    normalizePublicHttpsOrigin('https://API.PikiPOS.com:443/'),
    'https://api.pikipos.com',
  );
  assert.equal(
    normalizePublicHttpsOrigin('https://api.pikipos.com:8443'),
    'https://api.pikipos.com:8443',
  );
  assert.equal(
    buildFlutterwaveWebhookUrl('https://[2606:4700:4700::1111]'),
    'https://[2606:4700:4700::1111]/api/subscription/flutterwave/webhook',
  );

  for (const invalid of [
    'http://api.pikipos.com',
    'https://user:password@api.pikipos.com',
    'https://api.pikipos.com/backend',
    'https://api.pikipos.com?mode=test',
    'https://api.pikipos.com#webhook',
    'https://localhost',
    'https://shop.local',
    'https://127.0.0.1',
    'https://10.0.0.1',
    'https://172.20.0.1',
    'https://192.168.1.1',
    'https://169.254.10.2',
    'https://[::1]',
    'https://[fc00::1]',
    'https://[fe80::1]',
    'https://[::ffff:127.0.0.1]',
  ]) {
    assert.equal(normalizePublicHttpsOrigin(invalid), null, invalid);
    assert.equal(buildFlutterwaveWebhookUrl(invalid), null, invalid);
  }
});

test('Flutterwave signed webhook verification is bound to URL and secret', () => {
  const webhookUrl =
    'https://api.pikipos.com/api/subscription/flutterwave/webhook';
  const fingerprint = flutterwaveWebhookFingerprint({
    webhookUrl,
    webhookHash: 'webhook-secret',
  });
  const publicConfig = {
    webhookVerificationFingerprint: fingerprint,
    webhookLastVerifiedAt: '2026-07-27T10:00:00.000Z',
  };

  assert.deepEqual(
    resolveFlutterwaveWebhookStatus({
      publicBaseUrl: 'https://api.pikipos.com',
      webhookHash: 'webhook-secret',
      publicConfig,
    }),
    {
      webhookUrl,
      callbackUrl: webhookUrl,
      webhookConfigured: true,
      webhookVerified: true,
      webhookLastVerifiedAt: '2026-07-27T10:00:00.000Z',
    },
  );
  assert.equal(
    resolveFlutterwaveWebhookStatus({
      publicBaseUrl: 'https://new-api.pikipos.com',
      webhookHash: 'webhook-secret',
      publicConfig,
    }).webhookVerified,
    false,
  );
  assert.equal(
    resolveFlutterwaveWebhookStatus({
      publicBaseUrl: 'https://api.pikipos.com',
      webhookHash: 'changed-secret',
      publicConfig,
    }).webhookVerified,
    false,
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
