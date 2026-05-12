ALTER TABLE platform_ai_config
  ADD COLUMN IF NOT EXISTS stt_model text NOT NULL DEFAULT 'openai/whisper-1';

ALTER TABLE platform_ai_config
  ADD COLUMN IF NOT EXISTS tts_model text NOT NULL DEFAULT 'openai/tts-1';

ALTER TABLE platform_ai_config
  ADD COLUMN IF NOT EXISTS tts_voice text NOT NULL DEFAULT 'alloy';
