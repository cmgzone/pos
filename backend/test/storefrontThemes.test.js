const test = require('node:test');
const assert = require('node:assert/strict');

const {
  checkoutForActiveGateways,
  createStorefrontTheme,
  defaultStorefrontTheme,
  normalizeStorefrontThemeSections,
  normalizeStorefrontCheckout,
  normalizeStorefrontThemeDesign,
  normalizeStorefrontThemeInput,
  storefrontThemePresets,
} = require('../src/storefrontThemes');

test('storefront theme presets expose reusable validated designs', () => {
  const presets = storefrontThemePresets();
  assert.ok(presets.length >= 5);
  assert.ok(presets.some((preset) => preset.id === 'minimal'));
  assert.ok(presets.some((preset) => preset.id === 'portfolio'));
  assert.ok(presets.every((preset) => /^#[0-9a-f]{6}$/.test(preset.design.accentColor)));
});

test('restaurant default theme keeps the restaurant presentation', () => {
  const theme = defaultStorefrontTheme({
    storefrontType: 'restaurant',
    brandColor: '#C45A00',
  });
  assert.equal(theme.storefrontType, 'restaurant');
  assert.equal(theme.design.accentColor, '#c45a00');
  assert.equal(theme.preset, 'warm');
  assert.equal(theme.isPublished, true);
  assert.ok(theme.sections.some((section) => section.type === 'catalog'));
});

test('storefront sections keep safe ordered content and always include the catalog', () => {
  const sections = normalizeStorefrontThemeSections(
    [
      {
        id: 'Main Hero',
        type: 'hero',
        title: 'Built for this shop',
        buttonAction: 'catalog',
        script: '<script>alert(1)</script>',
      },
      {
        id: 'Why us',
        type: 'benefits',
        items: [
          { title: 'Helpful team', body: 'Ask before ordering.', icon: 'heart' },
          { title: 'Unsafe', body: 'Ignored icon.', icon: 'javascript' },
        ],
      },
      { id: 'raw-code', type: 'html', body: '<iframe />' },
    ],
    [],
    { storefrontType: 'retail' },
  );

  assert.deepEqual(
    sections.map((section) => section.type),
    ['hero', 'benefits', 'catalog'],
  );
  assert.equal(sections[0].id, 'main-hero');
  assert.equal(sections[0].script, undefined);
  assert.equal(sections[1].items[1].icon, 'sparkles');
});

test('storefront sections survive database storage and theme normalization', async () => {
  const target = async (sql, params = []) => {
    if (/CREATE TABLE|CREATE INDEX|CREATE UNIQUE INDEX/i.test(sql)) {
      return { rows: [] };
    }
    if (/INSERT INTO storefront_themes/i.test(sql)) {
      return {
        rows: [
          {
            id: params[0],
            business_id: params[1],
            branch_id: params[2],
            storefront_type: params[3],
            name: params[4],
            preset: params[5],
            design_json: JSON.parse(params[6]),
            checkout_json: JSON.parse(params[7]),
            source: params[8],
            is_published: false,
            created_by: params[9],
          },
        ],
      };
    }
    throw new Error(`Unexpected SQL in test: ${sql}`);
  };

  const theme = await createStorefrontTheme(
    target,
    'business-1',
    {
      name: 'Built store',
      sections: [
        { type: 'hero', title: 'Start here' },
        { type: 'catalog', title: 'Everything' },
      ],
    },
    { createdBy: 'owner-1' },
  );

  assert.deepEqual(
    theme.sections.map((section) => section.type),
    ['hero', 'catalog'],
  );
  assert.equal(theme.sections[1].title, 'Everything');
});

test('theme design rejects unsafe values and keeps the valid fallback', () => {
  const design = normalizeStorefrontThemeDesign(
    {
      backgroundColor: 'javascript:alert(1)',
      accentColor: '#ABCDEF',
      heroStyle: '<script>',
      fontFamily: 'remote-font-url',
      cardStyle: 'minimal',
      catalogLayout: 'sidebar',
    },
    {
      backgroundColor: '#101010',
      accentColor: '#202020',
      heroStyle: 'cover',
      fontFamily: 'inter',
      cardStyle: 'bordered',
    },
  );

  assert.equal(design.backgroundColor, '#101010');
  assert.equal(design.accentColor, '#abcdef');
  assert.equal(design.heroStyle, 'cover');
  assert.equal(design.fontFamily, 'inter');
  assert.equal(design.cardStyle, 'minimal');
  assert.equal(design.catalogLayout, 'sidebar');
});

test('checkout customization only accepts supported payment and fulfillment values', () => {
  const checkout = normalizeStorefrontCheckout({
    paymentMethods: ['mpesa', 'manual', 'raw-card-script'],
    defaultPaymentMethod: 'mpesa',
    fulfillmentMethods: ['delivery', 'teleport'],
    checkoutButtonLabel: 'Send my order',
    showOrderNote: false,
  });

  assert.deepEqual(checkout.paymentMethods, ['mpesa', 'manual']);
  assert.equal(checkout.defaultPaymentMethod, 'mpesa');
  assert.deepEqual(checkout.fulfillmentMethods, ['delivery']);
  assert.equal(checkout.checkoutButtonLabel, 'Send my order');
  assert.equal(checkout.showOrderNote, false);
  assert.equal(checkout.requireCustomerName, true);
  assert.equal(checkout.requirePhone, true);
});

test('inactive gateways are removed from the public checkout', () => {
  const requested = normalizeStorefrontCheckout({
    paymentMethods: ['mpesa'],
    defaultPaymentMethod: 'mpesa',
  });
  const withoutGateway = checkoutForActiveGateways(requested, []);
  const withGateway = checkoutForActiveGateways(requested, ['mpesa']);

  assert.deepEqual(withoutGateway.paymentMethods, ['manual']);
  assert.equal(withoutGateway.defaultPaymentMethod, 'manual');
  assert.deepEqual(withGateway.paymentMethods, ['mpesa']);
  assert.equal(withGateway.defaultPaymentMethod, 'mpesa');
});

test('theme input normalizes branch and storefront scope without imposing a count limit', () => {
  const themes = Array.from({ length: 250 }, (_, index) =>
    normalizeStorefrontThemeInput({
      name: `Theme ${index + 1}`,
      branchId: 'main_branch',
      storefrontType: 'services',
      preset: index % 2 === 0 ? 'fresh' : 'minimal',
    }),
  );

  assert.equal(themes.length, 250);
  assert.ok(themes.every((theme) => theme.storefrontType === 'services'));
  assert.ok(themes.every((theme) => theme.branchId === 'main_branch'));
});
