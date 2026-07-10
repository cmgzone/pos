CREATE TABLE IF NOT EXISTS restaurant_tables (
  id text PRIMARY KEY, business_id text, branch_id text, name text NOT NULL,
  area text, seats integer NOT NULL DEFAULT 2, status text NOT NULL DEFAULT 'available',
  position_x double precision NOT NULL DEFAULT 0, position_y double precision NOT NULL DEFAULT 0,
  current_order_id text, server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz, sync_status text NOT NULL DEFAULT 'synced'
);
CREATE TABLE IF NOT EXISTS table_orders (
  id text PRIMARY KEY, business_id text, branch_id text, table_id text NOT NULL,
  order_no text NOT NULL, status text NOT NULL DEFAULT 'open', guest_count integer NOT NULL DEFAULT 1,
  notes text, items_json text NOT NULL DEFAULT '[]', subtotal double precision NOT NULL DEFAULT 0,
  tax double precision NOT NULL DEFAULT 0, discount double precision NOT NULL DEFAULT 0,
  total double precision NOT NULL DEFAULT 0, split_count integer NOT NULL DEFAULT 1,
  opened_by text, opened_at timestamptz NOT NULL DEFAULT now(), closed_at timestamptz,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz, sync_status text NOT NULL DEFAULT 'synced'
);
ALTER TABLE restaurant_tables ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE table_orders ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
CREATE INDEX IF NOT EXISTS idx_restaurant_tables_branch_status ON restaurant_tables(business_id, branch_id, status);
CREATE INDEX IF NOT EXISTS idx_table_orders_branch_status ON table_orders(business_id, branch_id, status, updated_at DESC);
