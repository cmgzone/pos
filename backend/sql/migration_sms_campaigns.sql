CREATE TABLE IF NOT EXISTS sms_campaigns (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  name text NOT NULL,
  segment text NOT NULL DEFAULT 'all',
  message text NOT NULL,
  recipient_count integer NOT NULL DEFAULT 0,
  sent_count integer NOT NULL DEFAULT 0,
  failed_count integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft',
  recipient_snapshot_json text,
  last_error text,
  created_by text,
  sent_at timestamptz,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS name text NOT NULL DEFAULT 'Campaign';
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS segment text NOT NULL DEFAULT 'all';
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS message text NOT NULL DEFAULT '';
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS recipient_count integer NOT NULL DEFAULT 0;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS sent_count integer NOT NULL DEFAULT 0;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS failed_count integer NOT NULL DEFAULT 0;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft';
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS recipient_snapshot_json text;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS last_error text;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS created_by text;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS sent_at timestamptz;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE sms_campaigns ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';

CREATE INDEX IF NOT EXISTS idx_sms_campaigns_business_revision ON sms_campaigns(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sms_campaigns_branch_status ON sms_campaigns(business_id, branch_id, status);
