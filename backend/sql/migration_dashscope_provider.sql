-- Add multi-provider support to platform_ai_config
-- Each model type can use a different provider (openrouter or dashscope)

ALTER TABLE platform_ai_config
  ADD COLUMN IF NOT EXISTS dashscope_api_key text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS chat_provider text NOT NULL DEFAULT 'openrouter',
  ADD COLUMN IF NOT EXISTS image_provider text NOT NULL DEFAULT 'openrouter',
  ADD COLUMN IF NOT EXISTS stt_provider text NOT NULL DEFAULT 'openrouter',
  ADD COLUMN IF NOT EXISTS tts_provider text NOT NULL DEFAULT 'openrouter';
