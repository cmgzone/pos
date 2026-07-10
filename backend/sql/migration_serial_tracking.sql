-- Serialized inventory and warranty tracking.

CREATE TABLE IF NOT EXISTS product_serials (
  id text PRIMARY KEY,
  business_id text,
  branch_id text DEFAULT 'main_branch',
  product_id text NOT NULL,
  variant_id text,
  stock_batch_id text,
  purchase_id text,
  sale_id text,
  sale_item_id text,
  serial_number text NOT NULL,
  status text NOT NULL DEFAULT 'available',
  warranty_expires_at text,
  note text,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS variant_id text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS stock_batch_id text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS purchase_id text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS sale_id text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS sale_item_id text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'available';
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS warranty_expires_at text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE product_serials ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';
UPDATE product_serials SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
ALTER TABLE product_serials ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE product_serials ALTER COLUMN server_revision SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_serials_server_revision ON product_serials(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_product_serials_business_revision ON product_serials(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_product_serials_branch_id ON product_serials(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_product_serials_lookup ON product_serials(business_id, serial_number) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_product_serials_product_status ON product_serials(business_id, product_id, status) WHERE deleted_at IS NULL;
