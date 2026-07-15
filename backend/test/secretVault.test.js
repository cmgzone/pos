const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');

const {
  decryptSecretObject,
  encryptSecretObject,
  isEncryptedSecretObject,
} = require('../src/secretVault');

const key = crypto.randomBytes(32).toString('base64');
const additionalData = 'business_payment_gateways:business-1:mpesa';

test('payment secrets are encrypted with authenticated encryption', () => {
  const secrets = {
    consumerKey: 'merchant-key',
    consumerSecret: 'merchant-secret',
    passkey: 'merchant-passkey',
  };
  const encrypted = encryptSecretObject(secrets, {
    encryptionKey: key,
    additionalData,
  });

  assert.equal(isEncryptedSecretObject(encrypted), true);
  assert.equal(JSON.stringify(encrypted).includes('merchant-secret'), false);
  assert.deepEqual(
    decryptSecretObject(encrypted, {
      encryptionKey: key,
      additionalData,
    }),
    { value: secrets, wasEncrypted: true },
  );
});

test('payment secret ciphertext is bound to its business and provider', () => {
  const encrypted = encryptSecretObject(
    { consumerSecret: 'merchant-secret' },
    { encryptionKey: key, additionalData },
  );

  assert.throws(
    () =>
      decryptSecretObject(encrypted, {
        encryptionKey: key,
        additionalData: 'business_payment_gateways:business-2:mpesa',
      }),
    /could not be decrypted/,
  );
});

test('tampered payment secret ciphertext is rejected', () => {
  const encrypted = encryptSecretObject(
    { passkey: 'merchant-passkey' },
    { encryptionKey: key, additionalData },
  );
  encrypted.__pikiEncryptedSecret.ciphertext = Buffer.from(
    'tampered',
  ).toString('base64');

  assert.throws(
    () =>
      decryptSecretObject(encrypted, {
        encryptionKey: key,
        additionalData,
      }),
    /could not be decrypted/,
  );
});

test('legacy plaintext objects are identified for migration', () => {
  const legacy = { consumerKey: 'legacy-key' };
  assert.deepEqual(
    decryptSecretObject(legacy, {
      encryptionKey: '',
      additionalData,
    }),
    { value: legacy, wasEncrypted: false },
  );
});

test('invalid encryption keys are rejected before storing credentials', () => {
  assert.throws(
    () =>
      encryptSecretObject(
        { consumerKey: 'merchant-key' },
        { encryptionKey: 'not-a-key', additionalData },
      ),
    /must be a 32-byte key/,
  );
});
