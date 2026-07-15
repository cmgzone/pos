const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createStorefrontCampaign,
  normalizeCampaignInput,
  normalizeSlug,
} = require('../src/storefrontCampaigns');

test('campaign input produces safe reusable landing-page data', () => {
  const campaign = normalizeCampaignInput({
    name: 'July Skin & Hair Offers!',
    title: 'Everyday care, selected for you',
    storefrontType: 'retail',
    productIds: ['p-1', 'p-1', 'p-2'],
    highlights: ['Verified products', 'Easy pickup'],
    heroImageUrl: 'javascript:alert(1)',
  });

  assert.equal(campaign.slug, 'july-skin-hair-offers');
  assert.deepEqual(campaign.productIds, ['p-1', 'p-2']);
  assert.equal(campaign.heroImageUrl, null);
  assert.equal(campaign.buttonLabel, 'Shop the campaign');
});

test('campaign slugs remain stable and shareable', () => {
  assert.equal(normalizeSlug('  Back To School 2026 '), 'back-to-school-2026');
  assert.equal(normalizeSlug('Café & Gifts'), 'cafe-gifts');
});

test('campaign creation stores a draft and normalized product selection', async () => {
  const target = async (sql, params = []) => {
    if (/CREATE TABLE|CREATE INDEX|CREATE UNIQUE INDEX/i.test(sql)) {
      return { rows: [] };
    }
    if (/INSERT INTO storefront_campaigns/i.test(sql)) {
      return {
        rows: [
          {
            id: params[0],
            business_id: params[1],
            branch_id: params[2],
            storefront_type: params[3],
            name: params[4],
            slug: params[5],
            eyebrow: params[6],
            title: params[7],
            description: params[8],
            badge_label: params[9],
            button_label: params[10],
            hero_image_url: params[11],
            product_ids_json: JSON.parse(params[12]),
            highlights_json: JSON.parse(params[13]),
            status: 'draft',
          },
        ],
      };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  };

  const campaign = await createStorefrontCampaign(
    target,
    'business-1',
    {
      name: 'Weekend picks',
      title: 'A better weekend shop',
      productIds: ['p-1', 'p-2'],
    },
    { createdBy: 'owner-1' },
  );

  assert.equal(campaign.status, 'draft');
  assert.deepEqual(campaign.productIds, ['p-1', 'p-2']);
  assert.equal(campaign.slug, 'weekend-picks');
});
