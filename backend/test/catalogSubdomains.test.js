const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildCatalogStorefrontUrl,
  buildCatalogStorefrontSubdomain,
  buildCatalogSubdomainCandidates,
  catalogSubdomainBase,
  ensureBusinessCatalogSubdomain,
  ensureBusinessStorefronts,
  extractCatalogSubdomain,
  findBusinessCatalogStorefrontBySubdomain,
  findBusinessIdByCatalogSubdomain,
  isCatalogStorefrontOrigin,
  normalizeCatalogSubdomain,
  parseCatalogStorefrontSubdomain,
} = require('../src/catalogSubdomains');

test('catalog subdomain base creates a clean DNS label', () => {
  assert.equal(
    catalogSubdomainBase('Pólesio Rahisi & Sons'),
    'polesio-rahisi-and-sons',
  );
  assert.equal(catalogSubdomainBase('  12345  '), 'shop-12345');
});

test('reserved catalog subdomains receive a shop suffix', () => {
  assert.equal(catalogSubdomainBase('Admin'), 'admin-shop');
  assert.equal(normalizeCatalogSubdomain('admin'), null);
  assert.equal(normalizeCatalogSubdomain('my-shop'), 'my-shop');
});

test('catalog subdomain candidates include a stable business id fallback', () => {
  const candidates = buildCatalogSubdomainCandidates(
    'My Shop',
    'd28ba96d-c182-4b76-8fe7-e8d9ac2260f0',
  );

  assert.equal(candidates[0], 'my-shop');
  assert.equal(candidates[1], 'my-shop-d28ba96d');
  assert.equal(candidates[2], 'my-shop-d28ba96d-2');
});

test('catalog hostname extraction accepts one shop label only', () => {
  assert.equal(
    extractCatalogSubdomain('my-shop.pikipos.com', 'pikipos.com'),
    'my-shop',
  );
  assert.equal(
    extractCatalogSubdomain('MY-SHOP.PIKIPOS.COM:443', 'pikipos.com'),
    'my-shop',
  );
  assert.equal(extractCatalogSubdomain('pikipos.com', 'pikipos.com'), null);
  assert.equal(extractCatalogSubdomain('www.pikipos.com', 'pikipos.com'), null);
  assert.equal(
    extractCatalogSubdomain('nested.my-shop.pikipos.com', 'pikipos.com'),
    null,
  );
});

test('catalog storefront URL uses HTTPS and the configured root domain', () => {
  assert.equal(
    buildCatalogStorefrontUrl('pikipos.com', 'my-shop'),
    'https://my-shop.pikipos.com',
  );
});

test('catalog storefront subdomains keep a business name and module type', () => {
  assert.equal(
    buildCatalogStorefrontSubdomain('my-shop', 'services'),
    'my-shop-services',
  );
  assert.deepEqual(
    parseCatalogStorefrontSubdomain('my-shop-restaurant'),
    { businessSubdomain: 'my-shop', storefrontType: 'restaurant' },
  );
});

test('creating a module storefront binds one value per SQL placeholder', async () => {
  let insertCall;
  const target = async (sql, params = []) => {
    if (
      /ALTER TABLE|CREATE TABLE|CREATE UNIQUE INDEX|CREATE INDEX|DO\s+\$\$/i.test(
        sql,
      )
    ) {
      return { rows: [] };
    }
    if (/SELECT id, subdomain, type\s+FROM storefronts/i.test(sql)) {
      return { rows: [] };
    }
    if (/SELECT 1 FROM (businesses|storefronts)/i.test(sql)) {
      return { rows: [] };
    }
    if (/INSERT INTO storefronts/i.test(sql)) {
      insertCall = { sql, params };
      return { rows: [] };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  };

  const storefronts = await ensureBusinessStorefronts(target, {
    businessId: 'business-1',
    businessSubdomain: 'my-shop',
    types: ['retail'],
  });

  assert.equal(insertCall.params.length, 6);
  assert.equal(
    Math.max(
      ...[...insertCall.sql.matchAll(/\$(\d+)/g)].map((match) =>
        Number(match[1]),
      ),
    ),
    6,
  );
  assert.equal(storefronts.length, 1);
  assert.equal(storefronts[0].subdomain, 'my-shop-retail');
});

test('catalog storefront origin accepts secure shop subdomains only', () => {
  assert.equal(
    isCatalogStorefrontOrigin('https://asset.pikipos.com', 'pikipos.com'),
    true,
  );
  assert.equal(
    isCatalogStorefrontOrigin('https://asset.pikipos.com/', 'pikipos.com'),
    true,
  );
  assert.equal(
    isCatalogStorefrontOrigin('http://asset.pikipos.com', 'pikipos.com'),
    false,
  );
  assert.equal(
    isCatalogStorefrontOrigin('http://asset.pikipos.com', 'pikipos.com', {
      allowHttp: true,
    }),
    true,
  );
  assert.equal(
    isCatalogStorefrontOrigin('https://nested.asset.pikipos.com', 'pikipos.com'),
    false,
  );
  assert.equal(
    isCatalogStorefrontOrigin('https://pikipos.com', 'pikipos.com'),
    false,
  );
});

test('catalog subdomain assignment falls back when the preferred name is taken', async () => {
  const business = {
    id: 'd28ba96d-c182-4b76-8fe7-e8d9ac2260f0',
    name: 'My Shop',
    public_subdomain: null,
  };
  const target = async (sql, params = []) => {
    if (/ALTER TABLE|CREATE UNIQUE INDEX|CREATE INDEX|DO\s+\$\$/i.test(sql)) {
      return { rows: [] };
    }
    if (/SELECT name, public_subdomain/i.test(sql)) {
      return { rows: [{ ...business }] };
    }
    if (/UPDATE businesses/i.test(sql)) {
      if (params[1] === 'my-shop') {
        const error = new Error('duplicate');
        error.code = '23505';
        throw error;
      }
      business.public_subdomain = params[1];
      return { rows: [{ public_subdomain: params[1] }] };
    }
    if (/SELECT public_subdomain/i.test(sql)) {
      return { rows: [{ public_subdomain: business.public_subdomain }] };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  };

  const assigned = await ensureBusinessCatalogSubdomain(target, {
    businessId: business.id,
    businessName: business.name,
  });

  assert.equal(assigned, 'my-shop-d28ba96d');
});

test('catalog subdomain lookup ignores deleted businesses', async () => {
  const calls = [];
  const target = {
    query: async (sql, params = []) => {
      calls.push({ sql, params });
      if (/ALTER TABLE|CREATE TABLE|CREATE UNIQUE INDEX|CREATE INDEX|DO\s+\$\$/i.test(sql)) {
        return { rows: [] };
      }
      if (/FROM storefronts/i.test(sql)) {
        return { rows: [] };
      }
      if (/SELECT id/i.test(sql)) {
        return { rows: [{ id: 'business-1' }] };
      }
      throw new Error(`Unexpected SQL in test: ${sql}`);
    },
  };

  const businessId = await findBusinessIdByCatalogSubdomain(target, 'my-shop');

  assert.equal(businessId, 'business-1');
  assert.match(
    calls.find((call) => /SELECT id/i.test(call.sql))?.sql || '',
    /deleted_at IS NULL/i,
  );
});

test('catalog storefront subdomain resolves its business and module', async () => {
  const target = {
    query: async (sql, params = []) => {
      if (/ALTER TABLE|CREATE TABLE|CREATE UNIQUE INDEX|CREATE INDEX|DO\s+\$\$/i.test(sql)) {
        return { rows: [] };
      }
      if (/FROM storefronts/i.test(sql) && params[0] === 'my-shop-services') {
        return {
          rows: [
            {
              id: 'sf-1',
              business_id: 'business-1',
              type: 'services',
              title: 'Services',
            },
          ],
        };
      }
      if (/FROM storefronts/i.test(sql)) {
        return { rows: [] };
      }
      if (/SELECT id/i.test(sql) && params[0] === 'my-shop-services') {
        return { rows: [] };
      }
      if (/SELECT id/i.test(sql) && params[0] === 'my-shop') {
        return { rows: [{ id: 'business-1' }] };
      }
      throw new Error(`Unexpected SQL in test: ${sql}`);
    },
  };

  const storefront = await findBusinessCatalogStorefrontBySubdomain(
    target,
    'my-shop-services',
  );

  assert.deepEqual(storefront, {
    businessId: 'business-1',
    storefrontType: 'services',
    storefrontId: 'sf-1',
    title: 'Services',
  });
});
