const test = require('node:test');
const assert = require('node:assert/strict');

const {
  meetsSeverity,
  normalizeCooldown,
  normalizeSeverity,
} = require('../src/pikiCloud');

test('Piki Cloud only delivers alerts at or above the configured severity', () => {
  assert.equal(meetsSeverity('high', 'high'), true);
  assert.equal(meetsSeverity('high', 'medium'), true);
  assert.equal(meetsSeverity('medium', 'high'), false);
  assert.equal(meetsSeverity('info', 'medium'), false);
});

test('Piki Cloud normalizes its delivery thresholds safely', () => {
  assert.equal(normalizeSeverity('MEDIUM'), 'medium');
  assert.equal(normalizeSeverity('unknown'), 'high');
  assert.equal(normalizeCooldown(1), 15);
  assert.equal(normalizeCooldown(999999), 10080);
  assert.equal(normalizeCooldown('bad value'), 360);
});
