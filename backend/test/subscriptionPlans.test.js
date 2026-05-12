const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applySellingModeToEntitlements,
  validateSellingModeEntitlement,
} = require('../src/subscriptionPlans');

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
