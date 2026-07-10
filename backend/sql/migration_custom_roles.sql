-- Custom roles and reusable staff permission templates.

CREATE TABLE IF NOT EXISTS custom_roles (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  name text NOT NULL,
  description text,
  base_role text NOT NULL DEFAULT 'CASHIER',
  feature_access_json text,
  allowed_service_ids_json text,
  allowed_branch_ids_json text,
  pos_mode text NOT NULL DEFAULT 'both',
  service_order_scope text NOT NULL DEFAULT 'all_visible_services',
  is_active integer NOT NULL DEFAULT 1,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS base_role text NOT NULL DEFAULT 'CASHIER';
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS feature_access_json text;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS allowed_service_ids_json text;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS allowed_branch_ids_json text;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS pos_mode text NOT NULL DEFAULT 'both';
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS service_order_scope text NOT NULL DEFAULT 'all_visible_services';
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS is_active integer NOT NULL DEFAULT 1;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE custom_roles ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';
UPDATE custom_roles SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
ALTER TABLE custom_roles ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE custom_roles ALTER COLUMN server_revision SET NOT NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS custom_role_id text;

CREATE INDEX IF NOT EXISTS idx_custom_roles_server_revision ON custom_roles(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_custom_roles_business_revision ON custom_roles(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_custom_roles_business_active ON custom_roles(business_id, is_active, deleted_at);
CREATE INDEX IF NOT EXISTS idx_users_custom_role ON users(business_id, custom_role_id);
