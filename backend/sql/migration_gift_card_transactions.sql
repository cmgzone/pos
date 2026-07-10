CREATE TABLE IF NOT EXISTS gift_card_transactions (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id text NOT NULL DEFAULT 'main_branch',
  gift_card_id text NOT NULL,
  sale_id text,
  type text NOT NULL,
  amount double precision NOT NULL DEFAULT 0,
  balance_after double precision NOT NULL DEFAULT 0,
  note text,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced',
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq')
);

CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_card
  ON gift_card_transactions(business_id, gift_card_id, created_at);

CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_updated_at
  ON gift_card_transactions(updated_at);

CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_business_revision
  ON gift_card_transactions(business_id, server_revision, id);
