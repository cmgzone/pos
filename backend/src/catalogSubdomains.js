const crypto = require('crypto');

const RESERVED_SUBDOMAINS = new Set([
  'admin',
  'api',
  'app',
  'assets',
  'cdn',
  'coolify',
  'help',
  'mail',
  'pikipos',
  'shop',
  'status',
  'store',
  'support',
  'www',
]);
const STOREFRONT_SUBDOMAIN_TYPES = new Set([
  'retail',
  'services',
  'restaurant',
]);

let defaultSchemaPromise = null;

function ensureCatalogSubdomainSchema(target) {
  if (typeof target === 'function') {
    return initializeCatalogSubdomainSchema(target);
  }
  return applyCatalogSubdomainSchema(target);
}

async function applyCatalogSubdomainSchema(target) {
  if (!target) {
    throw new Error('A database query target is required');
  }
  await runQuery(
    target,
    `ALTER TABLE businesses
     ADD COLUMN IF NOT EXISTS public_subdomain text`,
  );
  await runQuery(
    target,
    `ALTER TABLE businesses
     ADD COLUMN IF NOT EXISTS primary_storefront_type text`,
  );
  await runQuery(
    target,
    `ALTER TABLE businesses
     ADD COLUMN IF NOT EXISTS deleted_at timestamptz`,
  );
  await runQuery(
    target,
    `ALTER TABLE businesses
     ADD COLUMN IF NOT EXISTS subdomain_released_at timestamptz`,
  );
  await runQuery(
    target,
    `DO $$
     BEGIN
       IF EXISTS (
         SELECT 1
         FROM pg_indexes
         WHERE indexname = 'idx_businesses_public_subdomain_unique'
           AND indexdef NOT ILIKE '%deleted_at IS NULL%'
       ) THEN
         DROP INDEX idx_businesses_public_subdomain_unique;
       END IF;
     END $$`,
  );
  await runQuery(
    target,
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_businesses_public_subdomain_unique
     ON businesses (LOWER(public_subdomain))
     WHERE public_subdomain IS NOT NULL
       AND deleted_at IS NULL`,
  );
  await runQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_businesses_deleted_at
     ON businesses (deleted_at)`,
  );
}

function initializeCatalogSubdomainSchema(target) {
  if (!defaultSchemaPromise) {
    defaultSchemaPromise = applyCatalogSubdomainSchema(target).catch((error) => {
      defaultSchemaPromise = null;
      throw error;
    });
  }
  return defaultSchemaPromise;
}

async function ensureBusinessCatalogSubdomain(
  target,
  { businessId, businessName },
) {
  const cleanBusinessId = normalizeText(businessId);
  if (!cleanBusinessId) {
    throw new Error('businessId is required');
  }

  await ensureCatalogSubdomainSchema(target);
  const existingResult = await runQuery(
    target,
    `SELECT name, public_subdomain
     FROM businesses
     WHERE id = $1
       AND deleted_at IS NULL
     LIMIT 1`,
    [cleanBusinessId],
  );
  const business = existingResult.rows[0];
  if (!business) {
    throw new Error('Business not found');
  }

  const existing = normalizeCatalogSubdomain(business.public_subdomain);
  if (existing) {
    await ensureBusinessStorefronts(target, {
      businessId: cleanBusinessId,
      businessSubdomain: existing,
    });
    return existing;
  }

  const candidates = buildCatalogSubdomainCandidates(
    businessName || business.name,
    cleanBusinessId,
  );
  for (const candidate of candidates) {
    try {
      const updated = await runQuery(
        target,
        `UPDATE businesses
         SET public_subdomain = $2,
             updated_at = NOW()
         WHERE id = $1
           AND public_subdomain IS NULL
           AND deleted_at IS NULL
         RETURNING public_subdomain`,
        [cleanBusinessId, candidate],
      );
      const assigned = normalizeCatalogSubdomain(
        updated.rows[0]?.public_subdomain,
      );
      if (assigned) {
        return assigned;
      }

      const raced = await runQuery(
        target,
        `SELECT public_subdomain
         FROM businesses
         WHERE id = $1
           AND deleted_at IS NULL
         LIMIT 1`,
        [cleanBusinessId],
      );
      const racedValue = normalizeCatalogSubdomain(
        raced.rows[0]?.public_subdomain,
      );
      if (racedValue) {
        return racedValue;
      }
    } catch (error) {
      if (error?.code !== '23505') {
        throw error;
      }
    }
  }

  throw new Error('Could not assign a unique catalog subdomain');
}

async function ensureBusinessStorefrontsWithSubdomain(
  target,
  { businessId, businessSubdomain },
) {
  return ensureBusinessStorefronts(target, { businessId, businessSubdomain });
}

async function findBusinessIdByCatalogSubdomain(target, subdomain) {
  const storefront = await findBusinessCatalogStorefrontBySubdomain(
    target,
    subdomain,
  );
  return storefront?.businessId || null;
}

async function findBusinessCatalogStorefrontBySubdomain(target, subdomain) {
  const normalized = normalizeCatalogSubdomain(subdomain);
  if (!normalized) {
    return null;
  }

  // Independent storefront records take priority so each module keeps its own
  // unique website even when a legacy business subdomain also resolves.
  const storefront = await findStorefrontBySubdomain(target, normalized);
  if (storefront) {
    return {
      businessId: storefront.businessId,
      storefrontType: storefront.storefrontType,
      storefrontId: storefront.storefrontId,
      title: storefront.title,
    };
  }

  await ensureCatalogSubdomainSchema(target);
  const result = await runQuery(
    target,
    `SELECT id
     FROM businesses
     WHERE LOWER(public_subdomain) = LOWER($1)
       AND deleted_at IS NULL
     LIMIT 1`,
    [normalized],
  );
  const businessId = normalizeText(result.rows[0]?.id);
  if (businessId) {
    return { businessId, storefrontType: null, storefrontId: null, title: null };
  }

  const parsed = parseCatalogStorefrontSubdomain(normalized);
  if (!parsed) {
    return null;
  }
  const storefrontResult = await runQuery(
    target,
    `SELECT id
     FROM businesses
     WHERE LOWER(public_subdomain) = LOWER($1)
       AND deleted_at IS NULL
     LIMIT 1`,
    [parsed.businessSubdomain],
  );
  const storefrontBusinessId = normalizeText(storefrontResult.rows[0]?.id);
  return storefrontBusinessId
    ? {
        businessId: storefrontBusinessId,
        storefrontType: parsed.storefrontType,
        storefrontId: null,
        title: null,
      }
    : null;
}

async function ensureStorefrontSchema(target) {
  if (!target) {
    throw new Error('A database query target is required');
  }
  await runQuery(
    target,
    `CREATE TABLE IF NOT EXISTS storefronts (
      id text PRIMARY KEY,
      business_id text NOT NULL,
      type text NOT NULL,
      subdomain text,
      title text,
      tagline text,
      description text,
      logo_url text,
      cover_url text,
      primary_color text,
      is_primary boolean NOT NULL DEFAULT false,
      status text NOT NULL DEFAULT 'active',
      created_at timestamptz NOT NULL,
      updated_at timestamptz NOT NULL,
      deleted_at timestamptz
    )`,
  );
  await runQuery(
    target,
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_storefronts_subdomain_unique
     ON storefronts (LOWER(subdomain))
     WHERE subdomain IS NOT NULL AND deleted_at IS NULL`,
  );
  await runQuery(
    target,
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_storefronts_business_type_unique
     ON storefronts (business_id, type)
     WHERE deleted_at IS NULL`,
  );
  await runQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_storefronts_business
     ON storefronts (business_id)`,
  );
}

// A subdomain is globally reserved when it is used by any business OR any
// storefront, so module websites can never collide with a business website.
async function isSubdomainTaken(target, subdomain) {
  const normalized = normalizeCatalogSubdomain(subdomain);
  if (!normalized || RESERVED_SUBDOMAINS.has(normalized)) {
    return true;
  }
  await ensureCatalogSubdomainSchema(target);
  await ensureStorefrontSchema(target);
  const business = await runQuery(
    target,
    `SELECT 1 FROM businesses
     WHERE LOWER(public_subdomain) = LOWER($1)
       AND deleted_at IS NULL
     LIMIT 1`,
    [normalized],
  );
  if (business.rows.length) {
    return true;
  }
  const storefront = await runQuery(
    target,
    `SELECT 1 FROM storefronts
     WHERE LOWER(subdomain) = LOWER($1)
       AND deleted_at IS NULL
     LIMIT 1`,
    [normalized],
  );
  return storefront.rows.length > 0;
}

// Creates (or skips if present) one independent storefront record per module
// type for a business. Each storefront gets a globally unique subdomain.
async function ensureBusinessStorefronts(
  target,
  { businessId, businessSubdomain, types },
) {
  const cleanBusinessId = normalizeText(businessId);
  const base = normalizeCatalogSubdomain(businessSubdomain);
  if (!cleanBusinessId || !base) {
    return [];
  }
  await ensureStorefrontSchema(target);
  const typeList =
    types && types.length
      ? types.filter(Boolean)
      : ['retail', 'services', 'restaurant'];
  const now = new Date().toISOString();
  const created = [];

  for (const type of typeList) {
    const normalizedType = normalizeCatalogStorefrontType(type);
    if (!normalizedType) continue;

    const existing = await runQuery(
      target,
      `SELECT id, subdomain, type
       FROM storefronts
       WHERE business_id = $1 AND type = $2 AND deleted_at IS NULL
       LIMIT 1`,
      [cleanBusinessId, normalizedType],
    );
    if (existing.rows[0]) {
      created.push({
        storefrontId: existing.rows[0].id,
        businessId: cleanBusinessId,
        storefrontType: normalizedType,
        subdomain: normalizeCatalogSubdomain(existing.rows[0].subdomain),
      });
      continue;
    }

    const desired = buildCatalogStorefrontSubdomain(base, normalizedType);
    let subdomain = desired;
    for (let attempt = 0; attempt <= 12; attempt += 1) {
      const candidate =
        attempt === 0 ? desired : fitDnsLabel(`${desired}-${attempt}`);
      if (!(await isSubdomainTaken(target, candidate))) {
        subdomain = candidate;
        break;
      }
    }

    const id = crypto.randomUUID();
    await runQuery(
      target,
      `INSERT INTO storefronts
        (id, business_id, type, subdomain, is_primary, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, 'active', $6, $6)`,
      [id, cleanBusinessId, normalizedType, subdomain, normalizedType === 'retail', now, now],
    );
    created.push({
      storefrontId: id,
      businessId: cleanBusinessId,
      storefrontType: normalizedType,
      subdomain,
    });
  }
  return created;
}

async function findStorefrontBySubdomain(target, subdomain) {
  const normalized = normalizeCatalogSubdomain(subdomain);
  if (!normalized) {
    return null;
  }
  await ensureStorefrontSchema(target);
  const result = await runQuery(
    target,
    `SELECT id, business_id, type, title
     FROM storefronts
     WHERE LOWER(subdomain) = LOWER($1)
       AND deleted_at IS NULL
     LIMIT 1`,
    [normalized],
  );
  const row = result.rows[0];
  if (!row) {
    return null;
  }
  return {
    storefrontId: normalizeText(row.id),
    businessId: normalizeText(row.business_id),
    storefrontType: normalizeCatalogStorefrontType(row.type),
    title: row.title,
  };
}

async function listBusinessStorefronts(target, businessId) {
  const cleanBusinessId = normalizeText(businessId);
  if (!cleanBusinessId) {
    return [];
  }
  await ensureStorefrontSchema(target);
  const result = await runQuery(
    target,
    `SELECT id, business_id, type, subdomain, title, tagline, description,
            logo_url, cover_url, primary_color, is_primary, status
     FROM storefronts
     WHERE business_id = $1 AND deleted_at IS NULL
     ORDER BY type ASC`,
    [cleanBusinessId],
  );
  return result.rows.map((row) => ({
    id: normalizeText(row.id),
    businessId: cleanBusinessId,
    type: normalizeCatalogStorefrontType(row.type),
    subdomain: normalizeCatalogSubdomain(row.subdomain),
    title: row.title,
    tagline: row.tagline,
    description: row.description,
    logoUrl: row.logo_url,
    coverUrl: row.cover_url,
    primaryColor: row.primary_color,
    isPrimary: Boolean(row.is_primary),
    status: row.status,
  }));
}

function normalizeCatalogStorefrontType(value) {
  const type = normalizeText(value)?.toLowerCase();
  switch (type) {
    case 'retail':
    case 'store':
    case 'shop':
      return 'retail';
    case 'services':
    case 'service':
      return 'services';
    case 'restaurant':
    case 'menu':
      return 'restaurant';
    default:
      return null;
  }
}

function buildCatalogStorefrontSubdomain(businessSubdomain, storefrontType) {
  const business = normalizeCatalogSubdomain(businessSubdomain);
  const type = normalizeCatalogStorefrontType(storefrontType);
  if (!business || !type) {
    throw new Error('Catalog storefront subdomain is invalid');
  }
  const suffix = `-${type}`;
  const base = fitDnsLabel(business, 63 - suffix.length);
  const value = normalizeCatalogSubdomain(`${base}${suffix}`);
  if (!value) {
    throw new Error('Catalog storefront subdomain is invalid');
  }
  return value;
}

function parseCatalogStorefrontSubdomain(subdomain) {
  const normalized = normalizeCatalogSubdomain(subdomain);
  if (!normalized) return null;
  for (const type of STOREFRONT_SUBDOMAIN_TYPES) {
    const suffix = `-${type}`;
    if (!normalized.endsWith(suffix)) continue;
    const businessSubdomain = normalizeCatalogSubdomain(
      normalized.slice(0, -suffix.length),
    );
    if (businessSubdomain) {
      return { businessSubdomain, storefrontType: type };
    }
  }
  return null;
}

function buildCatalogSubdomainCandidates(businessName, businessId) {
  const base = catalogSubdomainBase(businessName);
  const suffix =
    String(businessId || '')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '')
      .slice(0, 8) || 'store';
  const candidates = [base, fitDnsLabel(`${base}-${suffix}`)];
  for (let attempt = 2; attempt <= 8; attempt += 1) {
    candidates.push(fitDnsLabel(`${base}-${suffix}-${attempt}`));
  }
  return [...new Set(candidates.filter(Boolean))];
}

function catalogSubdomainBase(value) {
  const normalized = String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-');

  let base = normalized || 'my-shop';
  if (/^\d+$/.test(base)) {
    base = `shop-${base}`;
  }
  if (RESERVED_SUBDOMAINS.has(base)) {
    base = `${base}-shop`;
  }
  return fitDnsLabel(base, 48) || 'my-shop';
}

function normalizeCatalogSubdomain(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (
    !normalized ||
    normalized.length > 63 ||
    RESERVED_SUBDOMAINS.has(normalized) ||
    !/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(normalized)
  ) {
    return null;
  }
  return normalized;
}

function extractCatalogSubdomain(hostValue, rootDomain) {
  const root = normalizeHostname(rootDomain);
  const host = normalizeHostname(String(hostValue || '').split(',')[0]);
  if (!root || !host || host === root || host === `www.${root}`) {
    return null;
  }

  const suffix = `.${root}`;
  if (!host.endsWith(suffix)) {
    return null;
  }
  const subdomain = host.slice(0, -suffix.length);
  if (!subdomain || subdomain.includes('.')) {
    return null;
  }
  return normalizeCatalogSubdomain(subdomain);
}

function buildCatalogStorefrontUrl(rootDomain, subdomain) {
  const root = normalizeHostname(rootDomain);
  const normalizedSubdomain = normalizeCatalogSubdomain(subdomain);
  if (!root || !normalizedSubdomain) {
    throw new Error('Catalog storefront domain is invalid');
  }
  return `https://${normalizedSubdomain}.${root}`;
}

function isCatalogStorefrontOrigin(origin, rootDomain, options = {}) {
  const normalizedOrigin = String(origin || '').trim().replace(/\/+$/, '');
  if (!normalizedOrigin) {
    return false;
  }

  let parsed;
  try {
    parsed = new URL(normalizedOrigin);
  } catch (_) {
    return false;
  }

  const allowHttp = Boolean(options.allowHttp);
  if (parsed.protocol !== 'https:' && !(allowHttp && parsed.protocol === 'http:')) {
    return false;
  }
  if (parsed.username || parsed.password || parsed.pathname !== '/' || parsed.search || parsed.hash) {
    return false;
  }

  return Boolean(extractCatalogSubdomain(parsed.host, rootDomain));
}

function fitDnsLabel(value, maxLength = 63) {
  return String(value || '')
    .slice(0, maxLength)
    .replace(/-+$/g, '');
}

function normalizeHostname(value) {
  let normalized = String(value || '').trim().toLowerCase();
  if (!normalized) {
    return '';
  }
  normalized = normalized.replace(/^\w+:\/\//, '').split('/')[0];
  normalized = normalized.replace(/\.$/, '');
  if (normalized.startsWith('[')) {
    return normalized;
  }
  return normalized.split(':')[0];
}

function normalizeText(value) {
  const normalized = String(value || '').trim();
  return normalized || null;
}

function runQuery(target, sql, params = []) {
  if (typeof target === 'function') {
    return target(sql, params);
  }
  return target.query(sql, params);
}

module.exports = {
  RESERVED_SUBDOMAINS,
  STOREFRONT_SUBDOMAIN_TYPES,
  buildCatalogStorefrontSubdomain,
  buildCatalogStorefrontUrl,
  buildCatalogSubdomainCandidates,
  catalogSubdomainBase,
  ensureBusinessCatalogSubdomain,
  ensureBusinessStorefronts,
  ensureCatalogSubdomainSchema,
  ensureStorefrontSchema,
  extractCatalogSubdomain,
  findBusinessCatalogStorefrontBySubdomain,
  findBusinessIdByCatalogSubdomain,
  findStorefrontBySubdomain,
  initializeCatalogSubdomainSchema,
  isCatalogStorefrontOrigin,
  isSubdomainTaken,
  listBusinessStorefronts,
  normalizeCatalogStorefrontType,
  normalizeCatalogSubdomain,
  parseCatalogStorefrontSubdomain,
};
