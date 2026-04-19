const test = require('node:test');
const assert = require('node:assert/strict');

const {
  issueLicense,
  resolveSubscriptionState,
  signPayload,
} = require('../src/licenseTokens');

test('issueLicense signs a stable base64 payload', () => {
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

  assert.equal(license.payload.business_id, 'biz-1');
  assert.equal(license.payload.status, 'active');
  assert.equal(license.signature, signPayload(license.payloadBase64));
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
