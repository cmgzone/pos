const test = require('node:test');
const assert = require('node:assert/strict');

const { normalizeConnectionInput } = require('../src/storefrontConnections');

test('store connection accepts public HTTPS endpoints and safe mappings', () => {
  const connection = normalizeConnectionInput({
    endpointUrl: 'https://store.example.com/api/products',
    authType: 'apiKey',
    apiKeyHeader: 'X-Store-Key',
    dataPath: 'data.products',
    fieldMappings: {
      name: 'attributes.name',
      price: 'attributes.price',
      ignored: 'private.secret',
    },
  });
  assert.equal(connection.endpointUrl, 'https://store.example.com/api/products');
  assert.equal(connection.apiKeyHeader, 'X-Store-Key');
  assert.deepEqual(connection.fieldMappings, {
    name: 'attributes.name',
    price: 'attributes.price',
  });
});

test('store connection rejects credentials embedded in endpoint URLs', () => {
  assert.throws(
    () => normalizeConnectionInput({ endpointUrl: 'https://user:pass@example.com/products' }),
    /public HTTPS store API endpoint/i,
  );
});
