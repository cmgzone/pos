-- AI Configuration table (platform-wide, single row)
CREATE TABLE IF NOT EXISTS platform_ai_config (
  id         INTEGER PRIMARY KEY DEFAULT 1,
  api_key    TEXT NOT NULL DEFAULT '',
  serp_api_key TEXT NOT NULL DEFAULT '',
  model      TEXT NOT NULL DEFAULT 'openai/gpt-4o-mini',
  enabled    BOOLEAN NOT NULL DEFAULT false,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT single_row CHECK (id = 1)
);

INSERT INTO platform_ai_config (id) VALUES (1) ON CONFLICT DO NOTHING;

-- Rate limiting table for AI proxy
CREATE TABLE IF NOT EXISTS ai_rate_limits (
  business_id TEXT PRIMARY KEY,
  request_count INTEGER NOT NULL DEFAULT 0,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
