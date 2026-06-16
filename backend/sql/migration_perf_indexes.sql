-- ══════════════════════════════════════════════════════════════════════════════
-- Performance Indexes Migration
-- Adds composite indexes on products and product_variants for branch + deleted_at
-- lookups used by the Flutter client's getAll and barcode-scan queries.
-- ══════════════════════════════════════════════════════════════════════════════

-- Covers: SELECT ... FROM products WHERE branch_id = ? AND deleted_at IS NULL
CREATE INDEX IF NOT EXISTS idx_products_branch_deleted
  ON products(business_id, branch_id, deleted_at);

-- Covers: SELECT ... FROM product_variants WHERE branch_id = ? AND deleted_at IS NULL
CREATE INDEX IF NOT EXISTS idx_product_variants_branch_deleted
  ON product_variants(business_id, branch_id, deleted_at);

-- ══════════════════════════════════════════════════════════════════════════════
-- End of Performance Indexes Migration
-- ══════════════════════════════════════════════════════════════════════════════
