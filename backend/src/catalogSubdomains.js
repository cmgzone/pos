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
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_businesses_public_subdomain_unique
     ON businesses (LOWER(public_subdomain))
     WHERE public_subdomain IS NOT NULL`,
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
     LIMIT 1`,
    [cleanBusinessId],
  );
  const business = existingResult.rows[0];
  if (!business) {
    throw new Error('Business not found');
  }

  const existing = normalizeCatalogSubdomain(business.public_subdomain);
  if (existing) {
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

async function findBusinessIdByCatalogSubdomain(target, subdomain) {
  const normalized = normalizeCatalogSubdomain(subdomain);
  if (!normalized) {
    return null;
  }

  await ensureCatalogSubdomainSchema(target);
  const result = await runQuery(
    target,
    `SELECT id
     FROM businesses
     WHERE LOWER(public_subdomain) = LOWER($1)
     LIMIT 1`,
    [normalized],
  );
  return normalizeText(result.rows[0]?.id);
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
  buildCatalogStorefrontUrl,
  buildCatalogSubdomainCandidates,
  catalogSubdomainBase,
  ensureBusinessCatalogSubdomain,
  ensureCatalogSubdomainSchema,
  extractCatalogSubdomain,
  findBusinessIdByCatalogSubdomain,
  initializeCatalogSubdomainSchema,
  normalizeCatalogSubdomain,
};
