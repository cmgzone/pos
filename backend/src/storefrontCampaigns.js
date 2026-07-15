const crypto = require('crypto');

const CAMPAIGN_STATUSES = new Set(['draft', 'published', 'archived']);
const STOREFRONT_TYPES = new Set(['retail', 'services', 'restaurant']);

async function ensureStorefrontCampaignSchema(target) {
  await run(target, `
    CREATE TABLE IF NOT EXISTS storefront_campaigns (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      storefront_type text NOT NULL DEFAULT 'retail',
      name text NOT NULL,
      slug text NOT NULL,
      eyebrow text,
      title text NOT NULL,
      description text,
      badge_label text,
      button_label text NOT NULL DEFAULT 'Shop the campaign',
      hero_image_url text,
      product_ids_json jsonb NOT NULL DEFAULT '[]'::jsonb,
      highlights_json jsonb NOT NULL DEFAULT '[]'::jsonb,
      status text NOT NULL DEFAULT 'draft',
      starts_at timestamptz,
      ends_at timestamptz,
      created_by text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      published_at timestamptz,
      deleted_at timestamptz
    )
  `);
  await run(target, `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_storefront_campaigns_slug
      ON storefront_campaigns (business_id, branch_id, storefront_type, LOWER(slug))
      WHERE deleted_at IS NULL
  `);
  await run(target, `
    CREATE INDEX IF NOT EXISTS idx_storefront_campaigns_scope
      ON storefront_campaigns (business_id, branch_id, storefront_type, status, updated_at DESC)
      WHERE deleted_at IS NULL
  `);
}

async function listStorefrontCampaigns(
  target,
  businessId,
  { branchId = 'main_branch', storefrontType = 'retail' } = {},
) {
  await ensureStorefrontCampaignSchema(target);
  const result = await run(
    target,
    `SELECT *
     FROM storefront_campaigns
     WHERE business_id = $1
       AND branch_id = $2
       AND storefront_type = $3
       AND deleted_at IS NULL
     ORDER BY CASE status WHEN 'published' THEN 0 WHEN 'draft' THEN 1 ELSE 2 END,
              updated_at DESC`,
    [businessId, normalizeBranchId(branchId), normalizeStorefrontType(storefrontType)],
  );
  return result.rows.map(normalizeCampaignRow);
}

async function getStorefrontCampaign(target, businessId, campaignId) {
  await ensureStorefrontCampaignSchema(target);
  const result = await run(
    target,
    `SELECT * FROM storefront_campaigns
     WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL
     LIMIT 1`,
    [campaignId, businessId],
  );
  return result.rows[0] ? normalizeCampaignRow(result.rows[0]) : null;
}

async function loadPublishedStorefrontCampaign(
  target,
  businessId,
  { branchId = 'main_branch', storefrontType = 'retail', slug } = {},
) {
  await ensureStorefrontCampaignSchema(target);
  const cleanSlug = normalizeSlug(slug);
  if (!cleanSlug) return null;
  const result = await run(
    target,
    `SELECT * FROM storefront_campaigns
     WHERE business_id = $1
       AND branch_id = $2
       AND storefront_type = $3
       AND LOWER(slug) = LOWER($4)
       AND status = 'published'
       AND deleted_at IS NULL
       AND (starts_at IS NULL OR starts_at <= NOW())
       AND (ends_at IS NULL OR ends_at >= NOW())
     LIMIT 1`,
    [
      businessId,
      normalizeBranchId(branchId),
      normalizeStorefrontType(storefrontType),
      cleanSlug,
    ],
  );
  return result.rows[0] ? normalizeCampaignRow(result.rows[0]) : null;
}

async function createStorefrontCampaign(
  target,
  businessId,
  input,
  { branchId = 'main_branch', storefrontType = 'retail', createdBy = null } = {},
) {
  await ensureStorefrontCampaignSchema(target);
  const normalized = normalizeCampaignInput(input, { branchId, storefrontType });
  const id = crypto.randomUUID();
  const result = await run(
    target,
    `INSERT INTO storefront_campaigns (
       id, business_id, branch_id, storefront_type, name, slug, eyebrow,
       title, description, badge_label, button_label, hero_image_url,
       product_ids_json, highlights_json, status, starts_at, ends_at,
       created_by, created_at, updated_at
     ) VALUES (
       $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
       $13::jsonb, $14::jsonb, 'draft', $15, $16, $17, NOW(), NOW()
     )
     RETURNING *`,
    [
      id,
      businessId,
      normalized.branchId,
      normalized.storefrontType,
      normalized.name,
      normalized.slug,
      normalized.eyebrow,
      normalized.title,
      normalized.description,
      normalized.badgeLabel,
      normalized.buttonLabel,
      normalized.heroImageUrl,
      JSON.stringify(normalized.productIds),
      JSON.stringify(normalized.highlights),
      normalized.startsAt,
      normalized.endsAt,
      createdBy,
    ],
  );
  return normalizeCampaignRow(result.rows[0]);
}

async function updateStorefrontCampaign(target, businessId, campaignId, input) {
  const existing = await getStorefrontCampaign(target, businessId, campaignId);
  if (!existing) throw createError(404, 'Campaign was not found.');
  const normalized = normalizeCampaignInput(input, { existing });
  const result = await run(
    target,
    `UPDATE storefront_campaigns
     SET name = $3,
         slug = $4,
         eyebrow = $5,
         title = $6,
         description = $7,
         badge_label = $8,
         button_label = $9,
         hero_image_url = $10,
         product_ids_json = $11::jsonb,
         highlights_json = $12::jsonb,
         starts_at = $13,
         ends_at = $14,
         updated_at = NOW()
     WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL
     RETURNING *`,
    [
      campaignId,
      businessId,
      normalized.name,
      normalized.slug,
      normalized.eyebrow,
      normalized.title,
      normalized.description,
      normalized.badgeLabel,
      normalized.buttonLabel,
      normalized.heroImageUrl,
      JSON.stringify(normalized.productIds),
      JSON.stringify(normalized.highlights),
      normalized.startsAt,
      normalized.endsAt,
    ],
  );
  return normalizeCampaignRow(result.rows[0]);
}

async function publishStorefrontCampaign(target, businessId, campaignId) {
  const existing = await getStorefrontCampaign(target, businessId, campaignId);
  if (!existing) throw createError(404, 'Campaign was not found.');
  if (existing.productIds.length === 0) {
    throw createError(400, 'Add at least one product before publishing this campaign.');
  }
  const isServices = existing.storefrontType === 'services';
  const selectedIds = isServices
    ? existing.productIds.map((id) => String(id).replace(/^service:/, ''))
    : existing.productIds;
  const productResult = await run(
    target,
    isServices
      ? `SELECT COUNT(*)::int AS count
         FROM services
         WHERE business_id = $1
           AND COALESCE(branch_id, 'main_branch') = $2
           AND id = ANY($3::text[])
           AND deleted_at IS NULL
           AND COALESCE(NULLIF(LOWER(is_active::text), ''), '1') NOT IN ('0', 'false', 'no', 'off')`
      : `SELECT COUNT(*)::int AS count
         FROM products
         WHERE business_id = $1
           AND COALESCE(branch_id, 'main_branch') = $2
           AND id = ANY($3::text[])
           AND deleted_at IS NULL
           AND COALESCE(show_online, 1) <> 0`,
    [businessId, existing.branchId, selectedIds],
  );
  if (Number(productResult.rows[0]?.count || 0) !== existing.productIds.length) {
    throw createError(
      400,
      'One or more campaign items are no longer published online. Review the selection first.',
    );
  }
  const result = await run(
    target,
    `UPDATE storefront_campaigns
     SET status = 'published', published_at = NOW(), updated_at = NOW()
     WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL
     RETURNING *`,
    [campaignId, businessId],
  );
  return normalizeCampaignRow(result.rows[0]);
}

async function unpublishStorefrontCampaign(target, businessId, campaignId) {
  const result = await run(
    target,
    `UPDATE storefront_campaigns
     SET status = 'draft', published_at = NULL, updated_at = NOW()
     WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL
     RETURNING *`,
    [campaignId, businessId],
  );
  if (!result.rows[0]) throw createError(404, 'Campaign was not found.');
  return normalizeCampaignRow(result.rows[0]);
}

async function deleteStorefrontCampaign(target, businessId, campaignId) {
  const result = await run(
    target,
    `UPDATE storefront_campaigns
     SET deleted_at = NOW(), updated_at = NOW()
     WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL
     RETURNING *`,
    [campaignId, businessId],
  );
  if (!result.rows[0]) throw createError(404, 'Campaign was not found.');
  return normalizeCampaignRow(result.rows[0]);
}

function normalizeCampaignInput(input = {}, options = {}) {
  const existing = options.existing || null;
  const name = limitText(input.name ?? existing?.name, 80);
  const title = limitText(input.title ?? existing?.title ?? name, 120);
  if (!name) throw createError(400, 'Campaign name is required.');
  if (!title) throw createError(400, 'Campaign headline is required.');
  const slug = normalizeSlug(input.slug ?? existing?.slug ?? name);
  if (!slug) throw createError(400, 'Campaign URL is invalid.');
  const startsAt = normalizeDate(input.startsAt ?? input.starts_at ?? existing?.startsAt);
  const endsAt = normalizeDate(input.endsAt ?? input.ends_at ?? existing?.endsAt);
  if (startsAt && endsAt && new Date(endsAt) <= new Date(startsAt)) {
    throw createError(400, 'Campaign end time must be after its start time.');
  }
  return {
    branchId: normalizeBranchId(input.branchId ?? input.branch_id ?? existing?.branchId ?? options.branchId),
    storefrontType: normalizeStorefrontType(
      input.storefrontType ?? input.storefront_type ?? existing?.storefrontType ?? options.storefrontType,
    ),
    name,
    slug,
    eyebrow: optionalText(input.eyebrow ?? existing?.eyebrow, 50),
    title,
    description: optionalText(input.description ?? existing?.description, 500),
    badgeLabel: optionalText(input.badgeLabel ?? input.badge_label ?? existing?.badgeLabel, 40),
    buttonLabel:
      limitText(input.buttonLabel ?? input.button_label ?? existing?.buttonLabel, 40) ||
      'Shop the campaign',
    heroImageUrl: normalizeUrl(
      input.heroImageUrl ?? input.hero_image_url ?? existing?.heroImageUrl,
    ),
    productIds: normalizeIdList(
      input.productIds ?? input.product_ids ?? existing?.productIds,
      24,
    ),
    highlights: normalizeHighlights(input.highlights ?? existing?.highlights),
    startsAt,
    endsAt,
  };
}

function normalizeCampaignRow(row) {
  return {
    id: row.id,
    branchId: row.branch_id,
    storefrontType: normalizeStorefrontType(row.storefront_type),
    name: row.name,
    slug: row.slug,
    eyebrow: row.eyebrow,
    title: row.title,
    description: row.description,
    badgeLabel: row.badge_label,
    buttonLabel: row.button_label,
    heroImageUrl: row.hero_image_url,
    productIds: normalizeIdList(row.product_ids_json, 24),
    highlights: normalizeHighlights(row.highlights_json),
    status: CAMPAIGN_STATUSES.has(row.status) ? row.status : 'draft',
    isPublished: row.status === 'published',
    startsAt: toIso(row.starts_at),
    endsAt: toIso(row.ends_at),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
    publishedAt: toIso(row.published_at),
  };
}

function normalizeHighlights(value) {
  const items = Array.isArray(value) ? value : [];
  return items
    .slice(0, 4)
    .map((item) => limitText(item, 80))
    .filter(Boolean);
}

function normalizeIdList(value, maximum) {
  const values = Array.isArray(value) ? value : [];
  return [...new Set(values.map((item) => limitText(item, 120)).filter(Boolean))].slice(
    0,
    maximum,
  );
}

function normalizeStorefrontType(value) {
  const normalized = String(value || '').trim().toLowerCase();
  return STOREFRONT_TYPES.has(normalized) ? normalized : 'retail';
}

function normalizeBranchId(value) {
  return limitText(value, 120) || 'main_branch';
}

function normalizeSlug(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-')
    .slice(0, 72)
    .replace(/-+$/g, '');
}

function normalizeUrl(value) {
  const text = optionalText(value, 1000);
  if (!text) return null;
  try {
    const parsed = new URL(text);
    return parsed.protocol === 'https:' ? parsed.toString() : null;
  } catch (_) {
    return null;
  }
}

function normalizeDate(value) {
  if (value == null || String(value).trim() === '') return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.valueOf())) throw createError(400, 'Campaign date is invalid.');
  return parsed.toISOString();
}

function optionalText(value, maxLength) {
  return limitText(value, maxLength) || null;
}

function limitText(value, maxLength) {
  const text = String(value ?? '').trim();
  return text ? text.slice(0, maxLength) : '';
}

function toIso(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date.toISOString();
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
  createStorefrontCampaign,
  deleteStorefrontCampaign,
  ensureStorefrontCampaignSchema,
  getStorefrontCampaign,
  listStorefrontCampaigns,
  loadPublishedStorefrontCampaign,
  normalizeCampaignInput,
  normalizeSlug,
  publishStorefrontCampaign,
  unpublishStorefrontCampaign,
  updateStorefrontCampaign,
};
