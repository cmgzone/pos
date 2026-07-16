const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createStorefrontSitePreviewToken,
  verifyStorefrontSitePreviewToken,
} = require('../src/storefrontSitePreview');

const secret = 'generated-site-preview-test-secret';

test('generated site preview token preserves the exact build scope', () => {
  const token = createStorefrontSitePreviewToken({
    secret,
    businessId: 'business-1',
    build: {
      id: 'build-7',
      branchId: 'westlands',
      storefrontType: 'retail',
    },
  });
  const preview = verifyStorefrontSitePreviewToken({
    secret,
    token,
    businessId: 'business-1',
  });
  assert.equal(preview.buildId, 'build-7');
  assert.equal(preview.branchId, 'westlands');
  assert.equal(preview.storefrontType, 'retail');
  assert.ok(preview.expiresAt > Date.now());
});

test('generated site preview token cannot cross business boundaries', () => {
  const token = createStorefrontSitePreviewToken({
    secret,
    businessId: 'business-1',
    build: { id: 'build-7', branchId: 'main_branch', storefrontType: 'retail' },
  });
  assert.equal(
    verifyStorefrontSitePreviewToken({
      secret,
      token,
      businessId: 'business-2',
    }),
    null,
  );
});
