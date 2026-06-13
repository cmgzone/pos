const test = require('node:test');
const assert = require('node:assert/strict');

const { deleteBusinessAccount } = require('../src/businessDeletion');

test('business deletion releases subdomain and invalidates access', async () => {
  const calls = [];
  const target = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      if (/ALTER TABLE|CREATE UNIQUE INDEX|CREATE INDEX|DO\s+\$\$/i.test(sql)) {
        return { rows: [] };
      }
      if (/SELECT id, name, public_subdomain/i.test(sql)) {
        return {
          rows: [
            {
              id: 'business-1',
              name: 'My Shop',
              public_subdomain: 'my-shop',
              deleted_at: null,
              subdomain_released_at: null,
            },
          ],
        };
      }
      if (/UPDATE businesses/i.test(sql)) {
        return {
          rows: [
            {
              id: 'business-1',
              name: 'My Shop',
              deleted_at: params[1],
              subdomain_released_at: params[1],
            },
          ],
        };
      }
      return { rows: [] };
    },
  };

  const result = await deleteBusinessAccount(target, {
    businessId: 'business-1',
    deletedByUserId: 'user-1',
    now: new Date('2026-06-13T10:00:00.000Z'),
  });

  assert.equal(result.deleted, true);
  assert.equal(result.releasedSubdomain, 'my-shop');
  assert.equal(result.deletedAt, '2026-06-13T10:00:00.000Z');
  assert.ok(
    calls.some((call) => /DELETE FROM business_access_tokens/i.test(call.sql)),
  );
  assert.ok(
    calls.some(
      (call) =>
        /UPDATE businesses/i.test(call.sql) &&
        /public_subdomain = NULL/i.test(call.sql),
    ),
  );
  assert.ok(
    calls.some(
      (call) =>
        /UPDATE users/i.test(call.sql) && /deleted_at = COALESCE/i.test(call.sql),
    ),
  );
});

test('business deletion is idempotent for already deleted businesses', async () => {
  const calls = [];
  const target = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      if (/ALTER TABLE|CREATE UNIQUE INDEX|CREATE INDEX|DO\s+\$\$/i.test(sql)) {
        return { rows: [] };
      }
      if (/SELECT id, name, public_subdomain/i.test(sql)) {
        return {
          rows: [
            {
              id: 'business-1',
              name: 'My Shop',
              public_subdomain: null,
              deleted_at: '2026-06-13T10:00:00.000Z',
              subdomain_released_at: '2026-06-13T10:00:00.000Z',
            },
          ],
        };
      }
      throw new Error(`Unexpected SQL in test: ${sql}`);
    },
  };

  const result = await deleteBusinessAccount(target, {
    businessId: 'business-1',
  });

  assert.equal(result.deleted, false);
  assert.equal(result.alreadyDeleted, true);
  assert.equal(result.releasedSubdomain, null);
  assert.equal(
    calls.some((call) => /DELETE FROM business_access_tokens/i.test(call.sql)),
    false,
  );
});
