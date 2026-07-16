const test = require('node:test');
const assert = require('node:assert/strict');

const {
  backendImageAssetUrl,
  loadBackendImageAsset,
  resetBackendImageAssetSchemaForTests,
  saveBackendImageAsset,
} = require('../src/backendImageAssets');

test('backend image fallback stores and reloads durable image bytes', async () => {
  resetBackendImageAssetSchemaForTests();
  const rows = new Map();
  const target = async (sql, params = []) => {
    if (/CREATE TABLE|CREATE INDEX/i.test(sql)) return { rows: [] };
    if (/INSERT INTO backend_image_assets/i.test(sql)) {
      const row = {
        id: params[0],
        content_type: params[3],
        byte_size: params[4],
        image_bytes: params[5],
      };
      rows.set(row.id, row);
      return { rows: [row] };
    }
    if (/FROM backend_image_assets/i.test(sql)) {
      return { rows: rows.has(params[0]) ? [rows.get(params[0])] : [] };
    }
    throw new Error(`Unexpected SQL: ${sql}`);
  };

  const bytes = Buffer.from('persistent-image');
  const saved = await saveBackendImageAsset(target, {
    businessId: 'business-1',
    assetKind: 'product',
    contentType: 'image/webp',
    bytes,
  });
  const loaded = await loadBackendImageAsset(target, saved.id);

  assert.equal(loaded.content_type, 'image/webp');
  assert.equal(loaded.byte_size, bytes.length);
  assert.deepEqual(loaded.image_bytes, bytes);
  assert.equal(
    backendImageAssetUrl('https://api.pikipos.com/', saved.id),
    `https://api.pikipos.com/api/files/images/${saved.id}`,
  );
});
