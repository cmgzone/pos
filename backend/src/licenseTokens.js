const crypto = require('crypto');

const { config } = require('./config');

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
  const signature = signPayload(payloadBase64);

  return {
    payload,
    payloadBase64,
    signature,
  };
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

function signPayload(payloadBase64) {
  return base64UrlEncode(
    crypto
      .createHmac('sha256', config.licenseSigningSecret)
      .update(String(payloadBase64))
      .digest(),
  );
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
  signPayload,
};
