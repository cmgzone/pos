const test = require('node:test');
const assert = require('node:assert/strict');

const { maxCursor, normalizeCursor } = require('../src/syncCursor');

test('normalizeCursor keeps numeric cursors and trims whitespace', () => {
  assert.equal(normalizeCursor(' 00142 '), '142');
});

test('normalizeCursor returns null for empty values', () => {
  assert.equal(normalizeCursor(''), null);
  assert.equal(normalizeCursor(null), null);
});

test('normalizeCursor rejects invalid cursor values', () => {
  assert.throws(() => normalizeCursor('14a'), /Invalid cursor/);
  assert.throws(() => normalizeCursor('-1'), /Invalid cursor/);
});

test('maxCursor returns the highest cursor value', () => {
  assert.equal(maxCursor('15', '20'), '20');
  assert.equal(maxCursor('20', '15'), '20');
  assert.equal(maxCursor(null, '15'), '15');
  assert.equal(maxCursor('15', null), '15');
});
