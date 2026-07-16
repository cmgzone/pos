const crypto = require('crypto');

const PURPOSE = 'storefront_page_preview';

function createStorefrontPagePreviewToken({ secret, businessId, page, expiresInSeconds = 3600 }) {
  const payload = {
    purpose: PURPOSE,
    businessId: String(businessId),
    pageId: String(page.id),
    branchId: String(page.branchId || 'main_branch'),
    storefrontType: String(page.storefrontType || 'retail'),
    slug: String(page.slug || ''),
    exp: Math.floor(Date.now() / 1000) + Math.max(60, Number(expiresInSeconds) || 3600),
  };
  const encoded = base64Url(JSON.stringify(payload));
  const signature = sign(encoded, secret);
  return `${encoded}.${signature}`;
}

function verifyStorefrontPagePreviewToken({ secret, token, businessId }) {
  const [encoded, signature] = String(token || '').split('.');
  if (!encoded || !signature) return null;
  const expected = sign(encoded, secret);
  if (!safeEqual(signature, expected)) return null;
  try {
    const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    if (payload.purpose !== PURPOSE || String(payload.businessId) !== String(businessId)) return null;
    if (!payload.pageId || !payload.branchId || !payload.storefrontType) return null;
    if (!Number.isFinite(payload.exp) || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

function base64Url(value) {
  return Buffer.from(value, 'utf8').toString('base64url');
}

function sign(value, secret) {
  return crypto.createHmac('sha256', String(secret || '')).update(value).digest('base64url');
}

function safeEqual(first, second) {
  const a = Buffer.from(String(first || ''));
  const b = Buffer.from(String(second || ''));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

module.exports = {
  createStorefrontPagePreviewToken,
  verifyStorefrontPagePreviewToken,
};
