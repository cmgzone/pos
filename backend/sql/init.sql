CREATE SEQUENCE IF NOT EXISTS sync_revision_seq AS bigint;

CREATE TABLE IF NOT EXISTS businesses (
  id text PRIMARY KEY,
  name text NOT NULL,
  owner_name text,
  owner_email text,
  country_code text NOT NULL DEFAULT 'GLOBAL',
  currency text,
  selling_mode text NOT NULL DEFAULT 'combo',
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

ALTER TABLE businesses ADD COLUMN IF NOT EXISTS country_code text NOT NULL DEFAULT 'GLOBAL';
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS currency text;
ALTER TABLE businesses ADD COLUMN IF NOT EXISTS selling_mode text NOT NULL DEFAULT 'combo';

CREATE TABLE IF NOT EXISTS subscriptions (
  business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
  plan text NOT NULL DEFAULT 'trial',
  status text NOT NULL DEFAULT 'active',
  expires_at timestamptz NOT NULL,
  grace_until timestamptz NOT NULL,
  last_verified_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS subscription_plans (
  code text PRIMARY KEY,
  name text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  features_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  allowed_selling_modes_json jsonb NOT NULL DEFAULT '["products","services","combo"]'::jsonb,
  max_branches integer NOT NULL DEFAULT 1,
  max_employees integer NOT NULL DEFAULT 1,
  max_ai_agents integer NOT NULL DEFAULT 0,
  ai_rate_hourly integer NOT NULL DEFAULT 0,
  ai_rate_weekly integer NOT NULL DEFAULT 0,
  ai_rate_monthly integer NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

ALTER TABLE subscription_plans
  ADD COLUMN IF NOT EXISTS allowed_selling_modes_json jsonb NOT NULL DEFAULT '["products","services","combo"]'::jsonb;

CREATE TABLE IF NOT EXISTS platform_subscription_settings (
  id integer PRIMARY KEY DEFAULT 1,
  trial_days integer NOT NULL DEFAULT 30,
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT platform_subscription_settings_single_row CHECK (id = 1),
  CONSTRAINT platform_subscription_settings_trial_days CHECK (trial_days BETWEEN 1 AND 365)
);

INSERT INTO platform_subscription_settings (id, trial_days)
VALUES (1, 30)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS platform_payment_gateways (
  provider text PRIMARY KEY,
  display_name text NOT NULL,
  is_active boolean NOT NULL DEFAULT false,
  countries_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  public_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  secret_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS subscription_plan_prices (
  id text PRIMARY KEY,
  plan_code text NOT NULL REFERENCES subscription_plans(code) ON DELETE CASCADE,
  country_code text NOT NULL DEFAULT 'GLOBAL',
  currency text NOT NULL DEFAULT 'USD',
  amount_minor integer NOT NULL DEFAULT 0,
  billing_period text NOT NULL DEFAULT 'monthly',
  provider text NOT NULL DEFAULT 'google_pay',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_plan_prices_unique
  ON subscription_plan_prices(plan_code, country_code, provider, billing_period);

CREATE TABLE IF NOT EXISTS subscription_payments (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  plan_code text NOT NULL REFERENCES subscription_plans(code),
  price_id text REFERENCES subscription_plan_prices(id),
  provider text NOT NULL,
  country_code text NOT NULL,
  currency text NOT NULL,
  amount_minor integer NOT NULL,
  billing_period text NOT NULL DEFAULT 'monthly',
  selling_mode text NOT NULL DEFAULT 'products',
  status text NOT NULL DEFAULT 'pending',
  phone_number text,
  external_reference text,
  checkout_request_id text,
  google_pay_token_json jsonb,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  completed_at timestamptz
);

ALTER TABLE subscription_payments
  ADD COLUMN IF NOT EXISTS selling_mode text NOT NULL DEFAULT 'products';

CREATE INDEX IF NOT EXISTS idx_subscription_payments_business
  ON subscription_payments(business_id, created_at DESC);

CREATE TABLE IF NOT EXISTS pos_payment_requests (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  sale_id text,
  provider text NOT NULL,
  country_code text NOT NULL DEFAULT 'KE',
  currency text NOT NULL DEFAULT 'KES',
  amount_minor integer NOT NULL,
  phone_number text,
  status text NOT NULL DEFAULT 'pending',
  external_reference text,
  checkout_request_id text,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  completed_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_pos_payment_requests_business
  ON pos_payment_requests(business_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pos_payment_requests_checkout
  ON pos_payment_requests(checkout_request_id);

CREATE TABLE IF NOT EXISTS business_payment_gateways (
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  provider text NOT NULL,
  display_name text,
  is_active boolean NOT NULL DEFAULT false,
  public_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  secret_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (business_id, provider)
);

CREATE TABLE IF NOT EXISTS platform_message_gateways (
  provider text PRIMARY KEY,
  display_name text NOT NULL,
  is_active boolean NOT NULL DEFAULT false,
  countries_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  public_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  secret_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS business_communication_settings (
  business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
  whatsapp_number text,
  sms_sender_id text,
  allow_api_send boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS message_send_logs (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  user_id text,
  channel text NOT NULL,
  mode text NOT NULL DEFAULT 'api',
  provider text,
  recipient text NOT NULL,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  error_message text,
  metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_message_send_logs_business
  ON message_send_logs(business_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public_catalog_orders (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  customer_name text NOT NULL,
  phone text NOT NULL,
  delivery_address text,
  note text,
  status text NOT NULL DEFAULT 'pending',
  subtotal double precision NOT NULL DEFAULT 0,
  item_count double precision NOT NULL DEFAULT 0,
  source text NOT NULL DEFAULT 'catalog_link',
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public_catalog_order_items (
  id text PRIMARY KEY,
  order_id text NOT NULL REFERENCES public_catalog_orders(id) ON DELETE CASCADE,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  product_id text NOT NULL,
  variant_id text,
  product_name text NOT NULL,
  variant_name text,
  quantity double precision NOT NULL DEFAULT 1,
  unit_price double precision NOT NULL DEFAULT 0,
  line_total double precision NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_public_catalog_orders_business_status
  ON public_catalog_orders(business_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_public_catalog_order_items_order
  ON public_catalog_order_items(order_id);

CREATE TABLE IF NOT EXISTS business_access_tokens (
  business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
  access_token text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  name text,
  last_seen_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS platform_ai_config (
  id integer PRIMARY KEY DEFAULT 1,
  api_key text NOT NULL DEFAULT '',
  serp_api_key text NOT NULL DEFAULT '',
  model text NOT NULL DEFAULT 'openai/gpt-4o-mini',
  image_model text NOT NULL DEFAULT 'google/gemini-2.5-flash-image',
  stt_model text NOT NULL DEFAULT 'openai/whisper-1',
  tts_model text NOT NULL DEFAULT 'openai/tts-1',
  tts_voice text NOT NULL DEFAULT 'alloy',
  enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT platform_ai_config_single_row CHECK (id = 1)
);

INSERT INTO platform_ai_config (id) VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS ai_rate_limits (
  business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
  request_count integer NOT NULL DEFAULT 0,
  window_start timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS ai_rate_limit_counters (
  business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  period text NOT NULL,
  request_count integer NOT NULL DEFAULT 0,
  window_start timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (business_id, period)
);

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

CREATE TABLE IF NOT EXISTS categories (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  color text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS expense_categories (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  color text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS users (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  email text NOT NULL,
  phone text,
  password text NOT NULL,
  role text NOT NULL DEFAULT 'CASHIER',
  feature_access_json text,
  allowed_service_ids_json text,
  pos_mode text NOT NULL DEFAULT 'both',
  service_order_scope text NOT NULL DEFAULT 'all_visible_services',
  last_seen_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);


CREATE TABLE IF NOT EXISTS customers (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  phone text,
  email text,
  balance double precision NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS suppliers (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  phone text,
  email text,
  address text,
  note text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS products (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  price double precision NOT NULL DEFAULT 0,
  cost double precision,
  stock double precision NOT NULL DEFAULT 0,
  low_stock double precision NOT NULL DEFAULT 0,
  unit text NOT NULL DEFAULT 'pcs',
  stock_unit text NOT NULL DEFAULT 'pcs',
  sale_unit text NOT NULL DEFAULT 'pcs',
  sale_to_stock_factor double precision NOT NULL DEFAULT 1,
  purchase_unit text NOT NULL DEFAULT 'pcs',
  purchase_to_stock_factor double precision NOT NULL DEFAULT 1,
  sku text,
  barcode text,
  image_url text,
  category_id text,
  track_stock integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS purchase_invoices (
  id text PRIMARY KEY,
  business_id text,
  supplier_id text,
  supplier_name text,
  invoice_number text,
  total_amount double precision NOT NULL DEFAULT 0,
  note text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS stock_batches (
  id text PRIMARY KEY,
  business_id text,
  product_id text NOT NULL,
  quantity_received double precision NOT NULL DEFAULT 0,
  quantity_remaining double precision NOT NULL DEFAULT 0,
  unit_cost double precision NOT NULL DEFAULT 0,
  purchase_id text,
  supplier_id text,
  expiry_date date,
  received_at timestamptz NOT NULL,
  finished_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS shifts (
  id text PRIMARY KEY,
  business_id text,
  user_id text,
  cashier_name text,
  status text NOT NULL DEFAULT 'open',
  opening_cash double precision NOT NULL DEFAULT 0,
  closing_cash_counted double precision NOT NULL DEFAULT 0,
  expected_cash double precision NOT NULL DEFAULT 0,
  cash_sales_total double precision NOT NULL DEFAULT 0,
  cash_refunds_total double precision NOT NULL DEFAULT 0,
  cash_in_total double precision NOT NULL DEFAULT 0,
  cash_out_total double precision NOT NULL DEFAULT 0,
  difference double precision NOT NULL DEFAULT 0,
  note text,
  opened_at timestamptz NOT NULL,
  closed_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS sales (
  id text PRIMARY KEY,
  business_id text,
  total_amount double precision NOT NULL DEFAULT 0,
  tax double precision NOT NULL DEFAULT 0,
  discount double precision NOT NULL DEFAULT 0,
  payment_type text NOT NULL,
  user_id text,
  shift_id text,
  customer_id text,
  customer_name text,
  due_date text,
  amount_paid double precision NOT NULL DEFAULT 0,
  amount_tendered double precision NOT NULL DEFAULT 0,
  change_given double precision NOT NULL DEFAULT 0,
  balance_due double precision NOT NULL DEFAULT 0,
  payment_provider text,
  payment_reference text,
  payment_status text,
  payment_metadata_json jsonb,
  refund_sale_id text,
  refund_for_sale_id text,
  refund_note text,
  refunded_at timestamptz,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS sale_items (
  id text PRIMARY KEY,
  business_id text,
  quantity double precision NOT NULL,
  unit_price double precision NOT NULL DEFAULT 0,
  unit_cost double precision NOT NULL DEFAULT 0,
  unit text NOT NULL DEFAULT 'pcs',
  sale_id text NOT NULL,
  product_id text NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS cash_movements (
  id text PRIMARY KEY,
  business_id text,
  shift_id text NOT NULL,
  user_id text,
  type text NOT NULL,
  amount double precision NOT NULL DEFAULT 0,
  reason text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS credit_payments (
  id text PRIMARY KEY,
  business_id text,
  payment_group_id text NOT NULL,
  customer_id text NOT NULL,
  sale_id text,
  user_id text,
  amount double precision NOT NULL DEFAULT 0,
  note text,
  received_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS expenses (
  id text PRIMARY KEY,
  business_id text,
  category_id text,
  category_name text,
  title text NOT NULL,
  amount double precision NOT NULL DEFAULT 0,
  note text,
  incurred_on text NOT NULL,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE INDEX IF NOT EXISTS idx_categories_updated_at ON categories(updated_at);
CREATE INDEX IF NOT EXISTS idx_expense_categories_updated_at ON expense_categories(updated_at);
CREATE INDEX IF NOT EXISTS idx_users_updated_at ON users(updated_at);
CREATE INDEX IF NOT EXISTS idx_customers_updated_at ON customers(updated_at);
CREATE INDEX IF NOT EXISTS idx_suppliers_updated_at ON suppliers(updated_at);
CREATE INDEX IF NOT EXISTS idx_products_updated_at ON products(updated_at);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_updated_at ON purchase_invoices(updated_at);
CREATE INDEX IF NOT EXISTS idx_stock_batches_updated_at ON stock_batches(updated_at);
CREATE INDEX IF NOT EXISTS idx_shifts_updated_at ON shifts(updated_at);
CREATE INDEX IF NOT EXISTS idx_sales_updated_at ON sales(updated_at);
CREATE INDEX IF NOT EXISTS idx_sale_items_updated_at ON sale_items(updated_at);
CREATE INDEX IF NOT EXISTS idx_cash_movements_updated_at ON cash_movements(updated_at);
CREATE INDEX IF NOT EXISTS idx_credit_payments_updated_at ON credit_payments(updated_at);
CREATE INDEX IF NOT EXISTS idx_expenses_updated_at ON expenses(updated_at);
CREATE INDEX IF NOT EXISTS idx_devices_business_id ON devices(business_id);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen_at ON devices(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status, expires_at, grace_until);
CREATE INDEX IF NOT EXISTS idx_shifts_user_id ON shifts(user_id);
CREATE INDEX IF NOT EXISTS idx_shifts_business_opened_at ON shifts(business_id, opened_at);
CREATE INDEX IF NOT EXISTS idx_cash_movements_shift_id ON cash_movements(shift_id);
CREATE INDEX IF NOT EXISTS idx_cash_movements_business_created_at ON cash_movements(business_id, created_at);

ALTER TABLE categories ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE expense_categories ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE users ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE customers ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE suppliers ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE products ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE purchase_invoices ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE stock_batches ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE shifts ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE sales ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE sale_items ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE cash_movements ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE credit_payments ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE expenses ALTER COLUMN sync_status SET DEFAULT 'synced';

UPDATE categories SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE expense_categories SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE users SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE customers SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE suppliers SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE products SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE purchase_invoices SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE stock_batches SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE shifts SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE sales SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE sale_items SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE cash_movements SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE credit_payments SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE expenses SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';

ALTER TABLE categories ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE expense_categories ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE users ADD COLUMN IF NOT EXISTS server_revision bigint;

ALTER TABLE categories ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE expense_categories ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE products ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE products ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE stock_batches ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE stock_batches ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE stock_batches ADD COLUMN IF NOT EXISTS expiry_date date;
CREATE INDEX IF NOT EXISTS idx_stock_batches_expiry_date ON stock_batches(expiry_date);
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS shift_id text;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS payment_provider text;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS payment_reference text;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS payment_status text;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS payment_metadata_json jsonb;
CREATE INDEX IF NOT EXISTS idx_sales_shift_id ON sales(shift_id);
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE cash_movements ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE cash_movements ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE credit_payments ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE credit_payments ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS business_id text;

UPDATE categories SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE expense_categories SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE users SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE customers SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE suppliers SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE products SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE purchase_invoices SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE stock_batches SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE shifts SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE sales SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE sale_items SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE cash_movements SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE credit_payments SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE expenses SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;

ALTER TABLE categories ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE expense_categories ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE users ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE customers ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE suppliers ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE products ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE purchase_invoices ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE stock_batches ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE shifts ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE sales ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE sale_items ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE cash_movements ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE credit_payments ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE expenses ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');

ALTER TABLE categories ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE expense_categories ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE users ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE customers ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE suppliers ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE products ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE purchase_invoices ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE stock_batches ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE shifts ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE sales ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE sale_items ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE cash_movements ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE credit_payments ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE expenses ALTER COLUMN server_revision SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_categories_server_revision ON categories(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_expense_categories_server_revision ON expense_categories(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_users_server_revision ON users(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_customers_server_revision ON customers(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_suppliers_server_revision ON suppliers(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_products_server_revision ON products(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_server_revision ON purchase_invoices(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_server_revision ON stock_batches(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_shifts_server_revision ON shifts(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sales_server_revision ON sales(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sale_items_server_revision ON sale_items(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_cash_movements_server_revision ON cash_movements(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_credit_payments_server_revision ON credit_payments(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_expenses_server_revision ON expenses(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_categories_business_revision ON categories(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_expense_categories_business_revision ON expense_categories(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_users_business_revision ON users(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_customers_business_revision ON customers(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_suppliers_business_revision ON suppliers(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_products_business_revision ON products(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_business_revision ON purchase_invoices(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_business_revision ON stock_batches(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_shifts_business_revision ON shifts(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sales_business_revision ON sales(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sale_items_business_revision ON sale_items(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_cash_movements_business_revision ON cash_movements(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_credit_payments_business_revision ON credit_payments(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_expenses_business_revision ON expenses(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sales_business_created_at ON sales(business_id, created_at);
CREATE INDEX IF NOT EXISTS idx_users_business_email ON users(business_id, email);


-- Ensure last_seen_at exists on users (added after initial schema)
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

DROP INDEX IF EXISTS idx_users_email_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_business_email_unique
  ON users(business_id, email);

-- ── Service tables ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS services (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  category text,
  description text,
  base_price double precision NOT NULL DEFAULT 0,
  duration_minutes integer,
  is_active integer NOT NULL DEFAULT 1,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS service_fields (
  id text PRIMARY KEY,
  business_id text,
  service_id text NOT NULL,
  label text NOT NULL,
  field_type text NOT NULL,
  options_json text,
  is_required integer NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS service_orders (
  id text PRIMARY KEY,
  business_id text,
  service_id text NOT NULL,
  service_name text NOT NULL,
  customer_id text,
  customer_name text,
  entry_mode text NOT NULL DEFAULT 'walk_in',
  scheduled_at timestamptz,
  checked_in_at timestamptz,
  status text NOT NULL DEFAULT 'booked',
  assigned_staff text,
  assigned_staff_user_id text,
  bay_number text,
  price double precision NOT NULL DEFAULT 0,
  note text,
  sale_id text,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS service_field_values (
  id text PRIMARY KEY,
  business_id text,
  service_order_id text NOT NULL,
  field_id text,
  field_label text NOT NULL,
  field_type text NOT NULL,
  value_text text,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS service_sale_items (
  id text PRIMARY KEY,
  business_id text,
  sale_id text NOT NULL,
  service_order_id text,
  service_id text,
  service_name text NOT NULL,
  quantity double precision NOT NULL DEFAULT 1,
  unit_price double precision NOT NULL DEFAULT 0,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

-- Indexes for cursor-based sync (business_id + server_revision + id)
CREATE INDEX IF NOT EXISTS idx_services_business_revision ON services(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_service_fields_business_revision ON service_fields(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_service_orders_business_revision ON service_orders(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_service_field_values_business_revision ON service_field_values(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_service_sale_items_business_revision ON service_sale_items(business_id, server_revision, id);

-- Lookup indexes
CREATE INDEX IF NOT EXISTS idx_service_fields_service_id ON service_fields(service_id);
CREATE INDEX IF NOT EXISTS idx_service_orders_status ON service_orders(status);
CREATE INDEX IF NOT EXISTS idx_service_orders_scheduled_at ON service_orders(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_service_field_values_order_id ON service_field_values(service_order_id);
CREATE INDEX IF NOT EXISTS idx_service_sale_items_sale_id ON service_sale_items(sale_id);

-- Ensure bay_number exists (added in schema v11)
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS bay_number text;

-- Ensure price_map_json exists on service_fields (added for per-option auto-pricing)
ALTER TABLE service_fields ADD COLUMN IF NOT EXISTS price_map_json text;

ALTER TABLE users ADD COLUMN IF NOT EXISTS feature_access_json text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS allowed_service_ids_json text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS pos_mode text NOT NULL DEFAULT 'both';
ALTER TABLE users ADD COLUMN IF NOT EXISTS service_order_scope text NOT NULL DEFAULT 'all_visible_services';
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS assigned_staff_user_id text;

-- ── Product Variants ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS product_variants (
  id text PRIMARY KEY,
  business_id text,
  product_id text NOT NULL,
  name text NOT NULL,
  price double precision NOT NULL DEFAULT 0,
  cost double precision,
  sku text,
  barcode text,
  stock double precision NOT NULL DEFAULT 0,
  low_stock double precision NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE INDEX IF NOT EXISTS idx_product_variants_business_revision
  ON product_variants(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id
  ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_barcode
  ON product_variants(barcode);

-- Ensure has_variants column exists on products
ALTER TABLE products ADD COLUMN IF NOT EXISTS has_variants integer NOT NULL DEFAULT 0;

-- Ensure brand column exists on products
ALTER TABLE products ADD COLUMN IF NOT EXISTS brand text;

-- Ensure track_stock column exists on products
ALTER TABLE products ADD COLUMN IF NOT EXISTS track_stock integer NOT NULL DEFAULT 1;

-- Ensure variant_id column exists on sale_items
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS variant_id text;
CREATE INDEX IF NOT EXISTS idx_sale_items_variant_id ON sale_items(variant_id);

-- ── Payment Methods ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS payment_methods (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  is_cash_drawer integer NOT NULL DEFAULT 0,
  is_credit integer NOT NULL DEFAULT 0,
  is_active integer NOT NULL DEFAULT 1,
  sort_order integer NOT NULL DEFAULT 0,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_business_revision 
  ON payment_methods(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_payment_methods_business_active 
  ON payment_methods(business_id, is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_payment_methods_sort_order 
  ON payment_methods(business_id, sort_order, name) WHERE deleted_at IS NULL;

-- Add is_cash_drawer column to sales table
ALTER TABLE sales ADD COLUMN IF NOT EXISTS is_cash_drawer integer NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_sales_is_cash_drawer 
  ON sales(business_id, is_cash_drawer) WHERE deleted_at IS NULL;

-- Enterprise branch/audit schema
CREATE TABLE IF NOT EXISTS branches (
  id text PRIMARY KEY,
  business_id text,
  name text NOT NULL,
  code text,
  phone text,
  address text,
  is_active integer NOT NULL DEFAULT 1,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  user_id text,
  user_name text,
  user_role text,
  action text NOT NULL,
  entity_table text NOT NULL,
  entity_id text,
  before_json text,
  after_json text,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

CREATE TABLE IF NOT EXISTS stock_transfers (
  id text PRIMARY KEY,
  business_id text,
  branch_id text,
  from_branch_id text NOT NULL,
  to_branch_id text NOT NULL,
  product_id text NOT NULL,
  product_name text NOT NULL,
  quantity double precision NOT NULL DEFAULT 0,
  unit text,
  status text NOT NULL DEFAULT 'requested',
  requested_by text,
  approved_by text,
  received_by text,
  note text,
  requested_at timestamptz NOT NULL,
  approved_at timestamptz,
  received_at timestamptz,
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq'),
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'synced'
);

ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS from_branch_id text NOT NULL DEFAULT '';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS to_branch_id text NOT NULL DEFAULT '';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS product_id text NOT NULL DEFAULT '';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS product_name text NOT NULL DEFAULT 'Product';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS quantity double precision NOT NULL DEFAULT 0;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS unit text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'requested';
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS requested_by text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS approved_by text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS received_by text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS requested_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS received_at timestamptz;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE stock_transfers ADD COLUMN IF NOT EXISTS sync_status text NOT NULL DEFAULT 'synced';

ALTER TABLE users ADD COLUMN IF NOT EXISTS allowed_branch_ids_json text;

ALTER TABLE categories ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE expense_categories ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE customers ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE shifts ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE suppliers ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE products ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE product_variants ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE purchase_invoices ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE stock_batches ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE stock_batches ADD COLUMN IF NOT EXISTS batch_number text;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE cash_movements ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE credit_payments ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE services ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS branch_id text DEFAULT 'main_branch';

CREATE INDEX IF NOT EXISTS idx_branches_business_revision ON branches(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_business_revision ON audit_logs(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_business_revision ON stock_transfers(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_branch_status ON stock_transfers(business_id, from_branch_id, to_branch_id, status);

CREATE INDEX IF NOT EXISTS idx_categories_branch_id ON categories(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_expense_categories_branch_id ON expense_categories(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_customers_branch_id ON customers(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_shifts_branch_id ON shifts(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_suppliers_branch_id ON suppliers(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_products_branch_id ON products(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_branch_id ON product_variants(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_purchase_invoices_branch_id ON purchase_invoices(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_stock_batches_branch_id ON stock_batches(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_sales_branch_id ON sales(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_cash_movements_branch_id ON cash_movements(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_credit_payments_branch_id ON credit_payments(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_expenses_branch_id ON expenses(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_services_branch_id ON services(business_id, branch_id);
CREATE INDEX IF NOT EXISTS idx_service_orders_branch_id ON service_orders(business_id, branch_id);

CREATE INDEX IF NOT EXISTS idx_products_barcode_partial ON products(business_id, barcode) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_product_variants_barcode_partial ON product_variants(business_id, barcode) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_product_variants_product_deleted ON product_variants(business_id, product_id, deleted_at);
CREATE INDEX IF NOT EXISTS idx_stock_batches_fifo_partial ON stock_batches(business_id, product_id, quantity_remaining, expiry_date, received_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_sale_items_lookup ON sale_items(sale_id, product_id);
CREATE INDEX IF NOT EXISTS idx_sales_sync_branch ON sales(business_id, branch_id, deleted_at, created_at);
