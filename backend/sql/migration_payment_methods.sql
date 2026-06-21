-- ══════════════════════════════════════════════════════════════════════════════
-- Payment Methods Migration
-- Adds payment_methods table and updates sales table for flexible payment system
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Payment Methods Table ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS payment_methods (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  provider_key text,
  is_cash_drawer integer NOT NULL DEFAULT 0,
  is_credit integer NOT NULL DEFAULT 0,
  is_active integer NOT NULL DEFAULT 1,
  sort_order integer NOT NULL DEFAULT 0,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

-- Indexes for cursor-based sync
CREATE INDEX IF NOT EXISTS idx_payment_methods_business_revision 
  ON payment_methods(business_id, server_revision, id);

-- Lookup indexes
CREATE INDEX IF NOT EXISTS idx_payment_methods_business_active 
  ON payment_methods(business_id, is_active) WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_payment_methods_sort_order 
  ON payment_methods(business_id, sort_order, name) WHERE deleted_at IS NULL;

ALTER TABLE payment_methods ADD COLUMN IF NOT EXISTS provider_key text;
UPDATE payment_methods
SET provider_key = CASE
  WHEN is_cash_drawer = 1 THEN 'cash'
  WHEN is_credit = 1 OR lower(name) LIKE '%kopesha%' THEN 'kopesha'
  WHEN lower(name) LIKE '%mpesa%' OR lower(name) LIKE '%m-pesa%' THEN 'mpesa'
  WHEN lower(name) LIKE '%card%' THEN 'card'
  WHEN lower(name) LIKE '%bank%' OR lower(name) LIKE '%transfer%' THEN 'bank_transfer'
  ELSE 'other'
END
WHERE provider_key IS NULL OR btrim(provider_key) = '';

-- ── Update Sales Table ────────────────────────────────────────────────────────

-- Add is_cash_drawer column to sales table
ALTER TABLE sales ADD COLUMN IF NOT EXISTS is_cash_drawer integer NOT NULL DEFAULT 0;

-- Create index for cash drawer queries
CREATE INDEX IF NOT EXISTS idx_sales_is_cash_drawer 
  ON sales(business_id, is_cash_drawer) WHERE deleted_at IS NULL;

-- ── Seed Default Payment Methods ──────────────────────────────────────────────
-- Note: This should be run per business, not globally
-- The application should handle seeding default payment methods when a new business is created

-- Example seed for existing businesses (run this manually per business):
/*
INSERT INTO payment_methods (
  id, business_id, name, is_cash_drawer, is_credit, is_active, 
  sort_order, created_at, updated_at, sync_status
)
SELECT 
  gen_random_uuid()::text,
  b.id,
  'Cash',
  1, -- is_cash_drawer
  0, -- is_credit
  1, -- is_active
  0, -- sort_order
  NOW(),
  NOW(),
  'synced'
FROM businesses b
WHERE NOT EXISTS (
  SELECT 1 FROM payment_methods pm 
  WHERE pm.business_id = b.id AND pm.name = 'Cash'
);

INSERT INTO payment_methods (
  id, business_id, name, is_cash_drawer, is_credit, is_active, 
  sort_order, created_at, updated_at, sync_status
)
SELECT 
  gen_random_uuid()::text,
  b.id,
  'Kopesha',
  0, -- is_cash_drawer
  1, -- is_credit
  1, -- is_active
  1, -- sort_order
  NOW(),
  NOW(),
  'synced'
FROM businesses b
WHERE NOT EXISTS (
  SELECT 1 FROM payment_methods pm 
  WHERE pm.business_id = b.id AND pm.name = 'Kopesha'
);

INSERT INTO payment_methods (
  id, business_id, name, is_cash_drawer, is_credit, is_active, 
  sort_order, created_at, updated_at, sync_status
)
SELECT 
  gen_random_uuid()::text,
  b.id,
  'M-Pesa',
  0, -- is_cash_drawer
  0, -- is_credit
  1, -- is_active
  2, -- sort_order
  NOW(),
  NOW(),
  'synced'
FROM businesses b
WHERE NOT EXISTS (
  SELECT 1 FROM payment_methods pm 
  WHERE pm.business_id = b.id AND pm.name = 'M-Pesa'
);

INSERT INTO payment_methods (
  id, business_id, name, is_cash_drawer, is_credit, is_active, 
  sort_order, created_at, updated_at, sync_status
)
SELECT 
  gen_random_uuid()::text,
  b.id,
  'Card',
  0, -- is_cash_drawer
  0, -- is_credit
  1, -- is_active
  3, -- sort_order
  NOW(),
  NOW(),
  'synced'
FROM businesses b
WHERE NOT EXISTS (
  SELECT 1 FROM payment_methods pm 
  WHERE pm.business_id = b.id AND pm.name = 'Card'
);

INSERT INTO payment_methods (
  id, business_id, name, is_cash_drawer, is_credit, is_active, 
  sort_order, created_at, updated_at, sync_status
)
SELECT 
  gen_random_uuid()::text,
  b.id,
  'Bank Transfer',
  0, -- is_cash_drawer
  0, -- is_credit
  1, -- is_active
  4, -- sort_order
  NOW(),
  NOW(),
  'synced'
FROM businesses b
WHERE NOT EXISTS (
  SELECT 1 FROM payment_methods pm 
  WHERE pm.business_id = b.id AND pm.name = 'Bank Transfer'
);
*/

-- ── Backfill is_cash_drawer for existing sales ────────────────────────────────
-- Set is_cash_drawer = 1 for sales with payment_type = 'cash'
UPDATE sales 
SET is_cash_drawer = 1 
WHERE LOWER(payment_type) = 'cash' 
  AND is_cash_drawer = 0
  AND deleted_at IS NULL;

-- ══════════════════════════════════════════════════════════════════════════════
-- End of Payment Methods Migration
-- ══════════════════════════════════════════════════════════════════════════════
