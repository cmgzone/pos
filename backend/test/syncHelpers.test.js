const test = require('node:test');
const assert = require('node:assert/strict');

const {
  SERVER_SYNC_STATUS,
  buildRejectedWriteResult,
  canonicalizeRecord,
  compareTimestamps,
  prepareIncomingRecord,
} = require('../src/syncHelpers');

test('prepareIncomingRecord forces synced status and normalizes timestamps', () => {
  const result = prepareIncomingRecord('products', {
    id: '  product-1  ',
    name: 'Sugar',
    price: 2500,
    created_at: '2026-04-16T12:00:00-07:00',
    updated_at: '2026-04-17T12:00:00-07:00',
    deleted_at: '',
    sync_status: 'pending',
  });

  assert.equal(result.ok, true);
  assert.equal(result.record.id, 'product-1');
  assert.equal(result.record.sync_status, SERVER_SYNC_STATUS);
  assert.equal(result.record.created_at, '2026-04-16T19:00:00.000Z');
  assert.equal(result.record.updated_at, '2026-04-17T19:00:00.000Z');
  assert.equal(result.record.deleted_at, null);
});

test('prepareIncomingRecord rejects invalid required timestamps', () => {
  const result = prepareIncomingRecord('products', {
    id: 'product-1',
    name: 'Sugar',
    updated_at: 'not-a-date',
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'invalid_timestamp');
  assert.equal(result.error.field, 'updated_at');
});

test('prepareIncomingRecord requires non-nullable timestamps like received_at', () => {
  const result = prepareIncomingRecord('credit_payments', {
    id: 'payment-1',
    payment_group_id: 'group-1',
    customer_id: 'customer-1',
    amount: 500,
    created_at: '2026-04-17T19:00:00.000Z',
    updated_at: '2026-04-17T19:00:00.000Z',
  });

  assert.equal(result.ok, false);
  assert.equal(result.error.code, 'missing_timestamp');
  assert.equal(result.error.field, 'received_at');
});

test('prepareIncomingRecord accepts nullable sales integration timestamps', () => {
  const result = prepareIncomingRecord('sales', {
    id: 'sale-1',
    branch_id: 'main_branch',
    total_amount: 200,
    tax: 0,
    discount: 0,
    payment_type: 'cash',
    is_cash_drawer: 0,
    user_id: 'user-1',
    etims_submitted_at: null,
    refunded_at: '',
    created_at: '2026-04-17T19:00:00.000Z',
    updated_at: '2026-04-17T19:00:00.000Z',
  });

  assert.equal(result.ok, true);
  assert.equal(result.record.etims_submitted_at, null);
  assert.equal(result.record.refunded_at, null);
});

test('prepareIncomingRecord accepts nullable service order timestamps', () => {
  const result = prepareIncomingRecord('service_orders', {
    id: 'service-order-1',
    branch_id: 'main_branch',
    service_id: 'service-1',
    service_name: 'Car wash',
    entry_mode: 'walk_in',
    scheduled_at: null,
    checked_in_at: '',
    status: 'paid',
    price: 200,
    created_at: '2026-04-17T19:00:00.000Z',
    updated_at: '2026-04-17T19:00:00.000Z',
  });

  assert.equal(result.ok, true);
  assert.equal(result.record.scheduled_at, null);
  assert.equal(result.record.checked_in_at, null);
});

test('prepareIncomingRecord accepts nullable stock transfer completion timestamps', () => {
  const result = prepareIncomingRecord('stock_transfers', {
    id: 'transfer-1',
    branch_id: 'main_branch',
    from_branch_id: 'main_branch',
    to_branch_id: 'branch-2',
    product_id: 'product-1',
    product_name: 'Soap',
    quantity: 2,
    status: 'requested',
    requested_at: '2026-04-17T19:00:00.000Z',
    approved_at: null,
    received_at: '',
    created_at: '2026-04-17T19:00:00.000Z',
    updated_at: '2026-04-17T19:00:00.000Z',
  });

  assert.equal(result.ok, true);
  assert.equal(result.record.approved_at, null);
  assert.equal(result.record.received_at, null);
});

test('buildRejectedWriteResult treats equivalent synced rows as duplicates', () => {
  const incoming = {
    id: 'product-1',
    name: 'Sugar',
    price: 2500,
    created_at: '2026-04-16T19:00:00.000Z',
    updated_at: '2026-04-17T19:00:00.000Z',
    sync_status: 'synced',
  };
  const existing = {
    id: 'product-1',
    name: 'Sugar',
    price: 2500,
    created_at: new Date('2026-04-16T19:00:00.000Z'),
    updated_at: new Date('2026-04-17T19:00:00.000Z'),
    sync_status: 'pending',
  };

  const result = buildRejectedWriteResult('products', incoming, existing);

  assert.deepEqual(result, { status: 'duplicate' });
});

test('buildRejectedWriteResult returns stale_update conflicts with synced server rows', () => {
  const result = buildRejectedWriteResult(
    'products',
    {
      id: 'product-1',
      name: 'Sugar',
      price: 2500,
      created_at: '2026-04-16T19:00:00.000Z',
      updated_at: '2026-04-17T19:00:00.000Z',
      sync_status: 'synced',
    },
    {
      id: 'product-1',
      name: 'Sugar',
      price: 2600,
      created_at: '2026-04-16T19:00:00.000Z',
      updated_at: '2026-04-17T20:00:00.000Z',
      sync_status: 'pending',
    },
  );

  assert.equal(result.status, 'conflict');
  assert.equal(result.conflict.reason, 'stale_update');
  assert.equal(result.conflict.serverRow.sync_status, SERVER_SYNC_STATUS);
  assert.equal(result.conflict.serverRow.price, 2600);
});

test('buildRejectedWriteResult distinguishes same timestamp conflicts', () => {
  const result = buildRejectedWriteResult(
    'products',
    {
      id: 'product-1',
      name: 'Sugar',
      price: 2500,
      created_at: '2026-04-16T19:00:00.000Z',
      updated_at: '2026-04-17T19:00:00.000Z',
      sync_status: 'synced',
    },
    {
      id: 'product-1',
      name: 'Brown Sugar',
      price: 2500,
      created_at: '2026-04-16T19:00:00.000Z',
      updated_at: '2026-04-17T19:00:00.000Z',
      sync_status: 'synced',
    },
  );

  assert.equal(result.status, 'conflict');
  assert.equal(result.conflict.reason, 'same_timestamp');
});

test('canonicalizeRecord can force synced output for pulled rows', () => {
  const normalized = canonicalizeRecord(
    'products',
    {
      id: 'product-1',
      updated_at: new Date('2026-04-17T19:00:00.000Z'),
      sync_status: 'pending',
    },
    { forceSyncedStatus: true },
  );

  assert.equal(normalized.updated_at, '2026-04-17T19:00:00.000Z');
  assert.equal(normalized.sync_status, SERVER_SYNC_STATUS);
});

test('canonicalizeRecord redacts user passwords from client output', () => {
  const normalized = canonicalizeRecord(
    'users',
    {
      id: 'user-1',
      name: 'Cashier',
      email: 'cashier@example.com',
      password: 'velora.server.v1$210000$salt$digest',
      role: 'CASHIER',
      created_at: '2026-04-17T19:00:00.000Z',
      updated_at: '2026-04-17T19:00:00.000Z',
      sync_status: 'synced',
    },
    { forceSyncedStatus: true },
  );

  assert.equal(Object.hasOwn(normalized, 'password'), false);
  assert.equal(normalized.sync_status, SERVER_SYNC_STATUS);
});

test('compareTimestamps handles equal instants across time zones', () => {
  assert.equal(
    compareTimestamps('2026-04-17T12:00:00-07:00', '2026-04-17T19:00:00.000Z'),
    0,
  );
});
