-- Customer portal email-verification authentication.
CREATE TABLE IF NOT EXISTS customer_portal_email_otps (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  customer_id text NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  email text NOT NULL,
  code_hash text NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  expires_at timestamptz NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT NOW(),
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customer_portal_email_otps_lookup
  ON customer_portal_email_otps (business_id, customer_id, email, created_at DESC);
