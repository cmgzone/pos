const crypto = require('crypto');

const { config } = require('./config');
const { query, withTransaction } = require('./db');
const { issueLicense, resolveSubscriptionState } = require('./licenseTokens');

async function activateBusinessAccess({
  deviceId,
  businessName,
  ownerName,
  ownerEmail,
  deviceName,
}) {
  const normalizedDeviceId = normalizeText(deviceId);
  const normalizedBusinessName = normalizeText(businessName);

  if (!normalizedDeviceId) {
    throw new Error('deviceId is required');
  }
  if (!normalizedBusinessName) {
    throw new Error('businessName is required');
  }

  return withTransaction(async (client) => {
    const now = new Date();
    const existingContext = await loadBusinessContextByDevice(client, normalizedDeviceId);

    let businessId = existingContext?.business_id || null;
    if (!businessId) {
      businessId = crypto.randomUUID();
      await client.query(
        `
        INSERT INTO businesses (id, name, owner_name, owner_email, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $5)
        `,
        [
          businessId,
          normalizedBusinessName,
          normalizeText(ownerName),
          normalizeText(ownerEmail),
          now.toISOString(),
        ],
      );

      const expiresAt = addDays(now, config.subscriptionTrialDays);
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
          updated_at = $5
        WHERE id = $1
        `,
        [
          businessId,
          normalizedBusinessName,
          normalizeText(ownerName),
          normalizeText(ownerEmail),
          now.toISOString(),
        ],
      );

      await ensureSubscriptionRow(client, businessId, now);
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

  const result = await query(
    `
    SELECT
      b.id AS business_id,
      b.name AS business_name,
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
  return {
    businessId: context.business_id,
    businessName: context.business_name,
    deviceId: context.device_id,
    plan: context.plan,
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

async function ensureSubscriptionRow(client, businessId, now) {
  const result = await client.query(
    'SELECT business_id FROM subscriptions WHERE business_id = $1 LIMIT 1',
    [businessId],
  );
  if (result.rows.length) {
    return;
  }

  const expiresAt = addDays(now, config.subscriptionTrialDays);
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

function buildAccessResponse({
  deviceId,
  accessToken,
  businessContext,
  issuedAt,
}) {
  if (!businessContext) {
    throw new Error('Business access context could not be resolved');
  }

  const license = issueLicense({
    businessId: businessContext.business_id,
    businessName: businessContext.business_name,
    deviceId,
    subscription: businessContext,
    issuedAt,
  });

  return {
    business: {
      id: businessContext.business_id,
      name: businessContext.business_name,
    },
    accessToken,
    subscription: {
      plan: String(businessContext.plan || 'trial'),
      status: resolveSubscriptionState(businessContext, issuedAt).status,
      expiresAt: toIsoString(businessContext.expires_at),
      graceUntil: toIsoString(businessContext.grace_until),
      lastVerifiedAt: toIsoString(businessContext.last_verified_at) || issuedAt.toISOString(),
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
