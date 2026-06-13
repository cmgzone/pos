const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizePublicCatalogBranches,
} = require('../src/catalogBranches');

test('catalog branches include a default main branch for older businesses', () => {
  assert.deepEqual(normalizePublicCatalogBranches([]), [
    { id: 'main_branch', name: 'Main' },
  ]);
});

test('catalog branches preserve an existing main branch without duplicating it', () => {
  assert.deepEqual(
    normalizePublicCatalogBranches([
      { id: 'main_branch', name: 'Head Office' },
      { id: 'west', name: 'West Branch' },
    ]),
    [
      { id: 'main_branch', name: 'Head Office' },
      { id: 'west', name: 'West Branch' },
    ],
  );
});
