const test = require('node:test');
const assert = require('node:assert/strict');

const {
  currencyForCountry,
  parseAcceptLanguageCountry,
  resolveRequestCountry,
} = require('../src/geo');

test('currencyForCountry maps known EAC countries and defaults to USD', () => {
  assert.equal(currencyForCountry('KE'), 'KES');
  assert.equal(currencyForCountry('TZ'), 'TZS');
  assert.equal(currencyForCountry('UG'), 'UGX');
  assert.equal(currencyForCountry('RW'), 'RWF');
  assert.equal(currencyForCountry('US'), 'USD');
  assert.equal(currencyForCountry('GB'), 'USD');
  assert.equal(currencyForCountry('NG'), 'USD');
  assert.equal(currencyForCountry(''), 'USD');
  assert.equal(currencyForCountry(null), 'USD');
  assert.equal(currencyForCountry(undefined), 'USD');
});

test('currencyForCountry is case-insensitive and trims input', () => {
  assert.equal(currencyForCountry('ke'), 'KES');
  assert.equal(currencyForCountry('  KE  '), 'KES');
  assert.equal(currencyForCountry('us'), 'USD');
});

test('parseAcceptLanguageCountry extracts the first region tag', () => {
  assert.equal(parseAcceptLanguageCountry('en-US,en;q=0.9'), 'US');
  assert.equal(parseAcceptLanguageCountry('sw-KE,fr-FR;q=0.8'), 'KE');
  assert.equal(parseAcceptLanguageCountry('en-GB,en;q=0.9'), 'GB');
  assert.equal(parseAcceptLanguageCountry('fr-FR;q=0.8,en-US;q=0.6'), 'FR');
  assert.equal(parseAcceptLanguageCountry('en_US'), 'US');
});

test('parseAcceptLanguageCountry returns null when no region is present', () => {
  assert.equal(parseAcceptLanguageCountry('en'), null);
  assert.equal(parseAcceptLanguageCountry('en;q=0.9'), null);
  assert.equal(parseAcceptLanguageCountry(''), null);
  assert.equal(parseAcceptLanguageCountry(null), null);
  assert.equal(parseAcceptLanguageCountry('en-USA'), null);
});

test('resolveRequestCountry prefers cf-ipcountry when present', () => {
  const req = {
    headers: {
      'cf-ipcountry': 'GB',
      'x-vercel-ip-country': 'US',
      'accept-language': 'fr-FR',
    },
  };
  assert.equal(resolveRequestCountry(req), 'GB');
});

test('resolveRequestCountry falls back to x-vercel-ip-country', () => {
  const req = {
    headers: {
      'x-vercel-ip-country': 'us',
      'accept-language': 'fr-FR',
    },
  };
  assert.equal(resolveRequestCountry(req), 'US');
});

test('resolveRequestCountry falls back to accept-language', () => {
  const req = {
    headers: {
      'accept-language': 'en-KE,en;q=0.9',
    },
  };
  assert.equal(resolveRequestCountry(req), 'KE');
});

test('resolveRequestCountry returns null when no signal is present', () => {
  assert.equal(resolveRequestCountry({ headers: {} }), null);
  assert.equal(resolveRequestCountry({}), null);
  assert.equal(resolveRequestCountry(null), null);
});
