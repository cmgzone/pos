ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS approval_required integer NOT NULL DEFAULT 0;
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS submitted_by text;
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS submitted_at timestamptz;
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS approved_by text;
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE purchase_orders ADD COLUMN IF NOT EXISTS approval_note text;
