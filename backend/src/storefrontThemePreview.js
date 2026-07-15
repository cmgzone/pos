const jwt = require('jsonwebtoken');

const STOREFRONT_THEME_PREVIEW_PURPOSE = 'storefront_theme_preview';

function createStorefrontThemePreviewToken({ secret, businessId, theme }) {
  if (!secret || !businessId || !theme?.id) {
    throw new Error('Storefront preview token context is incomplete');
  }
  return jwt.sign(
    {
      purpose: STOREFRONT_THEME_PREVIEW_PURPOSE,
      businessId: String(businessId),
      themeId: String(theme.id),
      branchId: String(theme.branchId || 'main_branch'),
      storefrontType: String(theme.storefrontType || 'retail'),
    },
    secret,
    { expiresIn: '2h' },
  );
}

function verifyStorefrontThemePreviewToken({ secret, token, businessId }) {
  if (!secret || !token || !businessId) return null;
  try {
    const payload = jwt.verify(token, secret);
    if (
      !payload ||
      payload.purpose !== STOREFRONT_THEME_PREVIEW_PURPOSE ||
      String(payload.businessId || '') !== String(businessId) ||
      !payload.themeId ||
      !payload.branchId ||
      !payload.storefrontType
    ) {
      return null;
    }
    return {
      themeId: String(payload.themeId),
      branchId: String(payload.branchId),
      storefrontType: String(payload.storefrontType),
      expiresAt: Number(payload.exp || 0) * 1000,
    };
  } catch (_) {
    return null;
  }
}

module.exports = {
  createStorefrontThemePreviewToken,
  verifyStorefrontThemePreviewToken,
};
