CREATE TABLE IF NOT EXISTS customer_invoices (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  branch_id text,
  invoice_number text NOT NULL,
  customer_id text,
  customer_name text NOT NULL,
  customer_phone text,
  customer_email text,
  customer_kra_pin text,
  status text NOT NULL DEFAULT 'draft',
  issue_date text NOT NULL,
  due_date text,
  subtotal numeric NOT NULL DEFAULT 0,
  tax numeric NOT NULL DEFAULT 0,
  discount numeric NOT NULL DEFAULT 0,
  total_amount numeric NOT NULL DEFAULT 0,
  amount_paid numeric NOT NULL DEFAULT 0,
  balance_due numeric NOT NULL DEFAULT 0,
  payment_method text,
  payment_reference text,
  note text,
  sale_id text,
  sent_at text,
  paid_at text,
  created_by text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'pending',
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq')
);

CREATE TABLE IF NOT EXISTS customer_invoice_items (
  id text PRIMARY KEY,
  business_id text NOT NULL,
  branch_id text,
  invoice_id text NOT NULL,
  line_type text NOT NULL DEFAULT 'product',
  product_id text,
  variant_id text,
  service_id text,
  description text NOT NULL,
  quantity numeric NOT NULL DEFAULT 1,
  unit text NOT NULL DEFAULT 'pcs',
  unit_price numeric NOT NULL DEFAULT 0,
  unit_cost numeric NOT NULL DEFAULT 0,
  sale_to_stock_factor numeric NOT NULL DEFAULT 1,
  stock_unit text NOT NULL DEFAULT 'pcs',
  track_stock integer NOT NULL DEFAULT 1,
  line_total numeric NOT NULL DEFAULT 0,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  deleted_at timestamptz,
  sync_status text NOT NULL DEFAULT 'pending',
  server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq')
);

ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS customer_phone text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS customer_email text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS customer_kra_pin text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS payment_method text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS payment_reference text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS sale_id text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS sent_at text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS paid_at text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS created_by text;
ALTER TABLE customer_invoices ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');

ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS branch_id text;
ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS variant_id text;
ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS service_id text;
ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS sale_to_stock_factor numeric NOT NULL DEFAULT 1;
ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS stock_unit text NOT NULL DEFAULT 'pcs';
ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS track_stock integer NOT NULL DEFAULT 1;
ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;
ALTER TABLE customer_invoice_items ADD COLUMN IF NOT EXISTS server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq');

CREATE INDEX IF NOT EXISTS idx_customer_invoices_business_revision
  ON customer_invoices(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_customer_invoice_items_business_revision
  ON customer_invoice_items(business_id, server_revision, id);
CREATE INDEX IF NOT EXISTS idx_customer_invoices_status
  ON customer_invoices(business_id, branch_id, status, due_date);
CREATE INDEX IF NOT EXISTS idx_customer_invoice_items_invoice_id
  ON customer_invoice_items(business_id, invoice_id);
