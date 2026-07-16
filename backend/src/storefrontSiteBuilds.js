const crypto = require('crypto');

const { compileStorefrontSitePackage } = require('./storefrontSiteCompiler');

const SITE_BUILD_STATUSES = new Set(['draft', 'published', 'archived']);
const STOREFRONT_TYPES = new Set(['retail', 'services', 'restaurant']);

async function ensureStorefrontSiteBuildSchema(target) {
  await run(target, `
    CREATE TABLE IF NOT EXISTS storefront_site_builds (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      storefront_type text NOT NULL DEFAULT 'retail',
      version integer NOT NULL,
      name text NOT NULL,
      summary text,
      instruction text,
      source_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      compiled_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      compiler_version text NOT NULL,
      code_hash text NOT NULL,
      status text NOT NULL DEFAULT 'draft',
      source text NOT NULL DEFAULT 'ai',
      parent_build_id text,
      created_by text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      published_at timestamptz,
      deleted_at timestamptz
    )
  `);
  await run(target, `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_storefront_site_build_version
      ON storefront_site_builds (business_id, branch_id, storefront_type, version)
      WHERE deleted_at IS NULL
  `);
  await run(target, `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_storefront_site_build_published
      ON storefront_site_builds (business_id, branch_id, storefront_type)
      WHERE status = 'published' AND deleted_at IS NULL
  `);
  await run(target, `
    CREATE INDEX IF NOT EXISTS idx_storefront_site_build_scope
      ON storefront_site_builds (business_id, branch_id, storefront_type, updated_at DESC)
      WHERE deleted_at IS NULL
  `);
}

async function listStorefrontSiteBuilds(target, businessId, options = {}) {
  await ensureStorefrontSiteBuildSchema(target);
  const scope = normalizeScope(options);
  const result = await run(target, `
    SELECT id, business_id, branch_id, storefront_type, version, name,
           summary, instruction,
           compiled_json - 'html' - 'pageHtml' - 'css' AS compiled_json,
           compiler_version, code_hash, status, source, parent_build_id,
           created_by, created_at, updated_at, published_at
    FROM storefront_site_builds
    WHERE business_id=$1 AND branch_id=$2 AND storefront_type=$3
      AND deleted_at IS NULL
    ORDER BY version DESC
    LIMIT 50
  `, [businessId, scope.branchId, scope.storefrontType]);
  return result.rows.map((row) =>
    storefrontSiteBuildSummary(normalizeStorefrontSiteBuildRow(row)),
  );
}

async function getStorefrontSiteBuild(target, businessId, buildId) {
  await ensureStorefrontSiteBuildSchema(target);
  const result = await run(target, `
    SELECT * FROM storefront_site_builds
    WHERE business_id=$1 AND id=$2 AND deleted_at IS NULL
    LIMIT 1
  `, [businessId, buildId]);
  return result.rows[0] ? normalizeStorefrontSiteBuildRow(result.rows[0]) : null;
}

async function createStorefrontSiteBuild(target, businessId, input = {}, options = {}) {
  await ensureStorefrontSiteBuildSchema(target);
  const scope = normalizeScope(input);
  const compiled = compileStorefrontSitePackage(input.package ?? input.compiled ?? input);
  await run(
    target,
    'SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))',
    [String(businessId), `${scope.branchId}:${scope.storefrontType}`],
  );
  const versionResult = await run(target, `
    SELECT COALESCE(MAX(version), 0) + 1 AS next_version
    FROM storefront_site_builds
    WHERE business_id=$1 AND branch_id=$2 AND storefront_type=$3
  `, [businessId, scope.branchId, scope.storefrontType]);
  const version = Number(versionResult.rows[0]?.next_version) || 1;
  const result = await run(target, `
    INSERT INTO storefront_site_builds (
      id, business_id, branch_id, storefront_type, version, name, summary,
      instruction, source_json, compiled_json, compiler_version, code_hash,
      status, source, parent_build_id, created_by
    ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,$11,$12,'draft',$13,$14,$15)
    RETURNING *
  `, [
    crypto.randomUUID(), businessId, scope.branchId, scope.storefrontType,
    version, compiled.name, compiled.summary, limitText(input.instruction, 1600),
    JSON.stringify({ html: compiled.html, pageHtml: compiled.pageHtml, css: compiled.css }),
    JSON.stringify(compiled), compiled.compilerVersion, compiled.codeHash,
    limitText(input.source, 40) || 'ai', input.parentBuildId || null,
    options.createdBy || null,
  ]);
  return normalizeStorefrontSiteBuildRow(result.rows[0]);
}

async function publishStorefrontSiteBuild(target, businessId, buildId) {
  const existing = await getStorefrontSiteBuild(target, businessId, buildId);
  if (!existing) throw createError(404, 'Generated site build was not found.');
  const verified = compileStorefrontSitePackage(existing);
  if (
    verified.codeHash !== existing.codeHash ||
    verified.compilerVersion !== existing.compilerVersion
  ) {
    throw createError(
      409,
      'This generated site build no longer passes the current compiler. Create a new draft before publishing.',
    );
  }
  const result = await run(target, `
    WITH archived AS (
      UPDATE storefront_site_builds
      SET status='archived', updated_at=NOW()
      WHERE business_id=$1 AND branch_id=$2 AND storefront_type=$3
        AND status='published' AND id<>$4 AND deleted_at IS NULL
      RETURNING id
    )
    UPDATE storefront_site_builds
    SET status='published', published_at=NOW(), updated_at=NOW()
    WHERE business_id=$1 AND id=$4 AND deleted_at IS NULL
    RETURNING *
  `, [businessId, existing.branchId, existing.storefrontType, buildId]);
  if (!result.rows[0]) throw createError(404, 'Generated site build was not found.');
  return normalizeStorefrontSiteBuildRow(result.rows[0]);
}

async function deleteStorefrontSiteBuild(target, businessId, buildId) {
  const result = await run(target, `
    UPDATE storefront_site_builds
    SET deleted_at=NOW(), updated_at=NOW()
    WHERE business_id=$1 AND id=$2 AND status<>'published' AND deleted_at IS NULL
    RETURNING *
  `, [businessId, buildId]);
  if (!result.rows[0]) {
    throw createError(409, 'Only an unpublished generated-site build can be deleted.');
  }
  return normalizeStorefrontSiteBuildRow(result.rows[0]);
}

async function loadPublishedStorefrontSiteBuild(target, businessId, options = {}) {
  await ensureStorefrontSiteBuildSchema(target);
  const scope = normalizeScope(options);
  const result = await run(target, `
    SELECT * FROM storefront_site_builds
    WHERE business_id=$1 AND branch_id=$2 AND storefront_type=$3
      AND status='published' AND deleted_at IS NULL
    LIMIT 1
  `, [businessId, scope.branchId, scope.storefrontType]);
  return result.rows[0] ? normalizeStorefrontSiteBuildRow(result.rows[0]) : null;
}

function normalizeStorefrontSiteBuildRow(row) {
  const compiled = parseJson(row.compiled_json ?? row.compiled, {});
  const storefrontType = normalizeEnum(
    row.storefront_type ?? row.storefrontType,
    STOREFRONT_TYPES,
    'retail',
  );
  return {
    id: String(row.id),
    branchId: row.branch_id ?? row.branchId ?? 'main_branch',
    storefrontType,
    version: Number(row.version) || 1,
    name: row.name || compiled.name || 'Piki generated storefront',
    summary: row.summary || compiled.summary || '',
    instruction: row.instruction || null,
    html: String(compiled.html || ''),
    pageHtml: String(compiled.pageHtml || ''),
    css: String(compiled.css || ''),
    compilerVersion: row.compiler_version ?? compiled.compilerVersion,
    codeHash: row.code_hash ?? compiled.codeHash,
    slots: Array.isArray(compiled.slots) ? compiled.slots.map(String) : [],
    pageSlots: Array.isArray(compiled.pageSlots)
      ? compiled.pageSlots.map(String)
      : [],
    security: objectValue(compiled.security),
    status: SITE_BUILD_STATUSES.has(row.status) ? row.status : 'draft',
    source: row.source || 'ai',
    parentBuildId: row.parent_build_id ?? row.parentBuildId ?? null,
    createdBy: row.created_by ?? row.createdBy ?? null,
    createdAt: toIsoString(row.created_at ?? row.createdAt),
    updatedAt: toIsoString(row.updated_at ?? row.updatedAt),
    publishedAt: toIsoString(row.published_at ?? row.publishedAt),
  };
}

function publicStorefrontSiteBuild(build) {
  if (!build) return null;
  return {
    id: build.id,
    version: build.version,
    name: build.name,
    summary: build.summary,
    html: build.html,
    pageHtml: build.pageHtml,
    css: build.css,
    compilerVersion: build.compilerVersion,
    codeHash: build.codeHash,
    slots: build.slots,
    pageSlots: build.pageSlots,
    security: build.security,
    status: build.status,
    updatedAt: build.updatedAt,
  };
}

function storefrontSiteBuildSummary(build) {
  if (!build) return null;
  const { html: _html, pageHtml: _pageHtml, css: _css, ...summary } = build;
  return summary;
}

function normalizeScope(value = {}) {
  return {
    branchId: limitText(value.branchId ?? value.branch_id, 120) || 'main_branch',
    storefrontType: normalizeEnum(
      value.storefrontType ?? value.storefront_type,
      STOREFRONT_TYPES,
      'retail',
    ),
  };
}

function normalizeEnum(value, allowed, fallback) {
  const clean = String(value || '').trim().toLowerCase();
  return allowed.has(clean) ? clean : fallback;
}

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try { return JSON.parse(String(value)); } catch (_) { return fallback; }
}

function objectValue(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
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
  SITE_BUILD_STATUSES,
  createStorefrontSiteBuild,
  deleteStorefrontSiteBuild,
  ensureStorefrontSiteBuildSchema,
  getStorefrontSiteBuild,
  listStorefrontSiteBuilds,
  loadPublishedStorefrontSiteBuild,
  normalizeStorefrontSiteBuildRow,
  publicStorefrontSiteBuild,
  publishStorefrontSiteBuild,
  storefrontSiteBuildSummary,
};
