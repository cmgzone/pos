CREATE TABLE IF NOT EXISTS exchange_rates (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  base_currency text NOT NULL,
  quote_currency text NOT NULL,
  rate double precision NOT NULL DEFAULT 1,
  is_active integer NOT NULL DEFAULT 1,
  updated_by text,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS base_currency text NOT NULL DEFAULT 'KSh';
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS quote_currency text NOT NULL DEFAULT '$';
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS rate double precision NOT NULL DEFAULT 1;
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS is_active integer NOT NULL DEFAULT 1;
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS updated_by text;
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE exchange_rates ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';

CREATE INDEX IF NOT EXISTS idx_exchange_rates_business_revision ON exchange_rates(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_exchange_rates_active ON exchange_rates(business_id, branch_id, is_active, quote_currency);
