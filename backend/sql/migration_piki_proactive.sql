CREATE TABLE IF NOT EXISTS piki_learning (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id text,
  kind text NOT NULL,
  phrase text NOT NULL,
  target text NOT NULL,
  weight double precision NOT NULL DEFAULT 1,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_piki_learning_business_phrase
  ON piki_learning(business_id, kind, COALESCE(branch_id, ''), LOWER(phrase))
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS piki_proactive_insights (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id text,
  severity text NOT NULL DEFAULT 'info',
  kind text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  action_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  dedupe_key text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  generated_at timestamptz NOT NULL DEFAULT NOW(),
  acknowledged_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_piki_proactive_dedupe
  ON piki_proactive_insights(business_id, dedupe_key);

CREATE INDEX IF NOT EXISTS idx_piki_proactive_active
  ON piki_proactive_insights(business_id, status, generated_at DESC);
