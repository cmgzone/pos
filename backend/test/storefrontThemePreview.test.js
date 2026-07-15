const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createStorefrontThemePreviewToken,
  verifyStorefrontThemePreviewToken,
} = require('../src/storefrontThemePreview');

const secret = 'storefront-preview-test-secret';

test('storefront preview token keeps the draft theme scope', () => {
  const token = createStorefrontThemePreviewToken({
    secret,
    businessId: 'business-1',
    theme: {
      id: 'theme-draft-1',
      branchId: 'main_branch',
      storefrontType: 'retail',
    },
  });

  const preview = verifyStorefrontThemePreviewToken({
    secret,
    token,
    businessId: 'business-1',
  });
  assert.equal(preview.themeId, 'theme-draft-1');
  assert.equal(preview.branchId, 'main_branch');
  assert.equal(preview.storefrontType, 'retail');
  assert.ok(preview.expiresAt > Date.now());
});

test('storefront preview token cannot be reused for another business', () => {
  const token = createStorefrontThemePreviewToken({
    secret,
    businessId: 'business-1',
    theme: {
      id: 'theme-draft-1',
      branchId: 'main_branch',
      storefrontType: 'retail',
    },
  });

  assert.equal(
    verifyStorefrontThemePreviewToken({
      secret,
      token,
      businessId: 'business-2',
    }),
    null,
  );
});
