CREATE TABLE IF NOT EXISTS stocktake_sessions (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  started_by text,
  completed_by text,
  started_at timestamptz,
  completed_at timestamptz,
  note text,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS stocktake_items (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  session_id text NOT NULL,
  product_id text NOT NULL,
  product_name text NOT NULL,
  expected_qty double precision NOT NULL DEFAULT 0,
  counted_qty double precision,
  variance_qty double precision NOT NULL DEFAULT 0,
  unit text,
  unit_cost double precision NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending',
  note text,
  counted_at timestamptz,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS name text NOT NULL DEFAULT 'Stocktake';
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft';
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS started_by text;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS completed_by text;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS completed_at timestamptz;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE stocktake_sessions ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';

ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS session_id text NOT NULL DEFAULT '';
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS product_id text NOT NULL DEFAULT '';
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS product_name text NOT NULL DEFAULT 'Product';
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS expected_qty double precision NOT NULL DEFAULT 0;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS counted_qty double precision;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS variance_qty double precision NOT NULL DEFAULT 0;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS unit text;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS unit_cost double precision NOT NULL DEFAULT 0;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending';
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS counted_at timestamptz;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE stocktake_items ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';

CREATE INDEX IF NOT EXISTS idx_stocktake_sessions_business_revision ON stocktake_sessions(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_stocktake_sessions_branch_status ON stocktake_sessions(business_id, branch_id, status);
CREATE INDEX IF NOT EXISTS idx_stocktake_items_business_revision ON stocktake_items(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_stocktake_items_session ON stocktake_items(business_id, session_id, status);
