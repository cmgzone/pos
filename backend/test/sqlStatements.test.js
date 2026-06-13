const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const { splitSqlStatements } = require('../src/sqlStatements');

test('splitSqlStatements keeps semicolons inside string literals', () => {
  const sql = `
    CREATE TABLE notes (
      id text PRIMARY KEY,
      body text DEFAULT 'hello;world'
    );
    INSERT INTO notes (id, body) VALUES ('1', 'done;still one value');
  `;

  assert.deepEqual(splitSqlStatements(sql), [
    `CREATE TABLE notes (
      id text PRIMARY KEY,
      body text DEFAULT 'hello;world'
    )`,
    `INSERT INTO notes (id, body) VALUES ('1', 'done;still one value')`,
  ]);
});

test('splitSqlStatements ignores semicolons inside comments and dollar quotes', () => {
  const sql = `
    -- create helper; still same statement
    SELECT $$value;inside$$ AS payload;
    /* block comment; same rule */
    SELECT 2;
  `;

  assert.deepEqual(splitSqlStatements(sql), [
    `-- create helper; still same statement
    SELECT $$value;inside$$ AS payload`,
    `/* block comment; same rule */
    SELECT 2`,
  ]);
});

test('database initialization includes conflict-safe POS effect tables', () => {
  const sql = fs.readFileSync(
    path.resolve(__dirname, '..', 'sql', 'init.sql'),
    'utf8',
  );

  assert.match(sql, /CREATE TABLE IF NOT EXISTS sync_credit_payment_effects/i);
  assert.match(sql, /CREATE TABLE IF NOT EXISTS sync_refund_balance_effects/i);
  assert.match(sql, /CREATE TABLE IF NOT EXISTS sync_sale_credit_baselines/i);
  assert.match(sql, /ALTER TABLE devices ADD COLUMN IF NOT EXISTS user_id text/i);
  assert.match(
    sql,
    /ALTER TABLE public_catalog_orders[\s\S]+ADD COLUMN IF NOT EXISTS branch_id/i,
  );
  assert.match(
    sql,
    /ALTER TABLE businesses ADD COLUMN IF NOT EXISTS public_subdomain text/i,
  );
  assert.match(
    sql,
    /ALTER TABLE businesses ADD COLUMN IF NOT EXISTS deleted_at timestamptz/i,
  );
  assert.match(
    sql,
    /ALTER TABLE businesses ADD COLUMN IF NOT EXISTS subdomain_released_at timestamptz/i,
  );
  assert.match(sql, /idx_businesses_public_subdomain_unique/i);
  assert.match(sql, /DROP INDEX idx_businesses_public_subdomain_unique/i);
  assert.match(sql, /public_subdomain IS NOT NULL\s+AND deleted_at IS NULL/i);
});
