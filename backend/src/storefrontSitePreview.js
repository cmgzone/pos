const jwt = require('jsonwebtoken');

const PURPOSE = 'storefront_site_build_preview';

function createStorefrontSitePreviewToken({ secret, businessId, build }) {
  if (!secret || !businessId || !build?.id) {
    throw new Error('Generated site preview token context is incomplete');
  }
  return jwt.sign(
    {
      purpose: PURPOSE,
      businessId: String(businessId),
      buildId: String(build.id),
      branchId: String(build.branchId || 'main_branch'),
      storefrontType: String(build.storefrontType || 'retail'),
    },
    secret,
    { expiresIn: '2h' },
  );
}

function verifyStorefrontSitePreviewToken({ secret, token, businessId }) {
  if (!secret || !token || !businessId) return null;
  try {
    const payload = jwt.verify(token, secret);
    if (
      payload?.purpose !== PURPOSE ||
      String(payload.businessId || '') !== String(businessId) ||
      !payload.buildId ||
      !payload.branchId ||
      !payload.storefrontType
    ) return null;
    return {
      buildId: String(payload.buildId),
      branchId: String(payload.branchId),
      storefrontType: String(payload.storefrontType),
      expiresAt: Number(payload.exp || 0) * 1000,
    };
  } catch (_) {
    return null;
  }
}

module.exports = {
  createStorefrontSitePreviewToken,
  verifyStorefrontSitePreviewToken,
};
