const test = require('node:test');
const assert = require('node:assert/strict');

const { isDeviceActivationCompatible } = require('../src/businessAccess');

test('device activation allows the same business name with case changes', () => {
  const allowed = isDeviceActivationCompatible({
    existingBusinessName: 'Piki Shop',
    requestedBusinessName: '  piki shop  ',
  });

  assert.equal(allowed, true);
});

test('device activation rejects a different business name on the same device', () => {
  const allowed = isDeviceActivationCompatible({
    existingBusinessName: 'Piki Shop',
    requestedBusinessName: 'Other Business',
  });

  assert.equal(allowed, false);
});
