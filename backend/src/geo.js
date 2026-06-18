'use strict';

/**
 * Currency and country resolution helpers shared by the subscription and
 * catalog flows. These are pure functions with no I/O so they can be unit
 * tested directly.
 */

/**
 * Returns the ISO 4217 currency code for a country. Unknown countries fall
 * back to USD so that non-Kenyan businesses default to dollar pricing rather
 * than Kenyan shillings.
 *
 * @param {string} [countryCode] 2-letter ISO country code (e.g. `KE`, `US`).
 * @returns {string} ISO currency code (`KES`, `USD`, ...).
 */
function currencyForCountry(countryCode) {
  const clean = String(countryCode || '').trim().toUpperCase();
  if (clean === 'KE') return 'KES';
  if (clean === 'TZ') return 'TZS';
  if (clean === 'UG') return 'UGX';
  if (clean === 'RW') return 'RWF';
  return 'USD';
}

/**
 * Extracts the first valid 2-letter country segment from an Accept-Language
 * header value such as `en-US,en;q=0.9,fr-FR;q=0.8`.
 *
 * @param {string} acceptLanguage Raw Accept-Language header value.
 * @returns {string|null} Uppercased 2-letter country code, or null.
 */
function parseAcceptLanguageCountry(acceptLanguage) {
  if (!acceptLanguage) return null;
  const parts = String(acceptLanguage).split(',');
  for (const part of parts) {
    const tag = part.split(';')[0].trim();
    if (!tag) continue;
    const segments = tag.split(/[-_]/);
    if (segments.length < 2) continue;
    const country = segments[segments.length - 1].toUpperCase();
    if (/^[A-Z]{2}$/.test(country)) return country;
  }
  return null;
}

/**
 * Resolves the caller's 2-letter ISO country code from request headers.
 * Priority: `cf-ipcountry` -> `x-vercel-ip-country` -> Accept-Language region.
 *
 * @param {import('express').Request} req Express request.
 * @returns {string|null} Uppercased 2-letter country code, or null.
 */
function resolveRequestCountry(req) {
  const headers = (req && req.headers) || {};
  const cf = String(headers['cf-ipcountry'] || '').trim().toUpperCase();
  if (/^[A-Z]{2}$/.test(cf)) return cf;
  const vercel = String(headers['x-vercel-ip-country'] || '')
    .trim()
    .toUpperCase();
  if (/^[A-Z]{2}$/.test(vercel)) return vercel;
  const acceptLanguage = String(headers['accept-language'] || '');
  const fromAccept = parseAcceptLanguageCountry(acceptLanguage);
  if (fromAccept) return fromAccept;
  return null;
}

module.exports = {
  currencyForCountry,
  parseAcceptLanguageCountry,
  resolveRequestCountry,
};
