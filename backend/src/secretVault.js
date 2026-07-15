const crypto = require('crypto');

const ENVELOPE_PROPERTY = '__pikiEncryptedSecret';
const ENVELOPE_VERSION = 1;
const ENVELOPE_ALGORITHM = 'aes-256-gcm';

function decodeEncryptionKey(value) {
  const raw = String(value || '').trim();
  if (!raw) {
    throw new Error('PAYMENT_SECRETS_ENCRYPTION_KEY is not configured');
  }

  const isHex = /^[a-f0-9]{64}$/i.test(raw);
  if (!isHex && !/^[a-z0-9+/]+={0,2}$/i.test(raw)) {
    throw new Error(
      'PAYMENT_SECRETS_ENCRYPTION_KEY must be a 32-byte key encoded as base64 or 64 hexadecimal characters',
    );
  }
  const key = isHex ? Buffer.from(raw, 'hex') : Buffer.from(raw, 'base64');
  const canonicalInput = raw.replace(/=+$/, '');
  const canonicalKey = key.toString(isHex ? 'hex' : 'base64').replace(/=+$/, '');
  if (key.length !== 32) {
    throw new Error(
      'PAYMENT_SECRETS_ENCRYPTION_KEY must be a 32-byte key encoded as base64 or 64 hexadecimal characters',
    );
  }
  const canonicalMatches = isHex
    ? canonicalInput.toLowerCase() === canonicalKey.toLowerCase()
    : canonicalInput === canonicalKey;
  if (!canonicalMatches) {
    throw new Error(
      'PAYMENT_SECRETS_ENCRYPTION_KEY must be a 32-byte key encoded as base64 or 64 hexadecimal characters',
    );
  }
  return key;
}

function isEncryptedSecretObject(value) {
  const envelope = value?.[ENVELOPE_PROPERTY];
  return Boolean(
    envelope &&
      typeof envelope === 'object' &&
      Number(envelope.version) === ENVELOPE_VERSION &&
      envelope.algorithm === ENVELOPE_ALGORITHM,
  );
}

function encryptSecretObject(value, { encryptionKey, additionalData }) {
  const normalized = normalizeObject(value);
  if (Object.keys(normalized).length === 0) return {};

  const key = decodeEncryptionKey(encryptionKey);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv(ENVELOPE_ALGORITHM, key, iv);
  cipher.setAAD(Buffer.from(String(additionalData || ''), 'utf8'));
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(normalized), 'utf8'),
    cipher.final(),
  ]);

  return {
    [ENVELOPE_PROPERTY]: {
      version: ENVELOPE_VERSION,
      algorithm: ENVELOPE_ALGORITHM,
      iv: iv.toString('base64'),
      authenticationTag: cipher.getAuthTag().toString('base64'),
      ciphertext: ciphertext.toString('base64'),
    },
  };
}

function decryptSecretObject(value, { encryptionKey, additionalData }) {
  const normalized = normalizeObject(value);
  if (!isEncryptedSecretObject(normalized)) {
    return { value: normalized, wasEncrypted: false };
  }

  const envelope = normalized[ENVELOPE_PROPERTY];
  const key = decodeEncryptionKey(encryptionKey);
  try {
    const decipher = crypto.createDecipheriv(
      ENVELOPE_ALGORITHM,
      key,
      Buffer.from(envelope.iv, 'base64'),
    );
    decipher.setAAD(Buffer.from(String(additionalData || ''), 'utf8'));
    decipher.setAuthTag(Buffer.from(envelope.authenticationTag, 'base64'));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
      decipher.final(),
    ]).toString('utf8');
    return { value: normalizeObject(JSON.parse(plaintext)), wasEncrypted: true };
  } catch (_) {
    throw new Error(
      'Stored payment credentials could not be decrypted. Check PAYMENT_SECRETS_ENCRYPTION_KEY before changing it.',
    );
  }
}

function normalizeObject(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : {};
}

module.exports = {
  ENVELOPE_PROPERTY,
  decodeEncryptionKey,
  decryptSecretObject,
  encryptSecretObject,
  isEncryptedSecretObject,
};
