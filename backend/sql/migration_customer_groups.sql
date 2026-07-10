CREATE TABLE IF NOT EXISTS customer_groups (
  id text PRIMARY KEY, business_id text, branch_id text, name text NOT NULL, description text,
  color text, created_by text, server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz, sync_status text NOT NULL DEFAULT 'synced'
);
CREATE TABLE IF NOT EXISTS customer_group_members (
  id text PRIMARY KEY, business_id text, branch_id text, group_id text NOT NULL, customer_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz, sync_status text NOT NULL DEFAULT 'synced', UNIQUE(group_id, customer_id)
);
CREATE INDEX IF NOT EXISTS idx_customer_groups_branch ON customer_groups(business_id, branch_id, name);
CREATE INDEX IF NOT EXISTS idx_customer_group_members_group ON customer_group_members(business_id, group_id, customer_id);
