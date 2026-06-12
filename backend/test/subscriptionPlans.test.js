const test = require('node:test');
const assert = require('node:assert/strict');

const {
  DEFAULT_PLANS,
  applySellingModeToEntitlements,
  isPriceAvailableForPublicCatalog,
  isPriceVisibleInPublicCatalog,
  isPlausibleMpesaPasskey,
  normalizeSellingMode,
  normalizeGraceDays,
  normalizeTrialDays,
  renewalBaseDate,
  validatePaymentGatewayConfiguration,
  validateSellingModeEntitlement,
} = require('../src/subscriptionPlans');

test('selling mode labels normalize to entitlement modes', () => {
  assert.equal(normalizeSellingMode('Service only'), 'services');
  assert.equal(normalizeSellingMode('Services only'), 'services');
  assert.equal(normalizeSellingMode('Product only'), 'products');
  assert.equal(normalizeSellingMode('Products only'), 'products');
  assert.equal(normalizeSellingMode('Products + Services'), 'combo');
});

test('default trial can onboard service businesses', () => {
  const trialPlan = DEFAULT_PLANS.find((plan) => plan.code === 'trial');

  assert.ok(trialPlan);
  assert.equal(trialPlan.features.includes('services'), true);
  assert.deepEqual(trialPlan.sellingModes, ['products', 'services', 'combo']);
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
      ],
      allowedSellingModes: ['products', 'services', 'combo'],
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
});

test('selling mode validation requires the selected plan to support the mode', () => {
  const productOnlyPlan = {
    features: ['pos', 'products', 'sales'],
    allowedSellingModes: ['products'],
  };
  const comboPlan = {
    features: ['pos', 'products', 'services', 'sales'],
    allowedSellingModes: ['products', 'services', 'combo'],
  };

  assert.equal(validateSellingModeEntitlement(productOnlyPlan, 'products').ok, true);
  assert.equal(validateSellingModeEntitlement(productOnlyPlan, 'services').ok, false);
  assert.equal(validateSellingModeEntitlement(productOnlyPlan, 'combo').ok, false);
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

test('active M-Pesa gateway requires a valid HTTPS callback URL', () => {
  assert.throws(
    () =>
      validatePaymentGatewayConfiguration({
        provider: 'mpesa',
        isActive: true,
        publicConfig: {
          baseUrl: 'https://sandbox.safaricom.co.ke',
          shortcode: '123456',
          callbackUrl: 'superadmin@example.com',
        },
        secretConfig: {
          consumerKey: 'key',
          consumerSecret: 'secret',
          passkey: 'passkey',
        },
      }),
    /callback URL must be a valid HTTPS URL/,
  );
});

test('M-Pesa passkey rejects login passwords and certificate-sized values', () => {
  assert.equal(isPlausibleMpesaPasskey('short-password'), false);
  assert.equal(isPlausibleMpesaPasskey('x'.repeat(344)), false);
  assert.equal(isPlausibleMpesaPasskey('x'.repeat(64)), true);
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
