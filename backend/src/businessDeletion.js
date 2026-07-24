const { ensureCatalogSubdomainSchema } = require('./catalogSubdomains');

async function deleteBusinessAccount(
  target,
  { businessId, deletedByUserId, now = new Date() } = {},
) {
  const cleanBusinessId = normalizeText(businessId);
  if (!cleanBusinessId) {
    throw new Error('businessId is required');
  }
  const deletedAt = normalizeIsoTimestamp(now);

  await ensureCatalogSubdomainSchema(target);
  const currentResult = await runQuery(
    target,
    `SELECT id, name, public_subdomain, deleted_at, subdomain_released_at
     FROM businesses
     WHERE id = $1
     LIMIT 1`,
    [cleanBusinessId],
  );
  const current = currentResult.rows[0];
  if (!current) {
    return null;
  }

  const releasedSubdomain = normalizeText(current.public_subdomain);
  if (current.deleted_at) {
    return {
      businessId: current.id,
      businessName: current.name,
      deleted: false,
      alreadyDeleted: true,
      releasedSubdomain: null,
      deletedAt: toIsoString(current.deleted_at),
      subdomainReleasedAt: toIsoString(current.subdomain_released_at),
    };
  }

  await runQuery(
    target,
    `DELETE FROM business_access_tokens
     WHERE business_id = $1`,
    [cleanBusinessId],
  );
  await runQuery(
    target,
    `DELETE FROM business_payment_gateways
     WHERE business_id = $1`,
    [cleanBusinessId],
  );
  await runQuery(
    target,
    `UPDATE subscriptions
     SET status = 'canceled',
         updated_at = $2
     WHERE business_id = $1`,
    [cleanBusinessId, deletedAt],
  );
  await runQuery(
    target,
    `UPDATE users
     SET deleted_at = COALESCE(deleted_at, $2),
         updated_at = $2,
         sync_status = 'synced',
         server_revision = nextval('sync_revision_seq')
     WHERE business_id = $1
       AND deleted_at IS NULL`,
    [cleanBusinessId, deletedAt],
  );
  await runQuery(
    target,
    `UPDATE storefront_themes
     SET deleted_at = $2, updated_at = $2
     WHERE business_id = $1 AND deleted_at IS NULL`,
    [cleanBusinessId, deletedAt],
  );
  await runQuery(
    target,
    `UPDATE storefront_pages
     SET deleted_at = $2, updated_at = $2
     WHERE business_id = $1 AND deleted_at IS NULL`,
    [cleanBusinessId, deletedAt],
  );
  await runQuery(
    target,
    `UPDATE storefront_campaigns
     SET deleted_at = $2, updated_at = $2
     WHERE business_id = $1 AND deleted_at IS NULL`,
    [cleanBusinessId, deletedAt],
  );

  const updatedResult = await runQuery(
    target,
    `UPDATE businesses
     SET deleted_at = $2,
         public_subdomain = NULL,
         subdomain_released_at = CASE
           WHEN public_subdomain IS NULL THEN subdomain_released_at
           ELSE $2
         END,
         updated_at = $2
     WHERE id = $1
       AND deleted_at IS NULL
     RETURNING id, name, deleted_at, subdomain_released_at`,
    [cleanBusinessId, deletedAt],
  );
  const updated = updatedResult.rows[0];
  if (!updated) {
    return {
      businessId: current.id,
      businessName: current.name,
      deleted: false,
      alreadyDeleted: true,
      releasedSubdomain: null,
      deletedAt: toIsoString(current.deleted_at),
      subdomainReleasedAt: toIsoString(current.subdomain_released_at),
    };
  }

  return {
    businessId: updated.id,
    businessName: updated.name,
    deleted: true,
    alreadyDeleted: false,
    deletedByUserId: normalizeText(deletedByUserId),
    releasedSubdomain,
    deletedAt: toIsoString(updated.deleted_at),
    subdomainReleasedAt: toIsoString(updated.subdomain_released_at),
  };
}

function normalizeIsoTimestamp(value) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error('Deletion timestamp is invalid');
  }
  return date.toISOString();
}

function normalizeText(value) {
  const text = String(value || '').trim();
  return text || null;
}

function toIsoString(value) {
  if (!value) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function runQuery(target, sql, params = []) {
  if (typeof target === 'function') {
    return target(sql, params);
  }
  return target.query(sql, params);
}

module.exports = {
  deleteBusinessAccount,
};
