const crypto = require('crypto');

let schemaReady = false;

async function ensureBackendImageAssetSchema(target) {
  if (schemaReady) return;
  await target(
    `CREATE TABLE IF NOT EXISTS backend_image_assets (
       id uuid PRIMARY KEY,
       business_id text NOT NULL,
       asset_kind text NOT NULL,
       content_type text NOT NULL,
       byte_size integer NOT NULL,
       image_bytes bytea NOT NULL,
       created_at timestamptz NOT NULL DEFAULT NOW()
     )`,
  );
  await target(
    `CREATE INDEX IF NOT EXISTS idx_backend_image_assets_business_created
     ON backend_image_assets (business_id, created_at DESC)`,
  );
  schemaReady = true;
}

async function saveBackendImageAsset(
  target,
  { businessId, assetKind, contentType, bytes },
) {
  if (!businessId || !assetKind || !contentType || !Buffer.isBuffer(bytes)) {
    throw new Error('Complete backend image asset details are required.');
  }
  await ensureBackendImageAssetSchema(target);
  const id = crypto.randomUUID();
  const result = await target(
    `INSERT INTO backend_image_assets (
       id, business_id, asset_kind, content_type, byte_size, image_bytes
     ) VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, content_type, byte_size, created_at`,
    [id, businessId, assetKind, contentType, bytes.length, bytes],
  );
  return result.rows[0] || {
    id,
    content_type: contentType,
    byte_size: bytes.length,
  };
}

async function loadBackendImageAsset(target, id) {
  if (!id) return null;
  await ensureBackendImageAssetSchema(target);
  const result = await target(
    `SELECT id, content_type, byte_size, image_bytes, created_at
     FROM backend_image_assets
     WHERE id = $1
     LIMIT 1`,
    [id],
  );
  return result.rows[0] || null;
}

function backendImageAssetUrl(baseUrl, id) {
  const root = String(baseUrl || '').replace(/\/+$/, '');
  if (!root || !id) return '';
  return `${root}/api/files/images/${encodeURIComponent(id)}`;
}

function resetBackendImageAssetSchemaForTests() {
  schemaReady = false;
}

module.exports = {
  backendImageAssetUrl,
  ensureBackendImageAssetSchema,
  loadBackendImageAsset,
  resetBackendImageAssetSchemaForTests,
  saveBackendImageAsset,
};
