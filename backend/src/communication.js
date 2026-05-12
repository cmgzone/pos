const crypto = require('crypto');

const { query } = require('./db');
const { normalizeCountryCode } = require('./subscriptionPlans');

const SECRET_MASK_PREFIX = '********';

let schemaReady = false;

async function ensureCommunicationSchema(target = query) {
  const canUseCache = target === query;
  if (canUseCache && schemaReady) {
    return;
  }

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS platform_message_gateways (
      provider text PRIMARY KEY,
      display_name text NOT NULL,
      is_active boolean NOT NULL DEFAULT false,
      countries_json jsonb NOT NULL DEFAULT '[]'::jsonb,
      public_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      secret_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS business_communication_settings (
      business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
      whatsapp_number text,
      sms_sender_id text,
      allow_api_send boolean NOT NULL DEFAULT true,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS message_send_logs (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      user_id text,
      channel text NOT NULL,
      mode text NOT NULL DEFAULT 'api',
      provider text,
      recipient text NOT NULL,
      body text NOT NULL,
      status text NOT NULL DEFAULT 'pending',
      error_message text,
      metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_message_send_logs_business
      ON message_send_logs(business_id, created_at DESC)
    `,
  );

  await seedDefaultMessageGateways(target);

  if (canUseCache) {
    schemaReady = true;
  }
}

async function listMessageGateways({ includeSecrets = false } = {}, target = query) {
  await ensureCommunicationSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM platform_message_gateways
    ORDER BY CASE provider
      WHEN 'whatsapp' THEN 0
      WHEN 'africas_talking' THEN 1
      ELSE 2
    END, provider ASC
    `,
  );
  return result.rows.map((row) => normalizeGatewayRow(row, { includeSecrets }));
}

async function loadMessageGateway(provider, target = query, { includeSecrets = true } = {}) {
  await ensureCommunicationSchema(target);
  const cleanProvider = normalizeProvider(provider);
  const result = await runQuery(
    target,
    'SELECT * FROM platform_message_gateways WHERE provider = $1 LIMIT 1',
    [cleanProvider],
  );
  return result.rows[0]
    ? normalizeGatewayRow(result.rows[0], { includeSecrets })
    : null;
}

async function saveMessageGateway(provider, input = {}, target = query) {
  await ensureCommunicationSchema(target);
  const cleanProvider = normalizeProvider(provider || input.provider);
  const existing = await loadMessageGateway(cleanProvider, target, {
    includeSecrets: true,
  });
  const normalized = normalizeGatewayInput(input, {
    ...(existing || {}),
    provider: cleanProvider,
  });

  const result = await runQuery(
    target,
    `
    INSERT INTO platform_message_gateways (
      provider,
      display_name,
      is_active,
      countries_json,
      public_config_json,
      secret_config_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6::jsonb, NOW(), NOW())
    ON CONFLICT (provider) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        is_active = EXCLUDED.is_active,
        countries_json = EXCLUDED.countries_json,
        public_config_json = EXCLUDED.public_config_json,
        secret_config_json = EXCLUDED.secret_config_json,
        updated_at = NOW()
    RETURNING *
    `,
    [
      cleanProvider,
      normalized.displayName,
      normalized.isActive,
      JSON.stringify(normalized.countries),
      JSON.stringify(normalized.publicConfig),
      JSON.stringify(normalized.secretConfig),
    ],
  );

  return normalizeGatewayRow(result.rows[0], { includeSecrets: false });
}

async function getBusinessCommunicationSettings(businessId, target = query) {
  await ensureCommunicationSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM business_communication_settings
    WHERE business_id = $1
    LIMIT 1
    `,
    [businessId],
  );
  return normalizeBusinessSettingsRow(result.rows[0] || { business_id: businessId });
}

async function saveBusinessCommunicationSettings(businessId, input = {}, target = query) {
  await ensureCommunicationSchema(target);
  const whatsappNumber = normalizeText(input.whatsappNumber ?? input.whatsapp_number);
  const smsSenderId = normalizeText(input.smsSenderId ?? input.sms_sender_id);
  const allowApiSend =
    input.allowApiSend == null && input.allow_api_send == null
      ? true
      : Boolean(input.allowApiSend ?? input.allow_api_send);
  const result = await runQuery(
    target,
    `
    INSERT INTO business_communication_settings (
      business_id,
      whatsapp_number,
      sms_sender_id,
      allow_api_send,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, NOW(), NOW())
    ON CONFLICT (business_id) DO UPDATE
    SET whatsapp_number = EXCLUDED.whatsapp_number,
        sms_sender_id = EXCLUDED.sms_sender_id,
        allow_api_send = EXCLUDED.allow_api_send,
        updated_at = NOW()
    RETURNING *
    `,
    [businessId, whatsappNumber, smsSenderId, allowApiSend],
  );
  return normalizeBusinessSettingsRow(result.rows[0]);
}

async function sendBusinessMessage({
  businessContext,
  userId,
  channel,
  recipient,
  body,
  metadata = {},
}) {
  await ensureCommunicationSchema();
  const cleanChannel = normalizeChannel(channel);
  const cleanRecipient = normalizeText(recipient);
  const cleanBody = normalizeText(body);
  if (!cleanRecipient) {
    throw createError(400, 'recipient is required');
  }
  if (!cleanBody) {
    throw createError(400, 'message body is required');
  }

  const settings = await getBusinessCommunicationSettings(
    businessContext.businessId,
  );
  if (!settings.allowApiSend) {
    throw createError(403, 'API messaging is disabled for this business');
  }

  const provider = cleanChannel === 'sms' ? 'africas_talking' : 'whatsapp';
  const gateway = await loadMessageGateway(provider);
  const countryCode = normalizeCountryCode(businessContext.countryCode || 'GLOBAL');
  if (
    !gateway ||
    !gateway.isActive ||
    (
      !(gateway.countries || []).includes(countryCode) &&
      !(gateway.countries || []).includes('GLOBAL')
    )
  ) {
    throw createError(400, `${gatewayLabel(provider)} is not active for this business country`);
  }

  const log = await insertMessageLog({
    businessId: businessContext.businessId,
    userId,
    channel: cleanChannel,
    mode: 'api',
    provider,
    recipient: cleanRecipient,
    body: cleanBody,
    status: 'pending',
    metadata,
  });

  try {
    const providerResult =
      provider === 'whatsapp'
        ? await sendWhatsAppMessage(gateway, cleanRecipient, cleanBody)
        : await sendAfricasTalkingSms(
            gateway,
            cleanRecipient,
            cleanBody,
            settings.smsSenderId,
          );
    return updateMessageLog(log.id, {
      status: 'sent',
      metadata: providerResult,
    });
  } catch (error) {
    await updateMessageLog(log.id, {
      status: 'failed',
      errorMessage: error.message,
      metadata: { error: error.message },
    });
    throw error;
  }
}

async function listMessageLogs(businessId, { limit = 50 } = {}, target = query) {
  await ensureCommunicationSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM message_send_logs
    WHERE business_id = $1
    ORDER BY created_at DESC
    LIMIT $2
    `,
    [businessId, Math.min(Math.max(Number(limit) || 50, 1), 200)],
  );
  return result.rows.map(normalizeMessageLogRow);
}

async function seedDefaultMessageGateways(target = query) {
  const defaults = [
    {
      provider: 'whatsapp',
      displayName: 'WhatsApp API',
      isActive: false,
      countries: ['GLOBAL', 'KE'],
      publicConfig: {
        baseUrl: 'https://graph.facebook.com',
        apiVersion: 'v20.0',
        phoneNumberId: '',
      },
      secretConfig: { accessToken: '' },
    },
    {
      provider: 'africas_talking',
      displayName: "Africa's Talking SMS",
      isActive: false,
      countries: ['KE'],
      publicConfig: {
        username: '',
        senderId: '',
        baseUrl: 'https://api.africastalking.com/version1/messaging',
      },
      secretConfig: { apiKey: '' },
    },
  ];
  for (const gateway of defaults) {
    await runQuery(
      target,
      `
      INSERT INTO platform_message_gateways (
        provider,
        display_name,
        is_active,
        countries_json,
        public_config_json,
        secret_config_json
      )
      VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6::jsonb)
      ON CONFLICT (provider) DO NOTHING
      `,
      [
        gateway.provider,
        gateway.displayName,
        gateway.isActive,
        JSON.stringify(gateway.countries),
        JSON.stringify(gateway.publicConfig),
        JSON.stringify(gateway.secretConfig),
      ],
    );
  }
}

async function sendWhatsAppMessage(gateway, recipient, body) {
  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const baseUrl = normalizeText(publicConfig.baseUrl) || 'https://graph.facebook.com';
  const apiVersion = normalizeText(publicConfig.apiVersion) || 'v20.0';
  const phoneNumberId = normalizeText(publicConfig.phoneNumberId);
  const accessToken = normalizeText(secretConfig.accessToken);
  if (!phoneNumberId || !accessToken) {
    throw createError(400, 'WhatsApp API credentials are not configured');
  }
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(
    `${baseUrl.replace(/\/$/, '')}/${apiVersion}/${phoneNumberId}/messages`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to: normalizePhone(recipient),
        type: 'text',
        text: { preview_url: false, body },
      }),
    },
  );
  const result = await readMaybeJson(response);
  if (!response.ok) {
    throw createError(
      response.status,
      result?.error?.message || result?.message || 'WhatsApp send failed',
    );
  }
  return result;
}

async function sendAfricasTalkingSms(gateway, recipient, body, senderId) {
  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const username = normalizeText(publicConfig.username);
  const apiKey = normalizeText(secretConfig.apiKey);
  const endpoint =
    normalizeText(publicConfig.baseUrl) ||
    'https://api.africastalking.com/version1/messaging';
  const from = normalizeText(senderId) || normalizeText(publicConfig.senderId);
  if (!username || !apiKey) {
    throw createError(400, "Africa's Talking credentials are not configured");
  }
  const form = new URLSearchParams();
  form.set('username', username);
  form.set('to', normalizePhone(recipient, { plus: true }));
  form.set('message', body);
  if (from) {
    form.set('from', from);
  }
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      apiKey,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: form.toString(),
  });
  const result = await readMaybeJson(response);
  if (!response.ok) {
    throw createError(
      response.status,
      result?.SMSMessageData?.Message || result?.message || 'SMS send failed',
    );
  }
  return result;
}

async function insertMessageLog({
  businessId,
  userId,
  channel,
  mode,
  provider,
  recipient,
  body,
  status,
  metadata,
}) {
  const id = crypto.randomUUID();
  const result = await query(
    `
    INSERT INTO message_send_logs (
      id,
      business_id,
      user_id,
      channel,
      mode,
      provider,
      recipient,
      body,
      status,
      metadata_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, NOW(), NOW())
    RETURNING *
    `,
    [
      id,
      businessId,
      normalizeText(userId),
      channel,
      mode,
      provider,
      recipient,
      body,
      status,
      JSON.stringify(metadata || {}),
    ],
  );
  return normalizeMessageLogRow(result.rows[0]);
}

async function updateMessageLog(id, { status, errorMessage = null, metadata = {} }) {
  const result = await query(
    `
    UPDATE message_send_logs
    SET status = $2,
        error_message = $3,
        metadata_json = metadata_json || $4::jsonb,
        updated_at = NOW()
    WHERE id = $1
    RETURNING *
    `,
    [id, status, errorMessage, JSON.stringify(metadata || {})],
  );
  return normalizeMessageLogRow(result.rows[0]);
}

function normalizeGatewayInput(input, existing = {}) {
  const raw = input && typeof input === 'object' ? input : {};
  return {
    provider: normalizeProvider(raw.provider ?? existing.provider),
    displayName:
      normalizeText(raw.displayName ?? raw.display_name) ||
      existing.displayName ||
      gatewayLabel(existing.provider),
    isActive:
      raw.isActive == null && raw.is_active == null
        ? existing.isActive ?? false
        : Boolean(raw.isActive ?? raw.is_active),
    countries: normalizeCountryList(raw.countries ?? existing.countries ?? []),
    publicConfig: normalizeConfigObject(
      raw.publicConfig ?? raw.public_config ?? {},
      existing.publicConfig || {},
      { secret: false },
    ),
    secretConfig: normalizeConfigObject(
      raw.secretConfig ?? raw.secret_config ?? {},
      existing.secretConfig || {},
      { secret: true },
    ),
  };
}

function normalizeGatewayRow(row, { includeSecrets = false } = {}) {
  const secretConfig = parseJson(row.secret_config_json, {});
  return {
    provider: normalizeProvider(row.provider),
    displayName: row.display_name || gatewayLabel(row.provider),
    isActive: Boolean(row.is_active),
    countries: normalizeCountryList(parseJson(row.countries_json, [])),
    publicConfig: parseJson(row.public_config_json, {}),
    secretConfig: includeSecrets ? secretConfig : maskConfigObject(secretConfig),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeBusinessSettingsRow(row) {
  return {
    businessId: row.business_id,
    whatsappNumber: row.whatsapp_number || '',
    smsSenderId: row.sms_sender_id || '',
    allowApiSend: row.allow_api_send !== false,
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeMessageLogRow(row) {
  return {
    id: row.id,
    businessId: row.business_id,
    userId: row.user_id,
    channel: row.channel,
    mode: row.mode,
    provider: row.provider,
    recipient: row.recipient,
    body: row.body,
    status: row.status,
    errorMessage: row.error_message,
    metadata: parseJson(row.metadata_json, {}),
    createdAt: toIsoString(row.created_at),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeConfigObject(input, existing = {}, { secret = false } = {}) {
  const raw = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
  const normalized = { ...existing };
  for (const [key, value] of Object.entries(raw)) {
    const cleanKey = normalizeText(key);
    if (!cleanKey) continue;
    if (secret && typeof value === 'string' && value.startsWith(SECRET_MASK_PREFIX)) {
      continue;
    }
    if (value === null || value === undefined) {
      delete normalized[cleanKey];
      continue;
    }
    normalized[cleanKey] = typeof value === 'string' ? value.trim() : value;
  }
  return normalized;
}

function maskConfigObject(input = {}) {
  return Object.fromEntries(
    Object.entries(input).map(([key, value]) => [
      key,
      value ? `${SECRET_MASK_PREFIX}${String(value).slice(-4)}` : '',
    ]),
  );
}

function normalizeCountryList(input) {
  const list = Array.isArray(input)
    ? input
    : String(input || '')
        .split(',')
        .map((item) => item.trim());
  return Array.from(
    new Set(
      list
        .map((item) => normalizeCountryCode(item))
        .filter((item) => item && item.length > 0),
    ),
  );
}

function normalizeProvider(value) {
  return normalizeText(value)?.toLowerCase().replace(/[^a-z0-9_]+/g, '_') || '';
}

function normalizeChannel(value) {
  const clean = normalizeProvider(value);
  return clean === 'sms' ? 'sms' : 'whatsapp';
}

function normalizeText(value) {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized || null;
}

function normalizePhone(value, { plus = false } = {}) {
  const raw = String(value || '').trim();
  if (!raw) return raw;
  const digits = raw.replace(/[^\d]/g, '');
  if (plus && digits.startsWith('254')) {
    return `+${digits}`;
  }
  return plus && raw.startsWith('+') ? raw : digits || raw;
}

function gatewayLabel(provider) {
  switch (normalizeProvider(provider)) {
    case 'whatsapp':
      return 'WhatsApp API';
    case 'africas_talking':
      return "Africa's Talking SMS";
    default:
      return provider || 'Message Gateway';
  }
}

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch (_) {
    return fallback;
  }
}

function toIsoString(value) {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

async function readMaybeJson(response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    return { raw: text };
  }
}

function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function runQuery(target, text, params) {
  if (typeof target === 'function') {
    return target(text, params);
  }
  return target.query(text, params);
}

module.exports = {
  ensureCommunicationSchema,
  listMessageGateways,
  loadMessageGateway,
  saveMessageGateway,
  getBusinessCommunicationSettings,
  saveBusinessCommunicationSettings,
  sendBusinessMessage,
  listMessageLogs,
};
