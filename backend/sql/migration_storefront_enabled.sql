-- Adds businesses.storefront_enabled for fast storefront gating and syncs
-- existing storefront rows so legacy storefronts keep working.
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS storefront_enabled boolean NOT NULL DEFAULT false;

UPDATE businesses b
SET storefront_enabled = true
WHERE storefront_enabled = false
  AND EXISTS (
    SELECT 1 FROM storefronts s
    WHERE s.business_id = b.id
      AND s.deleted_at IS NULL
      AND s.status = 'active'
  );
