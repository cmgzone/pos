const crypto = require('crypto');

const { normalizeStorefrontThemeSections } = require('./storefrontThemes');

const PAGE_STATUSES = new Set(['draft', 'published', 'archived']);
const PAGE_TYPES = new Set(['custom', 'about', 'faq', 'contact', 'policy', 'landing']);
const STOREFRONT_TYPES = new Set(['retail', 'services', 'restaurant']);

async function ensureStorefrontPageSchema(target) {
  await run(target, `
    CREATE TABLE IF NOT EXISTS storefront_pages (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      storefront_type text NOT NULL DEFAULT 'retail',
      page_type text NOT NULL DEFAULT 'custom',
      title text NOT NULL,
      slug text NOT NULL,
      navigation_label text,
      show_in_navigation boolean NOT NULL DEFAULT true,
      seo_title text,
      seo_description text,
      sections_json jsonb NOT NULL DEFAULT '[]'::jsonb,
      status text NOT NULL DEFAULT 'draft',
      source text NOT NULL DEFAULT 'manual',
      created_by text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      published_at timestamptz,
      deleted_at timestamptz
    )
  `);
  await run(target, `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_storefront_pages_slug
      ON storefront_pages (business_id, branch_id, storefront_type, LOWER(slug))
      WHERE deleted_at IS NULL
  `);
  await run(target, `
    CREATE INDEX IF NOT EXISTS idx_storefront_pages_scope
      ON storefront_pages (business_id, branch_id, storefront_type, status, updated_at DESC)
      WHERE deleted_at IS NULL
  `);
}

function normalizeStorefrontPageInput(input = {}, existing = null) {
  const raw = objectValue(input);
  const title = limitText(raw.title ?? existing?.title, 100);
  if (!title) throw createError(400, 'Page title is required.');
  const pageType = normalizeEnum(raw.pageType ?? raw.page_type ?? existing?.pageType, PAGE_TYPES, 'custom');
  const slug = normalizePageSlug(raw.slug ?? existing?.slug ?? title);
  if (!slug) throw createError(400, 'Page URL is required.');
  const storefrontType = normalizeEnum(
    raw.storefrontType ?? raw.storefront_type ?? existing?.storefrontType,
    STOREFRONT_TYPES,
    'retail',
  );
  const requestedSections = Array.isArray(raw.sections)
    ? raw.sections
    : existing?.sections || defaultPageSections(pageType);
  const sections = normalizeStorefrontThemeSections(
    requestedSections,
    existing?.sections || defaultPageSections(pageType),
    { storefrontType, requireCatalog: false, maxSections: 20 },
  );
  if (!sections.length) {
    throw createError(400, 'Add at least one section to the page.');
  }
  return {
    branchId: limitText(raw.branchId ?? raw.branch_id ?? existing?.branchId, 120) || 'main_branch',
    storefrontType,
    pageType,
    title,
    slug,
    navigationLabel:
      limitText(raw.navigationLabel ?? raw.navigation_label ?? existing?.navigationLabel ?? title, 40) || title,
    showInNavigation: booleanValue(
      raw.showInNavigation ?? raw.show_in_navigation,
      existing?.showInNavigation ?? true,
    ),
    seoTitle: limitText(raw.seoTitle ?? raw.seo_title ?? existing?.seoTitle ?? title, 70) || title,
    seoDescription:
      limitText(raw.seoDescription ?? raw.seo_description ?? existing?.seoDescription, 180) || '',
    sections,
    source: limitText(raw.source ?? existing?.source, 40) || 'manual',
  };
}

function defaultPageSections(pageType = 'custom') {
  const hero = {
    id: 'page-hero',
    type: 'hero',
    enabled: true,
    style: 'surface',
    eyebrow: '',
    title: pageType === 'faq' ? 'Frequently asked questions' : pageType === 'contact' ? 'Contact us' : 'A page for your customers',
    body: pageType === 'policy' ? 'Clear information customers can refer to.' : 'Add useful, truthful information about your business.',
    buttonAction: 'none',
    alignment: 'left',
    showImage: pageType === 'about' || pageType === 'landing',
  };
  if (pageType === 'faq') {
    return [
      hero,
      { id: 'questions', type: 'faq', enabled: true, style: 'default', title: 'Common questions', body: '', items: [] },
      { id: 'faq-contact', type: 'contact', enabled: true, style: 'surface', title: 'Still need help?', body: 'Contact the team and we will be happy to help.', buttonLabel: 'Chat on WhatsApp', buttonAction: 'whatsapp', alignment: 'center' },
    ];
  }
  if (pageType === 'contact') {
    return [hero, { id: 'contact', type: 'contact', enabled: true, style: 'accent', title: 'Talk to the team', body: 'Send us a message and we will respond as soon as we can.', buttonLabel: 'Chat on WhatsApp', buttonAction: 'whatsapp', alignment: 'center' }];
  }
  if (pageType === 'policy') {
    return [hero, { id: 'policy-content', type: 'richText', enabled: true, style: 'default', title: 'Policy details', body: '', content: 'Replace this text with the policy your customers should read.', alignment: 'left' }];
  }
  if (pageType === 'about') {
    return [hero, { id: 'our-story', type: 'story', enabled: true, style: 'default', eyebrow: 'Our story', title: 'Built around our customers', body: 'Share the real story behind the business.', alignment: 'left', showImage: true }, { id: 'about-contact', type: 'contact', enabled: true, style: 'surface', title: 'Talk to us', body: 'We are here when you need help.', buttonLabel: 'Chat on WhatsApp', buttonAction: 'whatsapp', alignment: 'center' }];
  }
  if (pageType === 'landing') {
    return [hero, { id: 'landing-featured', type: 'featuredProducts', enabled: true, style: 'default', eyebrow: 'Selected for you', title: 'Featured products', body: '', source: 'featured', limit: 4 }, { id: 'landing-contact', type: 'contact', enabled: true, style: 'contrast', title: 'Ready to order?', body: 'Browse the store or talk to the team.', buttonLabel: 'Shop now', buttonAction: 'catalog', alignment: 'center' }];
  }
  return [hero, { id: 'page-content', type: 'richText', enabled: true, style: 'default', title: 'Page heading', body: '', content: 'Add your page content here.', alignment: 'left' }];
}

async function listStorefrontPages(target, businessId, options = {}) {
  await ensureStorefrontPageSchema(target);
  const branchId = limitText(options.branchId, 120) || 'main_branch';
  const storefrontType = normalizeEnum(options.storefrontType, STOREFRONT_TYPES, 'retail');
  const result = await run(target, `
    SELECT * FROM storefront_pages
    WHERE business_id = $1 AND branch_id = $2 AND storefront_type = $3
      AND deleted_at IS NULL
    ORDER BY CASE status WHEN 'published' THEN 0 WHEN 'draft' THEN 1 ELSE 2 END,
             updated_at DESC
  `, [businessId, branchId, storefrontType]);
  return result.rows.map(normalizeStorefrontPageRow);
}

async function getStorefrontPage(target, businessId, pageId) {
  await ensureStorefrontPageSchema(target);
  const result = await run(target, 'SELECT * FROM storefront_pages WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL LIMIT 1', [businessId, pageId]);
  return result.rows[0] ? normalizeStorefrontPageRow(result.rows[0]) : null;
}

async function createStorefrontPage(target, businessId, input, options = {}) {
  await ensureStorefrontPageSchema(target);
  const page = normalizeStorefrontPageInput(input);
  const result = await run(target, `
    INSERT INTO storefront_pages (
      id, business_id, branch_id, storefront_type, page_type, title, slug,
      navigation_label, show_in_navigation, seo_title, seo_description,
      sections_json, status, source, created_by
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,'draft',$13,$14)
    RETURNING *
  `, [
    crypto.randomUUID(), businessId, page.branchId, page.storefrontType,
    page.pageType, page.title, page.slug, page.navigationLabel,
    page.showInNavigation, page.seoTitle, page.seoDescription,
    JSON.stringify(page.sections), page.source, options.createdBy || null,
  ]);
  return normalizeStorefrontPageRow(result.rows[0]);
}

async function updateStorefrontPage(target, businessId, pageId, input) {
  const existing = await getStorefrontPage(target, businessId, pageId);
  if (!existing) throw createError(404, 'Storefront page was not found.');
  const page = normalizeStorefrontPageInput(input, existing);
  const result = await run(target, `
    UPDATE storefront_pages SET
      page_type=$3, title=$4, slug=$5, navigation_label=$6,
      show_in_navigation=$7, seo_title=$8, seo_description=$9,
      sections_json=$10::jsonb, source=$11, updated_at=NOW()
    WHERE business_id=$1 AND id=$2 AND deleted_at IS NULL
    RETURNING *
  `, [businessId, pageId, page.pageType, page.title, page.slug,
    page.navigationLabel, page.showInNavigation, page.seoTitle,
    page.seoDescription, JSON.stringify(page.sections), page.source]);
  return normalizeStorefrontPageRow(result.rows[0]);
}

async function publishStorefrontPage(target, businessId, pageId) {
  const result = await run(target, `
    UPDATE storefront_pages SET status='published', published_at=NOW(), updated_at=NOW()
    WHERE business_id=$1 AND id=$2 AND deleted_at IS NULL RETURNING *
  `, [businessId, pageId]);
  if (!result.rows[0]) throw createError(404, 'Storefront page was not found.');
  return normalizeStorefrontPageRow(result.rows[0]);
}

async function unpublishStorefrontPage(target, businessId, pageId) {
  const result = await run(target, `
    UPDATE storefront_pages SET status='draft', updated_at=NOW()
    WHERE business_id=$1 AND id=$2 AND deleted_at IS NULL RETURNING *
  `, [businessId, pageId]);
  if (!result.rows[0]) throw createError(404, 'Storefront page was not found.');
  return normalizeStorefrontPageRow(result.rows[0]);
}

async function deleteStorefrontPage(target, businessId, pageId) {
  const result = await run(target, `
    UPDATE storefront_pages SET deleted_at=NOW(), updated_at=NOW()
    WHERE business_id=$1 AND id=$2 AND deleted_at IS NULL RETURNING *
  `, [businessId, pageId]);
  if (!result.rows[0]) throw createError(404, 'Storefront page was not found.');
  return normalizeStorefrontPageRow(result.rows[0]);
}

async function listPublishedStorefrontPages(target, businessId, options = {}) {
  const pages = await listStorefrontPages(target, businessId, options);
  return pages.filter((page) => page.status === 'published');
}

async function loadPublishedStorefrontPage(target, businessId, options = {}) {
  await ensureStorefrontPageSchema(target);
  const branchId = limitText(options.branchId, 120) || 'main_branch';
  const storefrontType = normalizeEnum(options.storefrontType, STOREFRONT_TYPES, 'retail');
  const slug = normalizePageSlug(options.slug);
  if (!slug) return null;
  const result = await run(target, `
    SELECT * FROM storefront_pages
    WHERE business_id=$1 AND branch_id=$2 AND storefront_type=$3
      AND LOWER(slug)=LOWER($4) AND status='published' AND deleted_at IS NULL
    LIMIT 1
  `, [businessId, branchId, storefrontType, slug]);
  return result.rows[0] ? normalizeStorefrontPageRow(result.rows[0]) : null;
}

function normalizeStorefrontPageRow(row) {
  if (!row) return null;
  const storefrontType = normalizeEnum(row.storefront_type ?? row.storefrontType, STOREFRONT_TYPES, 'retail');
  return {
    id: String(row.id),
    branchId: row.branch_id ?? row.branchId ?? 'main_branch',
    storefrontType,
    pageType: normalizeEnum(row.page_type ?? row.pageType, PAGE_TYPES, 'custom'),
    title: row.title || 'Untitled page',
    slug: normalizePageSlug(row.slug),
    navigationLabel: row.navigation_label ?? row.navigationLabel ?? row.title,
    showInNavigation: row.show_in_navigation ?? row.showInNavigation ?? true,
    seoTitle: row.seo_title ?? row.seoTitle ?? row.title,
    seoDescription: row.seo_description ?? row.seoDescription ?? '',
    sections: normalizeStorefrontThemeSections(parseJson(row.sections_json ?? row.sections, []), [], {
      storefrontType,
      requireCatalog: false,
      maxSections: 20,
    }),
    status: PAGE_STATUSES.has(row.status) ? row.status : 'draft',
    source: row.source || 'manual',
    createdBy: row.created_by ?? row.createdBy ?? null,
    createdAt: toIsoString(row.created_at ?? row.createdAt),
    updatedAt: toIsoString(row.updated_at ?? row.updatedAt),
    publishedAt: toIsoString(row.published_at ?? row.publishedAt),
  };
}

function normalizePageSlug(value) {
  return String(value || '')
    .trim()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

function normalizeEnum(value, allowed, fallback) {
  const clean = String(value || '').trim();
  return allowed.has(clean) ? clean : fallback;
}

function booleanValue(value, fallback) {
  if (value == null) return Boolean(fallback);
  if (typeof value === 'boolean') return value;
  return !['false', '0', 'no', 'off'].includes(String(value).trim().toLowerCase());
}

function objectValue(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try { return JSON.parse(String(value)); } catch (_) { return fallback; }
}

function limitText(value, maxLength) {
  const clean = String(value ?? '').trim();
  return clean ? clean.slice(0, maxLength) : null;
}

function toIsoString(value) {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function run(target, sql, params = []) {
  if (typeof target === 'function') return target(sql, params);
  return target.query(sql, params);
}

module.exports = {
  PAGE_TYPES,
  createStorefrontPage,
  defaultPageSections,
  deleteStorefrontPage,
  ensureStorefrontPageSchema,
  getStorefrontPage,
  listPublishedStorefrontPages,
  listStorefrontPages,
  loadPublishedStorefrontPage,
  normalizePageSlug,
  normalizeStorefrontPageInput,
  normalizeStorefrontPageRow,
  publishStorefrontPage,
  unpublishStorefrontPage,
  updateStorefrontPage,
};
