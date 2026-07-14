const test = require('node:test');
const assert = require('node:assert/strict');

const {
  issueLicense,
  resolveSubscriptionState,
  verifyLicenseToken,
} = require('../src/licenseTokens');

test('issueLicense signs a stable base64 payload with Ed25519', () => {
  const license = issueLicense({
    businessId: 'biz-1',
    businessName: 'Velora Demo',
    deviceId: 'device-1',
    subscription: {
      plan: 'trial',
      status: 'active',
      expires_at: '2026-05-01T00:00:00.000Z',
      grace_until: '2026-05-05T00:00:00.000Z',
    },
    entitlements: {
      features: ['pos', 'agent'],
      maxBranches: 1,
      maxEmployees: 2,
      maxAiAgents: 1,
      aiRateLimits: { hourly: 20, weekly: 200, monthly: 500 },
    },
    issuedAt: new Date('2026-04-18T12:00:00.000Z'),
  });

  assert.equal(license.payload.business_id, 'biz-1');
  assert.equal(license.payload.status, 'active');
  assert.equal(license.payload.selling_mode, 'combo');
  assert.deepEqual(license.payload.entitlements.features, ['pos', 'agent']);
  assert.equal(license.payload.entitlements.maxBranches, 1);
  assert.equal(license.alg, 'ed25519');
  assert.ok(license.signature && license.signature.length > 0);

  const verified = verifyLicenseToken({
    payloadBase64: license.payloadBase64,
    signature: license.signature,
    alg: license.alg,
  });
  assert.equal(verified, true);
});

test('verifyLicenseToken rejects a tampered payload', () => {
  const license = issueLicense({
    businessId: 'biz-1',
    businessName: 'Velora Demo',
    deviceId: 'device-1',
    subscription: {
      plan: 'trial',
      status: 'active',
      expires_at: '2026-05-01T00:00:00.000Z',
      grace_until: '2026-05-05T00:00:00.000Z',
    },
    issuedAt: new Date('2026-04-18T12:00:00.000Z'),
  });

  const tampered = license.payloadBase64 + 'tampered';
  assert.equal(
    verifyLicenseToken({
      payloadBase64: tampered,
      signature: license.signature,
      alg: license.alg,
    }),
    false,
  );
  assert.equal(
    verifyLicenseToken({
      payloadBase64: license.payloadBase64,
      signature: license.signature,
      alg: 'hmac',
    }),
    false,
  );
});

test('resolveSubscriptionState enters grace after expires_at', () => {
  const state = resolveSubscriptionState(
    {
      status: 'active',
      expires_at: '2026-04-18T00:00:00.000Z',
      grace_until: '2026-04-20T00:00:00.000Z',
    },
    new Date('2026-04-19T00:00:00.000Z'),
  );

  assert.deepEqual(state, {
    status: 'grace',
    usable: true,
  });
});

test('resolveSubscriptionState expires after grace_until', () => {
  const state = resolveSubscriptionState(
    {
      status: 'active',
      expires_at: '2026-04-18T00:00:00.000Z',
      grace_until: '2026-04-20T00:00:00.000Z',
    },
    new Date('2026-04-21T00:00:00.000Z'),
  );

  assert.deepEqual(state, {
    status: 'expired',
    usable: false,
  });
});
