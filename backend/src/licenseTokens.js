const crypto = require('crypto');

const { config } = require('./config');

// Ed25519 keys are stored as raw 32-byte seed / public key (base64). The
// private key signs licenses; the public key (shipped in the app) verifies
// them. The raw keys are wrapped in the standard DER prefixes below so Node's
// crypto can build KeyObjects from them.
const ED25519_PRIVATE_PREFIX = Buffer.from(
  '302e020100300506032b657004220420',
  'hex',
);
const ED25519_PUBLIC_PREFIX = Buffer.from(
  '302a300506032b6570032100',
  'hex',
);

function _ed25519PrivateKey() {
  const raw = Buffer.from(config.licenseSigningPrivateKey, 'base64');
  const der = Buffer.concat([ED25519_PRIVATE_PREFIX, raw]);
  return crypto.createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
}

function _ed25519PublicKey() {
  const raw = Buffer.from(config.licenseSigningPublicKey, 'base64');
  const der = Buffer.concat([ED25519_PUBLIC_PREFIX, raw]);
  return crypto.createPublicKey({ key: der, format: 'der', type: 'spki' });
}

function issueLicense({
  businessId,
  businessName,
  countryCode,
  sellingMode,
  deviceId,
  subscription,
  entitlements,
  issuedAt = new Date(),
}) {
  const payload = {
    business_id: String(businessId).trim(),
    business_name: String(businessName || '').trim(),
    country_code: String(countryCode || subscription?.country_code || 'GLOBAL')
      .trim()
      .toUpperCase(),
    selling_mode: String(sellingMode || subscription?.selling_mode || 'combo')
      .trim()
      .toLowerCase(),
    device_id: String(deviceId).trim(),
    plan: String(subscription.plan || 'trial').trim(),
    status: resolveSubscriptionState(subscription, issuedAt).status,
    expires_at: toIsoString(subscription.expires_at),
    grace_until: toIsoString(subscription.grace_until),
    issued_at: toIsoString(issuedAt),
  };
  if (entitlements && typeof entitlements === 'object') {
    payload.entitlements = entitlements;
  }

  const payloadBase64 = base64UrlEncode(JSON.stringify(payload));
  const signature = signPayloadEd25519(payloadBase64);

  return {
    payload,
    payloadBase64,
    signature,
    alg: 'ed25519',
  };
}

function signPayloadEd25519(payloadBase64) {
  const signature = crypto.sign(
    null,
    Buffer.from(payloadBase64, 'utf8'),
    _ed25519PrivateKey(),
  );
  return signature.toString('base64url');
}

function verifyPayloadEd25519(payloadBase64, signature) {
  try {
    const rawSignature = Buffer.from(signature, 'base64url');
    return crypto.verify(
      null,
      Buffer.from(payloadBase64, 'utf8'),
      _ed25519PublicKey(),
      rawSignature,
    );
  } catch (_) {
    return false;
  }
}

function verifyLicenseToken({ payloadBase64, signature, alg }) {
  if (alg !== 'ed25519') {
    return false;
  }
  return verifyPayloadEd25519(payloadBase64, signature);
}

function resolveSubscriptionState(subscription, referenceDate = new Date()) {
  const expiresAt = parseDate(subscription?.expires_at);
  const graceUntil = parseDate(subscription?.grace_until);
  const normalizedStatus = String(subscription?.status || 'active')
    .trim()
    .toLowerCase();

  if (!expiresAt || !graceUntil) {
    return {
      status: 'expired',
      usable: false,
    };
  }

  if (normalizedStatus !== 'active' && normalizedStatus !== 'grace') {
    return {
      status: normalizedStatus || 'expired',
      usable: false,
    };
  }

  const now = parseDate(referenceDate) || new Date();
  if (now > graceUntil) {
    return {
      status: 'expired',
      usable: false,
    };
  }
  if (now > expiresAt) {
    return {
      status: 'grace',
      usable: true,
    };
  }

  return {
    status: 'active',
    usable: true,
  };
}

function toIsoString(value) {
  const parsed = parseDate(value);
  if (!parsed) {
    return null;
  }
  return parsed.toISOString();
}

function parseDate(value) {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }

  if (value == null) {
    return null;
  }

  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function base64UrlEncode(value) {
  return Buffer.from(value).toString('base64url');
}

module.exports = {
  issueLicense,
  resolveSubscriptionState,
  verifyLicenseToken,
  signPayloadEd25519,
};
