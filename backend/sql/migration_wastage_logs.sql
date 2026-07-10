CREATE TABLE IF NOT EXISTS wastage_logs (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  product_id text NOT NULL,
  product_name text NOT NULL,
  quantity double precision NOT NULL DEFAULT 0,
  unit text,
  unit_cost double precision NOT NULL DEFAULT 0,
  reason text NOT NULL DEFAULT 'wastage',
  note text,
  recorded_by text,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS product_id text NOT NULL DEFAULT '';
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS product_name text NOT NULL DEFAULT 'Product';
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS quantity double precision NOT NULL DEFAULT 0;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS unit text;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS unit_cost double precision NOT NULL DEFAULT 0;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS reason text NOT NULL DEFAULT 'wastage';
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS recorded_by text;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS recorded_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE wastage_logs ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';

CREATE INDEX IF NOT EXISTS idx_wastage_logs_business_revision ON wastage_logs(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_wastage_logs_branch_recorded ON wastage_logs(business_id, branch_id, recorded_at DESC);
