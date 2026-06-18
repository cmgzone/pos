'use strict';

const { normalizeCountryCode, normalizeProvider } = require('./subscriptionPlans');

/**
 * Normalizes the subscription platform value. Unknown values default to
 * `windows` (the desktop/web build target).
 */
function normalizeSubscriptionPlatform(value) {
  const platform = String(value || '').trim().toLowerCase();
  if (platform === 'android') return 'android';
  if (platform === 'windows') return 'windows';
  return platform || 'windows';
}

/**
 * Returns true when the payment provider is allowed for the given platform.
 * Android uses Google Play Billing; Windows uses PayPal or Flutterwave.
 */
function subscriptionProviderAllowedForPlatform(provider, platform) {
  const cleanProvider = normalizeProvider(provider);
  const cleanPlatform = normalizeSubscriptionPlatform(platform);
  if (cleanPlatform === 'android') {
    return cleanProvider === 'google_play';
  }
  return cleanProvider === 'paypal' || cleanProvider === 'flutterwave';
}

/**
 * Selects the best market for a country/provider request. Falls back from an
 * exact country+provider match to the GLOBAL+provider market, then to the
 * first market matching the provider, then to the first market overall.
 */
function selectSubscriptionMarket(markets, { countryCode, provider } = {}) {
  const cleanCountry = normalizeOptionalText(countryCode)
    ? normalizeCountryCode(countryCode)
    : null;
  const cleanProvider = normalizeOptionalText(provider)
    ? normalizeProvider(provider)
    : null;
  const matchesProvider = (market) =>
    !cleanProvider || market.provider === cleanProvider;

  if (cleanCountry) {
    const exact = markets.find(
      (market) =>
        market.countryCode === cleanCountry &&
        matchesProvider(market),
    );
    if (exact) return exact;

    const global = markets.find(
      (market) =>
        market.countryCode === 'GLOBAL' &&
        matchesProvider(market),
    );
    if (global) return global;
  }

  if (cleanProvider) {
    const byProvider = markets.find(matchesProvider);
    if (byProvider) return byProvider;
  }

  return markets[0] || null;
}

/**
 * Builds the per-provider market list for a platform. For each provider that
 * is allowed on the platform, prefers an exact country match and falls back to
 * the GLOBAL market. GLOBAL markets keep their original countryCode and label
 * so that providers without a local presence (e.g. PayPal in Kenya) are shown
 * honestly as "Other Countries" rather than mislabeled as the requested
 * country.
 */
function subscriptionMarketsForPlatform(markets, platform, countryCode) {
  const cleanCountry = normalizeCountryCode(countryCode || 'KE');
  const filtered = (markets || []).filter((market) =>
    subscriptionProviderAllowedForPlatform(market.provider, platform),
  );
  const providers = [...new Set(filtered.map((market) => market.provider))];
  return providers.flatMap((provider) => {
    const exact = filtered.find(
      (market) =>
        market.provider === provider && market.countryCode === cleanCountry,
    );
    if (exact) return [exact];
    const global = filtered.find(
      (market) => market.provider === provider && market.countryCode === 'GLOBAL',
    );
    if (!global) return [];
    return [global];
  });
}

function normalizeOptionalText(value) {
  const text = String(value || '').trim();
  return text === '' ? null : text;
}

module.exports = {
  normalizeSubscriptionPlatform,
  subscriptionProviderAllowedForPlatform,
  selectSubscriptionMarket,
  subscriptionMarketsForPlatform,
};
