ALTER TABLE loyalty_rules
  ADD COLUMN IF NOT EXISTS gift_card_reward_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE loyalty_rules
  ADD COLUMN IF NOT EXISTS gift_card_reward_points_threshold integer NOT NULL DEFAULT 0;

ALTER TABLE loyalty_rules
  ADD COLUMN IF NOT EXISTS gift_card_reward_amount double precision NOT NULL DEFAULT 0;

ALTER TABLE loyalty_rules
  ADD COLUMN IF NOT EXISTS gift_card_reward_expiry_days integer NOT NULL DEFAULT 0;
