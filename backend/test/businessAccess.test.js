const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ensureDeviceUserSchema,
  isDeviceActivationCompatible,
} = require('../src/businessAccess');

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

test('device schema binds devices to authenticated users', async () => {
  const statements = [];
  await ensureDeviceUserSchema(async (sql) => {
    statements.push(sql);
    return { rows: [] };
  });

  assert.equal(statements.length, 2);
  assert.match(statements[0], /ADD COLUMN IF NOT EXISTS user_id text/i);
  assert.match(statements[1], /idx_devices_user_id/i);
});
