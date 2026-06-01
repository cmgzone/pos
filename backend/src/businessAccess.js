const crypto = require('crypto');

const { config } = require('./config');
const { query, withTransaction } = require('./db');
const { issueLicense, resolveSubscriptionState } = require('./licenseTokens');
const {
  applySellingModeToEntitlements,
  ensureSubscriptionSchema,
  loadEntitlementsForPlan,
  loadPlatformSubscriptionSettings,
  normalizeCountryCode,
  normalizeSellingMode,
} = require('./subscriptionPlans');

async function activateBusinessAccess({
  deviceId,
  businessName,
  ownerName,
  ownerEmail,
  deviceName,
  countryCode,
  currency,
  sellingMode,
}) {
  const normalizedDeviceId = normalizeText(deviceId);
  const normalizedBusinessName = normalizeText(businessName);
  const normalizedCountryCode = normalizeCountryCode(countryCode || 'GLOBAL');
  const normalizedCurrency =
    normalizeCurrency(currency) || displayCurrencyForCountry(normalizedCountryCode);
  const normalizedSellingMode = normalizeSellingMode(sellingMode) || 'combo';

  if (!normalizedDeviceId) {
    throw new Error('deviceId is required');
  }
  if (!normalizedBusinessName) {
    throw new Error('businessName is required');
  }

  return withTransaction(async (client) => {
    await ensureSubscriptionSchema(client);
    const subscriptionSettings = await loadPlatformSubscriptionSettings(client);
    const now = new Date();
    const existingContext = await loadBusinessContextByDevice(client, normalizedDeviceId);

    let businessId = existingContext?.business_id || null;
    if (!businessId) {
      businessId = crypto.randomUUID();
      await client.query(
        `
        INSERT INTO businesses (id, name, owner_name, owner_email, country_code, currency, selling_mode, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)
        `,
        [
          businessId,
          normalizedBusinessName,
          normalizeText(ownerName),
          normalizeText(ownerEmail),
          normalizedCountryCode,
          normalizedCurrency,
          normalizedSellingMode,
          now.toISOString(),
        ],
      );

      const expiresAt = addDays(now, subscriptionSettings.trialDays);
      const graceUntil = addDays(expiresAt, config.subscriptionGraceDays);
      await client.query(
        `
        INSERT INTO subscriptions (
          business_id,
          plan,
          status,
          expires_at,
          grace_until,
          last_verified_at,
          created_at,
          updated_at
        )
        VALUES ($1, 'trial', 'active', $2, $3, $4, $4, $4)
        `,
        [businessId, expiresAt.toISOString(), graceUntil.toISOString(), now.toISOString()],
      );
    } else {
      await client.query(
        `
        UPDATE businesses
        SET
          name = COALESCE(NULLIF($2, ''), name),
          owner_name = COALESCE(NULLIF($3, ''), owner_name),
          owner_email = COALESCE(NULLIF($4, ''), owner_email),
          country_code = COALESCE(NULLIF($5, ''), country_code),
          currency = COALESCE(NULLIF($6, ''), currency),
          selling_mode = COALESCE(NULLIF($7, ''), selling_mode),
          updated_at = $8
        WHERE id = $1
        `,
        [
          businessId,
          normalizedBusinessName,
          normalizeText(ownerName),
          normalizeText(ownerEmail),
          normalizedCountryCode,
          normalizedCurrency,
          normalizedSellingMode,
          now.toISOString(),
        ],
      );

      await ensureSubscriptionRow(
        client,
        businessId,
        now,
        subscriptionSettings.trialDays,
      );
    }

    await client.query(
      `
      INSERT INTO devices (id, business_id, name, last_seen_at, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $4, $4)
      ON CONFLICT (id) DO UPDATE
      SET
        business_id = EXCLUDED.business_id,
        name = COALESCE(EXCLUDED.name, devices.name),
        last_seen_at = EXCLUDED.last_seen_at,
        updated_at = EXCLUDED.updated_at
      `,
      [
        normalizedDeviceId,
        businessId,
        normalizeText(deviceName),
        now.toISOString(),
      ],
    );

    const accessToken = crypto.randomBytes(32).toString('base64url');
    await client.query(
      `
      INSERT INTO business_access_tokens (business_id, access_token, created_at, updated_at)
      VALUES ($1, $2, $3, $3)
      ON CONFLICT (business_id) DO UPDATE
      SET
        access_token = EXCLUDED.access_token,
        updated_at = EXCLUDED.updated_at
      `,
      [businessId, accessToken, now.toISOString()],
    );

    const refreshedContext = await loadBusinessContextByDevice(
      client,
      normalizedDeviceId,
    );

    return buildAccessResponse({
      client,
      deviceId: normalizedDeviceId,
      accessToken,
      businessContext: refreshedContext,
      issuedAt: now,
    });
  });
}

async function refreshBusinessAccess({ accessToken, deviceId }) {
  const normalizedToken = normalizeText(accessToken);
  const normalizedDeviceId = normalizeText(deviceId);
  if (!normalizedToken) {
    throw new Error('Authorization token is required');
  }
  if (!normalizedDeviceId) {
    throw new Error('deviceId is required');
  }

  return withTransaction(async (client) => {
    await ensureSubscriptionSchema(client);
    const context = await loadBusinessContextByToken(
      client,
      normalizedToken,
      normalizedDeviceId,
    );
    if (!context) {
      return null;
    }

    const now = new Date();
    await client.query(
      `
      UPDATE devices
      SET last_seen_at = $2, updated_at = $2
      WHERE id = $1
      `,
      [normalizedDeviceId, now.toISOString()],
    );
    await client.query(
      `
      UPDATE subscriptions
      SET last_verified_at = $2, updated_at = $2
      WHERE business_id = $1
      `,
      [context.business_id, now.toISOString()],
    );

    const refreshedContext = await loadBusinessContextByToken(
      client,
      normalizedToken,
      normalizedDeviceId,
    );

    return buildAccessResponse({
      client,
      deviceId: normalizedDeviceId,
      accessToken: normalizedToken,
      businessContext: refreshedContext,
      issuedAt: now,
    });
  });
}

async function resolveBusinessAccess({ accessToken, deviceId }) {
  const normalizedToken = normalizeText(accessToken);
  const normalizedDeviceId = normalizeText(deviceId);
  if (!normalizedToken || !normalizedDeviceId) {
    return null;
  }

  await ensureSubscriptionSchema();
  const result = await query(
    `
    SELECT
      b.id AS business_id,
      b.name AS business_name,
      b.country_code,
      b.currency,
      b.selling_mode,
      s.plan,
      s.status,
      s.expires_at,
      s.grace_until,
      s.last_verified_at,
      d.id AS device_id
    FROM business_access_tokens t
    JOIN businesses b ON b.id = t.business_id
    JOIN subscriptions s ON s.business_id = b.id
    JOIN devices d ON d.business_id = b.id AND d.id = $2
    WHERE t.access_token = $1
    LIMIT 1
    `,
    [normalizedToken, normalizedDeviceId],
  );

  if (!result.rows.length) {
    return null;
  }

  const context = result.rows[0];
  const licenseState = resolveSubscriptionState(context);
  const sellingMode = normalizeSellingMode(context.selling_mode) || 'combo';
  const entitlements = applySellingModeToEntitlements(
    await loadEntitlementsForPlan(context.plan),
    sellingMode,
  );
  return {
    businessId: context.business_id,
    businessName: context.business_name,
    countryCode: normalizeCountryCode(context.country_code || 'GLOBAL'),
    currency: normalizeCurrency(context.currency) || displayCurrencyForCountry(context.country_code),
    sellingMode,
    deviceId: context.device_id,
    plan: context.plan,
    entitlements,
    subscriptionStatus: licenseState.status,
    usable: licenseState.usable,
    expiresAt: toIsoString(context.expires_at),
    graceUntil: toIsoString(context.grace_until),
    lastVerifiedAt: toIsoString(context.last_verified_at),
  };
}

function parseBearerToken(headerValue) {
  const raw = String(headerValue || '').trim();
  if (!raw.toLowerCase().startsWith('bearer ')) {
    return null;
  }
  return normalizeText(raw.slice(7));
}

async function ensureSubscriptionRow(client, businessId, now, trialDays) {
  const result = await client.query(
    'SELECT business_id FROM subscriptions WHERE business_id = $1 LIMIT 1',
    [businessId],
  );
  if (result.rows.length) {
    return;
  }

  const expiresAt = addDays(now, trialDays);
  const graceUntil = addDays(expiresAt, config.subscriptionGraceDays);
  await client.query(
    `
    INSERT INTO subscriptions (
      business_id,
      plan,
      status,
      expires_at,
      grace_until,
      last_verified_at,
      created_at,
      updated_at
    )
    VALUES ($1, 'trial', 'active', $2, $3, $4, $4, $4)
    `,
    [businessId, expiresAt.toISOString(), graceUntil.toISOString(), now.toISOString()],
  );
}

async function loadBusinessContextByDevice(client, deviceId) {
  const result = await client.query(
    `
    SELECT
      b.id AS business_id,
      b.name AS business_name,
      b.country_code,
      b.currency,
      b.selling_mode,
      s.plan,
      s.status,
      s.expires_at,
      s.grace_until,
      s.last_verified_at,
      d.id AS device_id
    FROM devices d
    JOIN businesses b ON b.id = d.business_id
    LEFT JOIN subscriptions s ON s.business_id = b.id
    WHERE d.id = $1
    LIMIT 1
    `,
    [deviceId],
  );

  return result.rows[0] || null;
}

async function loadBusinessContextByToken(client, accessToken, deviceId) {
  const result = await client.query(
    `
    SELECT
      b.id AS business_id,
      b.name AS business_name,
      b.country_code,
      b.currency,
      b.selling_mode,
      s.plan,
      s.status,
      s.expires_at,
      s.grace_until,
      s.last_verified_at,
      d.id AS device_id
    FROM business_access_tokens t
    JOIN businesses b ON b.id = t.business_id
    JOIN devices d ON d.business_id = b.id AND d.id = $2
    LEFT JOIN subscriptions s ON s.business_id = b.id
    WHERE t.access_token = $1
    LIMIT 1
    `,
    [accessToken, deviceId],
  );

  return result.rows[0] || null;
}

async function buildAccessResponse({
  client,
  deviceId,
  accessToken,
  businessContext,
  issuedAt,
}) {
  if (!businessContext) {
    throw new Error('Business access context could not be resolved');
  }

  const entitlements = applySellingModeToEntitlements(
    await loadEntitlementsForPlan(
      businessContext.plan,
      client || query,
    ),
    businessContext.selling_mode,
  );

  const license = issueLicense({
    businessId: businessContext.business_id,
    businessName: businessContext.business_name,
    countryCode: normalizeCountryCode(businessContext.country_code || 'GLOBAL'),
    sellingMode: normalizeSellingMode(businessContext.selling_mode) || 'combo',
    deviceId,
    subscription: businessContext,
    entitlements,
    issuedAt,
  });

  return {
    business: {
      id: businessContext.business_id,
      name: businessContext.business_name,
      countryCode: normalizeCountryCode(businessContext.country_code || 'GLOBAL'),
      currency:
        normalizeCurrency(businessContext.currency) ||
        displayCurrencyForCountry(businessContext.country_code),
      sellingMode: normalizeSellingMode(businessContext.selling_mode) || 'combo',
    },
    accessToken,
    subscription: {
      plan: String(businessContext.plan || 'trial'),
      status: resolveSubscriptionState(businessContext, issuedAt).status,
      expiresAt: toIsoString(businessContext.expires_at),
      graceUntil: toIsoString(businessContext.grace_until),
      lastVerifiedAt: toIsoString(businessContext.last_verified_at) || issuedAt.toISOString(),
      entitlements,
    },
    license,
  };
}

function addDays(date, days) {
  const next = new Date(date.getTime());
  next.setUTCDate(next.getUTCDate() + Math.max(0, Number(days) || 0));
  return next;
}

function normalizeText(value) {
  if (value == null) {
    return null;
  }
  const normalized = String(value).trim();
  return normalized || null;
}

function normalizeCurrency(value) {
  const normalized = normalizeText(value);
  if (!normalized || normalized.length > 12 || /[<>{}"'`\\]/.test(normalized)) {
    return null;
  }
  return normalized;
}

function displayCurrencyForCountry(countryCode) {
  const normalized = String(countryCode || '').trim().toUpperCase();
  if (normalized === 'KE') return 'KSh';
  if (normalized === 'TZ') return 'TSh';
  if (normalized === 'UG') return 'USh';
  if (normalized === 'RW') return 'FRw';
  if (normalized === 'ZA') return 'R';
  if (normalized === 'GB') return '\u00A3';
  return '$';
}

function toIsoString(value) {
  if (!value) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

module.exports = {
  activateBusinessAccess,
  parseBearerToken,
  refreshBusinessAccess,
  resolveBusinessAccess,
};
