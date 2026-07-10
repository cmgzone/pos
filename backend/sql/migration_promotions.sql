CREATE TABLE IF NOT EXISTS promotions (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id text NOT NULL DEFAULT 'main_branch',
  name text NOT NULL,
  description text,
  promotion_type text NOT NULL,
  discount_type text NOT NULL DEFAULT 'amount',
  discount_value double precision NOT NULL DEFAULT 0,
  priority integer NOT NULL DEFAULT 0,
  starts_at timestamptz,
  ends_at timestamptz,
  days_of_week text,
  start_time text,
  end_time text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced',
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq')
);

CREATE TABLE IF NOT EXISTS promotion_rules (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id text NOT NULL DEFAULT 'main_branch',
  promotion_id text NOT NULL,
  rule_type text NOT NULL,
  product_id text,
  category_id text,
  min_quantity double precision NOT NULL DEFAULT 0,
  free_quantity double precision NOT NULL DEFAULT 0,
  bundle_quantity double precision NOT NULL DEFAULT 0,
  min_subtotal double precision NOT NULL DEFAULT 0,
  rule_json text,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced',
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq')
);

CREATE INDEX IF NOT EXISTS idx_promotions_updated_at
  ON promotions(updated_at);

CREATE INDEX IF NOT EXISTS idx_promotions_business_revision
  ON promotions(business_id, server_revision, id);

CREATE INDEX IF NOT EXISTS idx_promotions_active
  ON promotions(business_id, branch_id, is_active, starts_at, ends_at);

CREATE INDEX IF NOT EXISTS idx_promotion_rules_updated_at
  ON promotion_rules(updated_at);

CREATE INDEX IF NOT EXISTS idx_promotion_rules_business_revision
  ON promotion_rules(business_id, server_revision, id);

CREATE INDEX IF NOT EXISTS idx_promotion_rules_promotion
  ON promotion_rules(business_id, promotion_id);
