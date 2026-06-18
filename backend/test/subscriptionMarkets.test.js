const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeSubscriptionPlatform,
  subscriptionProviderAllowedForPlatform,
  selectSubscriptionMarket,
  subscriptionMarketsForPlatform,
} = require('../src/subscriptionMarkets');

const ALL_MARKETS = [
  { countryCode: 'KE', label: 'Kenya', provider: 'google_play', providerLabel: 'Google Play' },
  { countryCode: 'GLOBAL', label: 'Other Countries', provider: 'google_play', providerLabel: 'Google Play' },
  { countryCode: 'KE', label: 'Kenya', provider: 'flutterwave', providerLabel: 'Flutterwave' },
  { countryCode: 'GLOBAL', label: 'Other Countries', provider: 'flutterwave', providerLabel: 'Flutterwave' },
  { countryCode: 'GLOBAL', label: 'Other Countries', provider: 'paypal', providerLabel: 'PayPal' },
];

test('normalizeSubscriptionPlatform defaults unknown values to windows', () => {
  assert.equal(normalizeSubscriptionPlatform('android'), 'android');
  assert.equal(normalizeSubscriptionPlatform('windows'), 'windows');
  assert.equal(normalizeSubscriptionPlatform(''), 'windows');
  assert.equal(normalizeSubscriptionPlatform(undefined), 'windows');
});

test('subscriptionProviderAllowedForPlatform gates android to google_play', () => {
  assert.equal(subscriptionProviderAllowedForPlatform('google_play', 'android'), true);
  assert.equal(subscriptionProviderAllowedForPlatform('paypal', 'android'), false);
  assert.equal(subscriptionProviderAllowedForPlatform('flutterwave', 'android'), false);
});

test('subscriptionProviderAllowedForPlatform gates windows to paypal and flutterwave', () => {
  assert.equal(subscriptionProviderAllowedForPlatform('paypal', 'windows'), true);
  assert.equal(subscriptionProviderAllowedForPlatform('flutterwave', 'windows'), true);
  assert.equal(subscriptionProviderAllowedForPlatform('google_play', 'windows'), false);
});

test('subscriptionMarketsForPlatform returns exact KE markets without relabeling GLOBAL fallbacks', () => {
  const markets = subscriptionMarketsForPlatform(ALL_MARKETS, 'windows', 'KE');
  const flutterwave = markets.find((m) => m.provider === 'flutterwave');
  const paypal = markets.find((m) => m.provider === 'paypal');

  assert.ok(flutterwave, 'flutterwave market is present');
  assert.equal(flutterwave.countryCode, 'KE');
  assert.equal(flutterwave.label, 'Kenya');

  assert.ok(paypal, 'paypal market is present');
  assert.equal(paypal.countryCode, 'GLOBAL');
  assert.equal(paypal.label, 'Other Countries');
});

test('subscriptionMarketsForPlatform does not label PayPal as Kenya', () => {
  const markets = subscriptionMarketsForPlatform(ALL_MARKETS, 'windows', 'KE');
  const paypal = markets.find((m) => m.provider === 'paypal');
  assert.notEqual(paypal.label, 'Kenya');
  assert.notEqual(paypal.countryCode, 'KE');
});

test('subscriptionMarketsForPlatform for android only returns google_play', () => {
  const markets = subscriptionMarketsForPlatform(ALL_MARKETS, 'android', 'KE');
  assert.equal(markets.length, 1);
  assert.equal(markets[0].provider, 'google_play');
  assert.equal(markets[0].countryCode, 'KE');
});

test('subscriptionMarketsForPlatform for non-KE country falls back to GLOBAL', () => {
  const markets = subscriptionMarketsForPlatform(ALL_MARKETS, 'windows', 'US');
  assert.equal(markets.length, 2);
  const flutterwave = markets.find((m) => m.provider === 'flutterwave');
  const paypal = markets.find((m) => m.provider === 'paypal');
  assert.equal(flutterwave.countryCode, 'GLOBAL');
  assert.equal(flutterwave.label, 'Other Countries');
  assert.equal(paypal.countryCode, 'GLOBAL');
  assert.equal(paypal.label, 'Other Countries');
});

test('selectSubscriptionMarket prefers exact country match', () => {
  const markets = subscriptionMarketsForPlatform(ALL_MARKETS, 'windows', 'KE');
  const selected = selectSubscriptionMarket(markets, { countryCode: 'KE' });
  assert.equal(selected.countryCode, 'KE');
});

test('selectSubscriptionMarket falls back to GLOBAL for provider without local market', () => {
  const markets = subscriptionMarketsForPlatform(ALL_MARKETS, 'windows', 'KE');
  const selected = selectSubscriptionMarket(markets, {
    countryCode: 'KE',
    provider: 'paypal',
  });
  assert.equal(selected.provider, 'paypal');
  assert.equal(selected.countryCode, 'GLOBAL');
});
