const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createStorefrontPage,
  normalizePageSlug,
  normalizeStorefrontPageInput,
} = require('../src/storefrontPages');
const {
  createStorefrontPagePreviewToken,
  verifyStorefrontPagePreviewToken,
} = require('../src/storefrontPagePreview');

test('custom pages keep flexible sections without forcing a catalog', () => {
  const page = normalizeStorefrontPageInput({
    title: 'Our Story',
    pageType: 'about',
    sections: [
      {
        id: 'story',
        type: 'richText',
        title: 'How we started',
        content: 'A truthful business story.',
        width: 'narrow',
        spacing: 'spacious',
      },
      {
        id: 'questions',
        type: 'faq',
        title: 'Questions',
        items: [{ question: 'Where are you based?', answer: 'Contact our team for branch details.' }],
      },
    ],
  });

  assert.equal(page.slug, 'our-story');
  assert.deepEqual(page.sections.map((section) => section.type), ['richText', 'faq']);
  assert.equal(page.sections[0].width, 'narrow');
  assert.equal(page.sections[0].spacing, 'spacious');
});

test('page slugs remain clean and shareable', () => {
  assert.equal(normalizePageSlug('  Returns & Delivery  '), 'returns-delivery');
  assert.equal(normalizePageSlug('Café Story'), 'cafe-story');
});

test('page creation stores a normalized draft', async () => {
  const target = async (sql, params = []) => {
    if (/CREATE TABLE|CREATE INDEX|CREATE UNIQUE INDEX/i.test(sql)) return { rows: [] };
    if (/INSERT INTO storefront_pages/i.test(sql)) {
      return {
        rows: [{
          id: params[0],
          business_id: params[1],
          branch_id: params[2],
          storefront_type: params[3],
          page_type: params[4],
          title: params[5],
          slug: params[6],
          navigation_label: params[7],
          show_in_navigation: params[8],
          seo_title: params[9],
          seo_description: params[10],
          sections_json: JSON.parse(params[11]),
          status: 'draft',
          source: params[12],
        }],
      };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  };
  const page = await createStorefrontPage(target, 'business-1', {
    title: 'Contact',
    pageType: 'contact',
  });
  assert.equal(page.status, 'draft');
  assert.equal(page.slug, 'contact');
  assert.ok(page.sections.some((section) => section.type === 'contact'));
});

test('page preview tokens are scoped to the business and page', () => {
  const token = createStorefrontPagePreviewToken({
    secret: 'preview-secret',
    businessId: 'business-1',
    page: {
      id: 'page-1',
      branchId: 'main_branch',
      storefrontType: 'retail',
      slug: 'about',
    },
  });
  const preview = verifyStorefrontPagePreviewToken({
    secret: 'preview-secret',
    token,
    businessId: 'business-1',
  });
  assert.equal(preview.pageId, 'page-1');
  assert.equal(preview.slug, 'about');
  assert.equal(
    verifyStorefrontPagePreviewToken({
      secret: 'preview-secret',
      token,
      businessId: 'business-2',
    }),
    null,
  );
});
