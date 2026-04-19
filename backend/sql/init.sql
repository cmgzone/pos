CREATE SEQUENCE IF NOT EXISTS sync_revision_seq AS bigint;

CREATE TABLE IF NOT EXISTS businesses (
  id text PRIMARY KEY,
  name text NOT NULL,
  owner_name text,
  owner_email text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

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
  received_at timestamptz NOT NULL,
  finished_at timestamptz,
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
  customer_id text,
  customer_name text,
  due_date text,
  amount_paid double precision NOT NULL DEFAULT 0,
  amount_tendered double precision NOT NULL DEFAULT 0,
  change_given double precision NOT NULL DEFAULT 0,
  balance_due double precision NOT NULL DEFAULT 0,
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
CREATE INDEX IF NOT EXISTS idx_sales_updated_at ON sales(updated_at);
CREATE INDEX IF NOT EXISTS idx_sale_items_updated_at ON sale_items(updated_at);
CREATE INDEX IF NOT EXISTS idx_credit_payments_updated_at ON credit_payments(updated_at);
CREATE INDEX IF NOT EXISTS idx_expenses_updated_at ON expenses(updated_at);
CREATE INDEX IF NOT EXISTS idx_devices_business_id ON devices(business_id);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen_at ON devices(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status, expires_at, grace_until);

ALTER TABLE categories ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE expense_categories ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE users ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE customers ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE suppliers ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE products ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE purchase_invoices ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE stock_batches ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE sales ALTER COLUMN sync_status SET DEFAULT 'synced';
ALTER TABLE sale_items ALTER COLUMN sync_status SET DEFAULT 'synced';
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
UPDATE sales SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
UPDATE sale_items SET sync_status = 'synced' WHERE sync_status IS DISTINCT FROM 'synced';
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
ALTER TABLE sales ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE sales ADD COLUMN IF NOT EXISTS business_id text;
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS server_revision bigint;
ALTER TABLE sale_items ADD COLUMN IF NOT EXISTS business_id text;
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
UPDATE sales SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
UPDATE sale_items SET server_revision = nextval('sync_revision_seq') WHERE server_revision IS NULL;
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
ALTER TABLE sales ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
ALTER TABLE sale_items ALTER COLUMN server_revision SET DEFAULT nextval('sync_revision_seq');
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
ALTER TABLE sales ALTER COLUMN server_revision SET NOT NULL;
ALTER TABLE sale_items ALTER COLUMN server_revision SET NOT NULL;
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
CREATE INDEX IF NOT EXISTS idx_sales_server_revision ON sales(server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sale_items_server_revision ON sale_items(server_revision, id);
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
CREATE INDEX IF NOT EXISTS idx_sales_business_revision ON sales(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sale_items_business_revision ON sale_items(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_credit_payments_business_revision ON credit_payments(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_expenses_business_revision ON expenses(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_sales_business_created_at ON sales(business_id, created_at);
CREATE INDEX IF NOT EXISTS idx_users_business_email ON users(business_id, email);


-- Ensure last_seen_at exists on users (added after initial schema)
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

DROP INDEX IF EXISTS idx_users_email_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_business_email_unique
  ON users(business_id, email);