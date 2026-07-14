const test = require('node:test');
const assert = require('node:assert/strict');

const {
  checkoutForActiveGateways,
  defaultStorefrontTheme,
  normalizeStorefrontCheckout,
  normalizeStorefrontThemeDesign,
  normalizeStorefrontThemeInput,
  storefrontThemePresets,
} = require('../src/storefrontThemes');

test('storefront theme presets expose reusable validated designs', () => {
  const presets = storefrontThemePresets();
  assert.ok(presets.length >= 5);
  assert.ok(presets.some((preset) => preset.id === 'minimal'));
  assert.ok(presets.every((preset) => /^#[0-9a-f]{6}$/.test(preset.design.accentColor)));
});

test('restaurant default theme keeps the restaurant presentation', () => {
  const theme = defaultStorefrontTheme({
    storefrontType: 'restaurant',
    brandColor: '#FF2A6D',
  });
  assert.equal(theme.storefrontType, 'restaurant');
  assert.equal(theme.design.accentColor, '#ff2a6d');
  assert.equal(theme.preset, 'warm');
  assert.equal(theme.isPublished, true);
});

test('theme design rejects unsafe values and keeps the valid fallback', () => {
  const design = normalizeStorefrontThemeDesign(
    {
      backgroundColor: 'javascript:alert(1)',
      accentColor: '#ABCDEF',
      heroStyle: '<script>',
      fontFamily: 'remote-font-url',
      cardStyle: 'minimal',
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
