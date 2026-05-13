ALTER TABLE platform_ai_config
  ADD COLUMN IF NOT EXISTS serp_api_key text NOT NULL DEFAULT '';
