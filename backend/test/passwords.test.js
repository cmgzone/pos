const test = require('node:test');
const assert = require('node:assert/strict');

const {
  hashPassword,
  needsPasswordRehash,
  normalizePasswordForStorage,
  verifyPassword,
} = require('../src/passwords');

test('server password hashes verify plaintext and reject hash replay', () => {
  const stored = hashPassword('correct horse battery staple');

  assert.equal(verifyPassword(stored, 'correct horse battery staple'), true);
  assert.equal(verifyPassword(stored, 'wrong password'), false);
  assert.equal(verifyPassword(stored, stored), false);
  assert.equal(needsPasswordRehash(stored), false);
});

test('legacy client hashes verify plaintext and require migration', () => {
  const legacy =
    'velora.v1$12000$dGVzdC1zYWx0$htPcWwbvfC3OBEuIx5nCdZfTE-DHTdW5YBBl7XL_Axc';

  assert.equal(verifyPassword(legacy, 'secret123'), true);
  assert.equal(verifyPassword(legacy, legacy), false);
  assert.equal(needsPasswordRehash(legacy), true);
  assert.equal(normalizePasswordForStorage(legacy), legacy);
});
