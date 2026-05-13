const crypto = require('crypto');

const SERVER_HASH_PREFIX = 'velora.server.v1';
const LEGACY_CLIENT_HASH_PREFIX = 'velora.v1';
const SERVER_HASH_ITERATIONS = 210000;
const SERVER_HASH_KEY_LENGTH = 32;
const SALT_BYTE_LENGTH = 16;

function hashPassword(password) {
  const salt = crypto.randomBytes(SALT_BYTE_LENGTH).toString('base64url');
  const digest = deriveServerDigest({
    password: String(password),
    salt,
    iterations: SERVER_HASH_ITERATIONS,
  });
  return [
    SERVER_HASH_PREFIX,
    String(SERVER_HASH_ITERATIONS),
    salt,
    digest,
  ].join('$');
}

function normalizePasswordForStorage(password) {
  const value = String(password ?? '');
  if (isStoredPasswordHash(value)) {
    return value;
  }
  return hashPassword(value);
}

function verifyPassword(storedPassword, candidatePassword) {
  const stored = String(storedPassword ?? '');
  const candidate = String(candidatePassword ?? '');
  if (!stored || !candidate || isStoredPasswordHash(candidate)) {
    return false;
  }

  const serverHash = parseHash(stored, SERVER_HASH_PREFIX);
  if (serverHash) {
    const candidateDigest = deriveServerDigest({
      password: candidate,
      salt: serverHash.salt,
      iterations: serverHash.iterations,
    });
    return constantTimeEquals(serverHash.digest, candidateDigest);
  }

  const legacyHash = parseHash(stored, LEGACY_CLIENT_HASH_PREFIX);
  if (legacyHash) {
    const candidateDigest = deriveLegacyClientDigest({
      password: candidate,
      salt: legacyHash.salt,
      iterations: legacyHash.iterations,
    });
    return constantTimeEquals(legacyHash.digest, candidateDigest);
  }

  return constantTimeEquals(stored, candidate);
}

function needsPasswordRehash(storedPassword) {
  return parseHash(String(storedPassword ?? ''), SERVER_HASH_PREFIX) == null;
}

function isStoredPasswordHash(value) {
  return (
    parseHash(value, SERVER_HASH_PREFIX) != null ||
    parseHash(value, LEGACY_CLIENT_HASH_PREFIX) != null
  );
}

function deriveServerDigest({ password, salt, iterations }) {
  return crypto
    .pbkdf2Sync(password, salt, iterations, SERVER_HASH_KEY_LENGTH, 'sha256')
    .toString('base64url');
}

function deriveLegacyClientDigest({ password, salt, iterations }) {
  const passwordBytes = Buffer.from(password, 'utf8');
  const saltBytes = Buffer.from(salt, 'utf8');
  let current = sha256(Buffer.concat([saltBytes, passwordBytes]));
  for (let round = 1; round < iterations; round += 1) {
    current = sha256(Buffer.concat([current, saltBytes, passwordBytes]));
  }
  return current.toString('base64url');
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest();
}

function parseHash(value, expectedPrefix) {
  const parts = String(value ?? '').split('$');
  if (parts.length !== 4 || parts[0] !== expectedPrefix) {
    return null;
  }

  const iterations = Number.parseInt(parts[1], 10);
  const salt = parts[2]?.trim() ?? '';
  const digest = parts[3]?.trim() ?? '';
  if (!Number.isSafeInteger(iterations) || iterations <= 0 || !salt || !digest) {
    return null;
  }

  return { iterations, salt, digest };
}

function constantTimeEquals(left, right) {
  const leftBytes = Buffer.from(normalizeBase64Url(left), 'utf8');
  const rightBytes = Buffer.from(normalizeBase64Url(right), 'utf8');
  const maxLength = Math.max(leftBytes.length, rightBytes.length);
  const paddedLeft = Buffer.alloc(maxLength);
  const paddedRight = Buffer.alloc(maxLength);
  leftBytes.copy(paddedLeft);
  rightBytes.copy(paddedRight);

  return (
    crypto.timingSafeEqual(paddedLeft, paddedRight) &&
    leftBytes.length === rightBytes.length
  );
}

function normalizeBase64Url(value) {
  return String(value ?? '').replace(/=+$/u, '');
}

module.exports = {
  LEGACY_CLIENT_HASH_PREFIX,
  SERVER_HASH_PREFIX,
  hashPassword,
  isStoredPasswordHash,
  needsPasswordRehash,
  normalizePasswordForStorage,
  verifyPassword,
};
