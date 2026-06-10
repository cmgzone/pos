CREATE TABLE IF NOT EXISTS received_mpesa_payments (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  transaction_code text UNIQUE NOT NULL,
  phone_number text NOT NULL,
  amount numeric NOT NULL,
  bill_ref_number text,
  merchant_shortcode text,
  first_name text,
  middle_name text,
  last_name text,
  status text NOT NULL DEFAULT 'unclaimed',
  claimed_by_sale_id text,
  raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

ALTER TABLE received_mpesa_payments
  ADD COLUMN IF NOT EXISTS merchant_shortcode text,
  ADD COLUMN IF NOT EXISTS raw_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_received_mpesa_unclaimed
  ON received_mpesa_payments(business_id, status, phone_number, amount);

CREATE INDEX IF NOT EXISTS idx_received_mpesa_bill_ref
  ON received_mpesa_payments(business_id, status, lower(bill_ref_number));
