const dns = require('dns/promises');
const net = require('net');
const crypto = require('crypto');

const {
  decryptSecretObject,
  encryptSecretObject,
} = require('./secretVault');

const AUTH_TYPES = new Set(['none', 'bearer', 'apiKey']);

async function ensureStorefrontConnectionSchema(target) {
  await run(target, `
    CREATE TABLE IF NOT EXISTS storefront_connections (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      name text NOT NULL,
      endpoint_url text NOT NULL,
      auth_type text NOT NULL DEFAULT 'none',
      api_key_header text,
      secret_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      data_path text,
      field_mappings_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      is_enabled boolean NOT NULL DEFAULT false,
      last_tested_at timestamptz,
      last_test_status text,
      last_test_message text,
      created_by text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      deleted_at timestamptz
    )
  `);
  await run(target, `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_storefront_connections_scope
      ON storefront_connections (business_id, branch_id)
      WHERE deleted_at IS NULL
  `);
}

async function getStorefrontConnection(target, businessId, branchId = 'main_branch') {
  await ensureStorefrontConnectionSchema(target);
  const result = await run(target, `
    SELECT * FROM storefront_connections
    WHERE business_id=$1 AND branch_id=$2 AND deleted_at IS NULL LIMIT 1
  `, [businessId, normalizeBranchId(branchId)]);
  return result.rows[0] ? normalizeConnectionRow(result.rows[0]) : null;
}

async function saveStorefrontConnection(target, businessId, input, options = {}) {
  await ensureStorefrontConnectionSchema(target);
  const existing = await getStorefrontConnection(target, businessId, input.branchId);
  const normalized = normalizeConnectionInput(input, existing);
  const id = existing?.id || crypto.randomUUID();
  let secretJson = existing?.secretEnvelope || {};
  const secret = normalizeText(input.secret ?? input.token ?? input.apiKey);
  if (secret) {
    if (!options.encryptionKey) {
      throw createError(503, 'Secure API credential storage is not configured on the server.');
    }
    secretJson = encryptSecretObject(
      { secret },
      {
        encryptionKey: options.encryptionKey,
        additionalData: secretAdditionalData(businessId, id),
      },
    );
  } else if (input.clearSecret === true || normalized.authType === 'none') {
    secretJson = {};
  }
  if (normalized.authType !== 'none' && !Object.keys(secretJson).length) {
    throw createError(400, 'Add the API credential before enabling this connection.');
  }
  const result = existing
    ? await run(target, `
        UPDATE storefront_connections SET
          name=$3, endpoint_url=$4, auth_type=$5, api_key_header=$6,
          secret_json=$7::jsonb, data_path=$8, field_mappings_json=$9::jsonb,
          is_enabled=$10, updated_at=NOW()
        WHERE business_id=$1 AND id=$2 AND deleted_at IS NULL RETURNING *
      `, [businessId, id, normalized.name, normalized.endpointUrl,
        normalized.authType, normalized.apiKeyHeader, JSON.stringify(secretJson),
        normalized.dataPath, JSON.stringify(normalized.fieldMappings), normalized.isEnabled])
    : await run(target, `
        INSERT INTO storefront_connections (
          id,business_id,branch_id,name,endpoint_url,auth_type,api_key_header,
          secret_json,data_path,field_mappings_json,is_enabled,created_by
        ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10::jsonb,$11,$12)
        RETURNING *
      `, [id, businessId, normalized.branchId, normalized.name,
        normalized.endpointUrl, normalized.authType, normalized.apiKeyHeader,
        JSON.stringify(secretJson), normalized.dataPath,
        JSON.stringify(normalized.fieldMappings), normalized.isEnabled,
        options.createdBy || null]);
  return normalizeConnectionRow(result.rows[0]);
}

async function testStorefrontConnection(target, businessId, branchId, options = {}) {
  const connection = await getStorefrontConnection(target, businessId, branchId);
  if (!connection) throw createError(404, 'Store API connection was not found.');
  try {
    const items = await fetchConnectionProducts(connection, {
      encryptionKey: options.encryptionKey,
      fetchImpl: options.fetchImpl,
    });
    await recordTest(target, connection.id, 'success', `${items.length} products received`);
    return { connection, itemCount: items.length, message: `${items.length} products received safely.` };
  } catch (error) {
    await recordTest(target, connection.id, 'failed', limitText(error.message, 240));
    throw error;
  }
}

async function hasEnabledStorefrontConnection(target, businessId, branchId) {
  const connection = await getStorefrontConnection(target, businessId, branchId);
  return connection?.isEnabled === true;
}

async function loadDynamicStorefrontProducts(target, businessId, branchId, options = {}) {
  const connection = await getStorefrontConnection(target, businessId, branchId);
  if (!connection?.isEnabled) return [];
  try {
    return await fetchConnectionProducts(connection, {
      encryptionKey: options.encryptionKey,
      fetchImpl: options.fetchImpl,
    });
  } catch (_) {
    return [];
  }
}

async function fetchConnectionProducts(connection, options = {}) {
  await assertSafeEndpoint(connection.endpointUrl);
  const headers = { Accept: 'application/json' };
  if (connection.authType !== 'none') {
    if (!options.encryptionKey) throw createError(503, 'Secure API credential storage is unavailable.');
    const decrypted = decryptSecretObject(connection.secretEnvelope, {
      encryptionKey: options.encryptionKey,
      additionalData: secretAdditionalData(connection.businessId, connection.id),
    }).value;
    const secret = normalizeText(decrypted.secret);
    if (!secret) throw createError(400, 'The stored API credential is missing.');
    if (connection.authType === 'bearer') headers.Authorization = `Bearer ${secret}`;
    if (connection.authType === 'apiKey') headers[connection.apiKeyHeader || 'X-API-Key'] = secret;
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    const fetchImpl = options.fetchImpl || globalThis.fetch;
    const response = await fetchImpl(connection.endpointUrl, {
      method: 'GET',
      headers,
      redirect: 'manual',
      signal: controller.signal,
    });
    if (response.status >= 300 && response.status < 400) {
      throw createError(400, 'Store API redirects are not allowed. Use the final HTTPS endpoint.');
    }
    if (!response.ok) throw createError(502, `Store API returned HTTP ${response.status}.`);
    const length = Number(response.headers?.get?.('content-length') || 0);
    if (length > 2_000_000) throw createError(400, 'Store API response is too large.');
    const text = await response.text();
    if (text.length > 2_000_000) throw createError(400, 'Store API response is too large.');
    let payload;
    try { payload = JSON.parse(text); } catch (_) { throw createError(502, 'Store API did not return valid JSON.'); }
    const source = valueAtPath(payload, connection.dataPath);
    if (!Array.isArray(source)) throw createError(400, 'The configured data path does not contain a product list.');
    return source.slice(0, 500).map((item, index) => normalizeExternalProduct(item, index, connection)).filter(Boolean);
  } catch (error) {
    if (error?.name === 'AbortError') throw createError(504, 'Store API took too long to respond.');
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

function normalizeExternalProduct(value, index, connection) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const map = connection.fieldMappings;
  const read = (key, defaults) => {
    const configured = normalizeText(map[key]);
    if (configured) return valueAtPath(value, configured);
    for (const candidate of defaults) {
      const result = valueAtPath(value, candidate);
      if (result != null) return result;
    }
    return null;
  };
  const name = limitText(read('name', ['name', 'title']), 160);
  const price = Number(read('price', ['price', 'selling_price', 'amount']));
  if (!name || !Number.isFinite(price) || price < 0) return null;
  const sourceId = limitText(read('id', ['id', 'sku', 'code']), 120) || String(index + 1);
  const stock = Number(read('stock', ['stock', 'quantity', 'inventory']));
  const imageUrl = safeHttpsUrl(read('imageUrl', ['imageUrl', 'image_url', 'image', 'thumbnail']));
  return {
    type: 'product',
    itemType: 'product',
    id: `external:${connection.id}:${sourceId}`,
    externalId: sourceId,
    productId: null,
    serviceId: null,
    name,
    price,
    compareAtPrice: numberOrNull(read('compareAtPrice', ['compareAtPrice', 'compare_at_price', 'regular_price'])),
    stock: Number.isFinite(stock) ? Math.max(0, stock) : 0,
    trackStock: Number.isFinite(stock),
    imageUrl,
    externalCheckoutUrl: safeHttpsUrl(read('checkoutUrl', ['checkoutUrl', 'checkout_url', 'url', 'permalink'])),
    imageUrls: imageUrl ? [imageUrl] : [],
    brand: limitText(read('brand', ['brand', 'vendor']), 100),
    description: limitText(read('description', ['description', 'summary']), 1000),
    category: limitText(read('category', ['category', 'category_name']), 100) || 'Products',
    showOnline: true,
    isFeatured: Boolean(read('isFeatured', ['isFeatured', 'featured'])),
    hasVariants: false,
    variants: [],
    source: 'external_api',
  };
}

function normalizeConnectionInput(input = {}, existing = null) {
  const endpointUrl = normalizeEndpoint(input.endpointUrl ?? input.endpoint_url ?? existing?.endpointUrl);
  const authType = normalizeEnum(input.authType ?? input.auth_type ?? existing?.authType, AUTH_TYPES, 'none');
  return {
    branchId: normalizeBranchId(input.branchId ?? input.branch_id ?? existing?.branchId),
    name: limitText(input.name ?? existing?.name, 80) || 'Store product API',
    endpointUrl,
    authType,
    apiKeyHeader: authType === 'apiKey'
      ? normalizeHeaderName(input.apiKeyHeader ?? input.api_key_header ?? existing?.apiKeyHeader)
      : null,
    dataPath: limitText(input.dataPath ?? input.data_path ?? existing?.dataPath, 160) || '',
    fieldMappings: normalizeMappings(input.fieldMappings ?? input.field_mappings ?? existing?.fieldMappings),
    isEnabled: booleanValue(input.isEnabled ?? input.is_enabled, existing?.isEnabled ?? false),
  };
}

function normalizeConnectionRow(row) {
  return {
    id: String(row.id),
    businessId: String(row.business_id ?? row.businessId),
    branchId: normalizeBranchId(row.branch_id ?? row.branchId),
    name: row.name || 'Store product API',
    endpointUrl: row.endpoint_url ?? row.endpointUrl,
    authType: normalizeEnum(row.auth_type ?? row.authType, AUTH_TYPES, 'none'),
    apiKeyHeader: row.api_key_header ?? row.apiKeyHeader ?? 'X-API-Key',
    dataPath: row.data_path ?? row.dataPath ?? '',
    fieldMappings: parseObject(row.field_mappings_json ?? row.fieldMappings),
    isEnabled: row.is_enabled ?? row.isEnabled ?? false,
    hasSecret: Object.keys(parseObject(row.secret_json ?? row.secretEnvelope)).length > 0,
    secretEnvelope: parseObject(row.secret_json ?? row.secretEnvelope),
    lastTestedAt: toIsoString(row.last_tested_at ?? row.lastTestedAt),
    lastTestStatus: row.last_test_status ?? row.lastTestStatus ?? null,
    lastTestMessage: row.last_test_message ?? row.lastTestMessage ?? null,
  };
}

async function assertSafeEndpoint(value) {
  const url = new URL(normalizeEndpoint(value));
  const host = url.hostname.toLowerCase();
  if (host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) {
    throw createError(400, 'Private network API endpoints are not allowed.');
  }
  if (net.isIP(host)) {
    if (isPrivateAddress(host)) throw createError(400, 'Private network API endpoints are not allowed.');
    return;
  }
  const addresses = await dns.lookup(host, { all: true, verbatim: true });
  if (!addresses.length || addresses.some((entry) => isPrivateAddress(entry.address))) {
    throw createError(400, 'The API endpoint must resolve to a public internet address.');
  }
}

function isPrivateAddress(address) {
  if (net.isIPv4(address)) {
    const [a, b] = address.split('.').map(Number);
    return a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || a >= 224;
  }
  const clean = String(address).toLowerCase();
  return clean === '::1' || clean === '::' || clean.startsWith('fc') || clean.startsWith('fd') || clean.startsWith('fe8') || clean.startsWith('fe9') || clean.startsWith('fea') || clean.startsWith('feb');
}

function normalizeEndpoint(value) {
  const clean = normalizeText(value);
  if (!clean) throw createError(400, 'Store API endpoint is required.');
  try {
    const url = new URL(clean);
    if (url.protocol !== 'https:' || url.username || url.password) throw new Error();
    return url.toString();
  } catch (_) {
    throw createError(400, 'Use a public HTTPS store API endpoint without credentials in the URL.');
  }
}

function normalizeHeaderName(value) {
  const clean = normalizeText(value) || 'X-API-Key';
  if (!/^[A-Za-z][A-Za-z0-9-]{0,60}$/.test(clean)) throw createError(400, 'API key header name is invalid.');
  const forbidden = new Set(['host', 'cookie', 'content-length', 'connection', 'transfer-encoding']);
  if (forbidden.has(clean.toLowerCase())) throw createError(400, 'That API header cannot be used.');
  return clean;
}

function normalizeMappings(value) {
  const raw = parseObject(value);
  const allowed = ['id', 'name', 'price', 'compareAtPrice', 'stock', 'imageUrl', 'checkoutUrl', 'brand', 'description', 'category', 'isFeatured'];
  return Object.fromEntries(allowed.map((key) => [key, normalizePath(raw[key])]).filter(([, item]) => item));
}

function normalizePath(value) {
  const clean = normalizeText(value);
  return clean && /^[A-Za-z0-9_$-]+(?:\.[A-Za-z0-9_$-]+)*$/.test(clean) ? clean : '';
}

function valueAtPath(value, path) {
  if (!path) return Array.isArray(value) ? value : value?.products ?? value?.items ?? value?.data ?? value;
  return String(path).split('.').reduce((current, key) => current == null ? undefined : current[key], value);
}

async function recordTest(target, id, status, message) {
  await run(target, `UPDATE storefront_connections SET last_tested_at=NOW(), last_test_status=$2, last_test_message=$3, updated_at=NOW() WHERE id=$1`, [id, status, message]);
}

function secretAdditionalData(businessId, id) { return `storefront-connection:${businessId}:${id}`; }
function safeHttpsUrl(value) { try { const url = new URL(String(value || '')); return url.protocol === 'https:' ? url.toString() : null; } catch (_) { return null; } }
function numberOrNull(value) { const number = Number(value); return Number.isFinite(number) && number >= 0 ? number : null; }
function normalizeBranchId(value) { return limitText(value, 120) || 'main_branch'; }
function normalizeEnum(value, allowed, fallback) { const clean = String(value || '').trim(); return allowed.has(clean) ? clean : fallback; }
function normalizeText(value) { const clean = String(value ?? '').trim(); return clean || null; }
function limitText(value, max) { const clean = normalizeText(value); return clean ? clean.slice(0, max) : null; }
function booleanValue(value, fallback) { if (value == null) return Boolean(fallback); if (typeof value === 'boolean') return value; return !['false','0','no','off'].includes(String(value).toLowerCase()); }
function parseObject(value) { if (value && typeof value === 'object' && !Array.isArray(value)) return value; try { const parsed = JSON.parse(String(value || '{}')); return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {}; } catch (_) { return {}; } }
function toIsoString(value) { if (!value) return null; const parsed = new Date(value); return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString(); }
function createError(statusCode, message) { const error = new Error(message); error.statusCode = statusCode; return error; }
function run(target, sql, params = []) { return typeof target === 'function' ? target(sql, params) : target.query(sql, params); }

module.exports = {
  ensureStorefrontConnectionSchema,
  fetchConnectionProducts,
  getStorefrontConnection,
  hasEnabledStorefrontConnection,
  loadDynamicStorefrontProducts,
  normalizeConnectionInput,
  normalizeConnectionRow,
  saveStorefrontConnection,
  testStorefrontConnection,
};
