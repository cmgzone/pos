ALTER TABLE public_catalog_orders ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'manual';
ALTER TABLE public_catalog_orders ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'pending';
ALTER TABLE public_catalog_orders ADD COLUMN IF NOT EXISTS delivery_status text;
ALTER TABLE public_catalog_orders ADD COLUMN IF NOT EXISTS tracking_code text;
ALTER TABLE public_catalog_orders ADD COLUMN IF NOT EXISTS payment_reference text;

CREATE TABLE IF NOT EXISTS delivery_zones (
  id text PRIMARY KEY, business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id text NOT NULL DEFAULT 'main_branch', name text NOT NULL,
  fee double precision NOT NULL DEFAULT 0, minimum_order double precision NOT NULL DEFAULT 0,
  is_active integer NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(), deleted_at timestamptz
);

CREATE TABLE IF NOT EXISTS deliveries (
  id text PRIMARY KEY, business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  branch_id text NOT NULL DEFAULT 'main_branch', order_id text NOT NULL REFERENCES public_catalog_orders(id) ON DELETE CASCADE,
  zone_id text, status text NOT NULL DEFAULT 'pending', tracking_code text NOT NULL,
  rider_name text, rider_phone text, scheduled_at timestamptz, delivered_at timestamptz,
  note text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_zones_business_active ON delivery_zones(business_id, branch_id, is_active);
CREATE INDEX IF NOT EXISTS idx_deliveries_business_status ON deliveries(business_id, branch_id, status, updated_at DESC);
