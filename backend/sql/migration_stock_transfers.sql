CREATE TABLE IF NOT EXISTS stock_transfers (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  from_branch_id text NOT NULL,
  to_branch_id text NOT NULL,
  product_id text NOT NULL,
  product_name text NOT NULL,
  quantity double precision NOT NULL DEFAULT 0,
  unit text,
  status text NOT NULL DEFAULT 'requested',
  requested_by text,
  approved_by text,
  received_by text,
  note text,
  requested_at timestamptz NOT NULL,
  approved_at timestamptz,
  received_at timestamptz,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS from_branch_id text NOT NULL DEFAULT '';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS to_branch_id text NOT NULL DEFAULT '';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS product_id text NOT NULL DEFAULT '';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS product_name text NOT NULL DEFAULT 'Product';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS quantity double precision NOT NULL DEFAULT 0;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS unit text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'requested';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS requested_by text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS approved_by text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS received_by text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS requested_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS received_at timestamptz;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';

CREATE INDEX IF NOT EXISTS idx_stock_transfers_business_revision
  ON stock_transfers(business_id, server_revision, id);

CREATE INDEX IF NOT EXISTS idx_stock_transfers_branch_status
  ON stock_transfers(business_id, from_branch_id, to_branch_id, status);
