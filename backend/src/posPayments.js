const crypto = require('crypto');

const { config } = require('./config');
const { query, withTransaction } = require('./db');
const {
  loadPaymentGateway,
  normalizeCountryCode,
} = require('./subscriptionPlans');

const SECRET_MASK_PREFIX = '********';

let schemaReady = false;

async function ensurePosPaymentSchema(target = query) {
  const canUseCache = target === query;
  if (canUseCache && schemaReady) {
    return;
  }

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS business_payment_gateways (
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      provider text NOT NULL,
      display_name text,
      is_active boolean NOT NULL DEFAULT false,
      public_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      secret_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      PRIMARY KEY (business_id, provider)
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS pos_payment_requests (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      sale_id text,
      provider text NOT NULL,
      country_code text NOT NULL DEFAULT 'KE',
      currency text NOT NULL DEFAULT 'KES',
      amount_minor integer NOT NULL,
      phone_number text,
      status text NOT NULL DEFAULT 'pending',
      external_reference text,
      checkout_request_id text,
      metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      completed_at timestamptz
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_pos_payment_requests_business
      ON pos_payment_requests(business_id, created_at DESC)
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_pos_payment_requests_checkout
      ON pos_payment_requests(checkout_request_id)
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE sales
      ADD COLUMN IF NOT EXISTS payment_provider text,
      ADD COLUMN IF NOT EXISTS payment_reference text,
      ADD COLUMN IF NOT EXISTS payment_status text,
      ADD COLUMN IF NOT EXISTS payment_metadata_json jsonb
    `,
  );

  if (canUseCache) {
    schemaReady = true;
  }
}

async function loadBusinessPaymentGateway(
  businessId,
  provider,
  { includeSecrets = false } = {},
  target = query,
) {
  await ensurePosPaymentSchema(target);
  const cleanProvider = normalizeProvider(provider);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM business_payment_gateways
    WHERE business_id = $1 AND provider = $2
    LIMIT 1
    `,
    [businessId, cleanProvider],
  );
  return normalizeBusinessPaymentGatewayRow(
    result.rows[0] || {
      business_id: businessId,
      provider: cleanProvider,
      display_name: providerLabel(cleanProvider),
      is_active: false,
      public_config_json: '{}',
      secret_config_json: '{}',
    },
    { includeSecrets },
  );
}

async function saveBusinessPaymentGateway(
  businessId,
  provider,
  input = {},
  target = query,
) {
  await ensurePosPaymentSchema(target);
  const cleanProvider = normalizeProvider(provider || input.provider);
  const existing = await loadBusinessPaymentGateway(
    businessId,
    cleanProvider,
    { includeSecrets: true },
    target,
  );
  const normalized = normalizeBusinessPaymentGatewayInput(input, {
    ...existing,
    provider: cleanProvider,
  });

  const result = await runQuery(
    target,
    `
    INSERT INTO business_payment_gateways (
      business_id,
      provider,
      display_name,
      is_active,
      public_config_json,
      secret_config_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, NOW(), NOW())
    ON CONFLICT (business_id, provider) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        is_active = EXCLUDED.is_active,
        public_config_json = EXCLUDED.public_config_json,
        secret_config_json = EXCLUDED.secret_config_json,
        updated_at = NOW()
    RETURNING *
    `,
    [
      businessId,
      cleanProvider,
      normalized.displayName,
      normalized.isActive,
      JSON.stringify(normalized.publicConfig),
      JSON.stringify(normalized.secretConfig),
    ],
  );

  return normalizeBusinessPaymentGatewayRow(result.rows[0], {
    includeSecrets: false,
  });
}

async function loadPosMpesaConfig(businessContext) {
  await ensurePosPaymentSchema();
  const countryCode = normalizeCountryCode(businessContext?.countryCode || 'GLOBAL');
  const platformGateway = await loadPaymentGateway('mpesa');
  const businessGateway = await loadBusinessPaymentGateway(
    businessContext?.businessId,
    'mpesa',
    { includeSecrets: true },
  );
  const countries = platformGateway?.countries || [];
  const platformActive =
    Boolean(platformGateway?.isActive) &&
    (countries.includes(countryCode) || countries.includes('GLOBAL'));
  const mpesaConfig = resolveMpesaGatewayConfig(platformGateway, businessGateway);
  const merchantConfigured =
    Boolean(businessGateway?.isActive) &&
    Boolean(mpesaConfig.shortcode) &&
    Boolean(mpesaConfig.consumerKey) &&
    Boolean(mpesaConfig.consumerSecret) &&
    Boolean(mpesaConfig.passkey) &&
    Boolean(mpesaConfig.callbackUrl);
  const active = platformActive && merchantConfigured;
  return {
    active,
    provider: 'mpesa',
    providerLabel: businessGateway?.displayName || platformGateway?.displayName || 'M-Pesa',
    countryCode,
    currency: countryCode === 'KE' ? 'KES' : 'KES',
    merchantConfigured,
    merchantShortcode: businessGateway?.publicConfig?.shortcode || null,
    message: active
      ? null
      : platformActive
        ? 'Add this business M-Pesa merchant credentials in Payment Methods.'
        : 'M-Pesa POS checkout is not active for this business country.',
  };
}

async function createMpesaPosCheckout({
  businessContext,
  amountMinor,
  phoneNumber,
  saleId = null,
  metadata = {},
}) {
  await ensurePosPaymentSchema();
  const cleanAmount = Math.round(Number(amountMinor || 0));
  if (cleanAmount <= 0) {
    throw createError(400, 'amountMinor must be greater than zero');
  }
  if (!normalizeText(phoneNumber)) {
    throw createError(400, 'phoneNumber is required for M-Pesa checkout');
  }

  const configStatus = await loadPosMpesaConfig(businessContext);
  if (!configStatus.active) {
    throw createError(400, configStatus.message);
  }

  const platformGateway = await loadPaymentGateway('mpesa');
  const businessGateway = await loadBusinessPaymentGateway(
    businessContext.businessId,
    'mpesa',
    { includeSecrets: true },
  );
  const paymentId = crypto.randomUUID();
  const externalReference = `pos_${paymentId.slice(0, 12)}`;
  const now = new Date().toISOString();
  const payment = await withTransaction(async (client) => {
    const result = await client.query(
      `
      INSERT INTO pos_payment_requests (
        id,
        business_id,
        sale_id,
        provider,
        country_code,
        currency,
        amount_minor,
        phone_number,
        status,
        external_reference,
        metadata_json,
        created_at,
        updated_at
      )
      VALUES ($1, $2, $3, 'mpesa', $4, $5, $6, $7, 'pending', $8, $9::jsonb, $10, $10)
      RETURNING *
      `,
      [
        paymentId,
        businessContext.businessId,
        normalizeText(saleId),
        configStatus.countryCode,
        configStatus.currency,
        cleanAmount,
        normalizeText(phoneNumber),
        externalReference,
        JSON.stringify(metadata || {}),
        now,
      ],
    );
    return normalizePosPaymentRow(result.rows[0]);
  });

  const mpesa = await initiateMpesaPosCheckout(
    payment,
    platformGateway,
    businessGateway,
  );
  return { ...payment, mpesa };
}

async function loadPosPayment({ businessId, paymentId }) {
  await ensurePosPaymentSchema();
  const result = await query(
    `
    SELECT *
    FROM pos_payment_requests
    WHERE id = $1 AND business_id = $2
    LIMIT 1
    `,
    [paymentId, businessId],
  );
  return result.rows[0] ? normalizePosPaymentRow(result.rows[0]) : null;
}

async function linkPosPaymentToSale({ businessId, paymentId, saleId }) {
  await ensurePosPaymentSchema();
  return withTransaction(async (client) => {
    const result = await client.query(
      `
      SELECT *
      FROM pos_payment_requests
      WHERE id = $1 AND business_id = $2
      FOR UPDATE
      `,
      [paymentId, businessId],
    );
    const payment = result.rows[0];
    if (!payment) {
      throw createError(404, 'Payment was not found');
    }
    if (payment.status !== 'paid') {
      throw createError(400, 'Payment is not confirmed yet');
    }
    await client.query(
      `
      UPDATE pos_payment_requests
      SET sale_id = $3,
          updated_at = NOW()
      WHERE id = $1 AND business_id = $2
      `,
      [paymentId, businessId, saleId],
    );
    await client.query(
      `
      UPDATE sales
      SET payment_provider = 'mpesa',
          payment_reference = COALESCE($3, $4, $1),
          payment_status = 'paid',
          payment_metadata_json = $5::jsonb,
          updated_at = NOW()
      WHERE id = $2 AND business_id = $6
      `,
      [
        paymentId,
        saleId,
        readMpesaReceipt(payment.metadata_json),
        payment.external_reference || null,
        JSON.stringify(payment.metadata_json || {}),
        businessId,
      ],
    );
    const updated = await client.query(
      `
      SELECT *
      FROM pos_payment_requests
      WHERE id = $1 AND business_id = $2
      LIMIT 1
      `,
      [paymentId, businessId],
    );
    return normalizePosPaymentRow(updated.rows[0]);
  });
}

async function handlePosMpesaCallback({
  checkoutRequestId,
  resultCode,
  resultDescription,
  metadata,
}) {
  await ensurePosPaymentSchema();
  return withTransaction(async (client) => {
    const paymentResult = await client.query(
      `
      SELECT *
      FROM pos_payment_requests
      WHERE checkout_request_id = $1
      FOR UPDATE
      `,
      [checkoutRequestId],
    );
    const payment = paymentResult.rows[0];
    if (!payment) {
      return false;
    }
    const status = Number(resultCode) === 0 ? 'paid' : 'failed';
    const nextMetadata = {
      resultCode,
      resultDescription,
      metadata,
    };
    await client.query(
      `
      UPDATE pos_payment_requests
      SET status = $2,
          metadata_json = metadata_json || $3::jsonb,
          completed_at = CASE WHEN $2 = 'paid' THEN NOW() ELSE completed_at END,
          updated_at = NOW()
      WHERE id = $1
      `,
      [payment.id, status, JSON.stringify(nextMetadata)],
    );

    if (status === 'paid' && payment.sale_id) {
      await client.query(
        `
        UPDATE sales
        SET payment_provider = 'mpesa',
            payment_reference = COALESCE($3, payment_reference, $1),
            payment_status = 'paid',
            payment_metadata_json = COALESCE(payment_metadata_json, '{}'::jsonb) || $4::jsonb,
            updated_at = NOW()
        WHERE id = $2 AND business_id = $5
        `,
        [
          payment.id,
          payment.sale_id,
          metadata?.MpesaReceiptNumber || metadata?.mpesaReceiptNumber || null,
          JSON.stringify(nextMetadata),
          payment.business_id,
        ],
      );
    }
    return true;
  });
}

async function initiateMpesaPosCheckout(payment, platformGateway, businessGateway) {
  const mpesaConfig = resolveMpesaGatewayConfig(platformGateway, businessGateway);
  if (
    !mpesaConfig.consumerKey ||
    !mpesaConfig.consumerSecret ||
    !mpesaConfig.shortcode ||
    !mpesaConfig.passkey ||
    !mpesaConfig.callbackUrl
  ) {
    await query(
      `
      UPDATE pos_payment_requests
      SET status = 'pending_configuration',
          updated_at = NOW()
      WHERE id = $1
      `,
      [payment.id],
    );
    return {
      status: 'configuration_required',
      message: 'M-Pesa credentials are not configured for this business.',
    };
  }

  const token = await getMpesaAccessToken(mpesaConfig);
  const timestamp = formatMpesaTimestamp(new Date());
  const password = Buffer.from(
    `${mpesaConfig.shortcode}${mpesaConfig.passkey}${timestamp}`,
  ).toString('base64');
  const phoneNumber = normalizeMpesaPhone(payment.phoneNumber);
  const amount = Math.max(1, Math.ceil(payment.amountMinor / 100));
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(
    `${mpesaConfig.baseUrl.replace(/\/$/, '')}/mpesa/stkpush/v1/processrequest`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        BusinessShortCode: mpesaConfig.shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: mpesaConfig.transactionType,
        Amount: amount,
        PartyA: phoneNumber,
        PartyB: mpesaConfig.shortcode,
        PhoneNumber: phoneNumber,
        CallBackURL: mpesaConfig.callbackUrl,
        AccountReference: mpesaConfig.accountReference || payment.externalReference,
        TransactionDesc: 'Velora POS sale',
      }),
    },
  );
  const body = await readMaybeJson(response);
  if (!response.ok || body.ResponseCode !== '0') {
    await query(
      `
      UPDATE pos_payment_requests
      SET status = 'failed',
          metadata_json = metadata_json || $2::jsonb,
          updated_at = NOW()
      WHERE id = $1
      `,
      [payment.id, JSON.stringify(body || {})],
    );
    throw createError(
      response.ok ? 502 : response.status,
      body.errorMessage || body.ResponseDescription || 'M-Pesa checkout failed',
    );
  }

  await query(
    `
    UPDATE pos_payment_requests
    SET checkout_request_id = $2,
        metadata_json = metadata_json || $3::jsonb,
        updated_at = NOW()
    WHERE id = $1
    `,
    [
      payment.id,
      body.CheckoutRequestID || null,
      JSON.stringify(body || {}),
    ],
  );

  return {
    status: 'stk_sent',
    merchantRequestId: body.MerchantRequestID || null,
    checkoutRequestId: body.CheckoutRequestID || null,
    responseDescription: body.ResponseDescription || '',
  };
}

async function getMpesaAccessToken(mpesaConfig) {
  const fetch = (await import('node-fetch')).default;
  const credentials = Buffer.from(
    `${mpesaConfig.consumerKey}:${mpesaConfig.consumerSecret}`,
  ).toString('base64');
  const response = await fetch(
    `${mpesaConfig.baseUrl.replace(/\/$/, '')}/oauth/v1/generate?grant_type=client_credentials`,
    {
      headers: {
        Authorization: `Basic ${credentials}`,
      },
    },
  );
  const body = await readMaybeJson(response);
  if (!response.ok || !body.access_token) {
    throw createError(response.ok ? 502 : response.status, 'M-Pesa auth failed');
  }
  return body.access_token;
}

function resolveMpesaGatewayConfig(platformGateway, businessGateway) {
  const platformPublicConfig = platformGateway?.publicConfig || {};
  const businessPublicConfig = businessGateway?.publicConfig || {};
  const businessSecretConfig = businessGateway?.secretConfig || {};
  return {
    baseUrl:
      businessPublicConfig.baseUrl ||
      platformPublicConfig.baseUrl ||
      config.mpesaBaseUrl,
    shortcode: businessPublicConfig.shortcode || '',
    callbackUrl:
      businessPublicConfig.callbackUrl ||
      platformPublicConfig.callbackUrl ||
      config.mpesaCallbackUrl,
    transactionType:
      businessPublicConfig.transactionType || 'CustomerPayBillOnline',
    accountReference: businessPublicConfig.accountReference || '',
    consumerKey: businessSecretConfig.consumerKey || '',
    consumerSecret: businessSecretConfig.consumerSecret || '',
    passkey: businessSecretConfig.passkey || '',
  };
}

function normalizeBusinessPaymentGatewayInput(input, existing = {}) {
  const raw = input && typeof input === 'object' ? input : {};
  return {
    provider: normalizeProvider(raw.provider ?? existing.provider),
    displayName:
      normalizeText(raw.displayName ?? raw.display_name) ||
      existing.displayName ||
      providerLabel(existing.provider),
    isActive:
      raw.isActive == null && raw.is_active == null
        ? existing.isActive ?? false
        : Boolean(raw.isActive ?? raw.is_active),
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

function normalizeBusinessPaymentGatewayRow(row, { includeSecrets = false } = {}) {
  const secretConfig = parseJson(row.secret_config_json, {});
  return {
    businessId: row.business_id,
    provider: normalizeProvider(row.provider),
    displayName: row.display_name || providerLabel(row.provider),
    isActive: Boolean(row.is_active),
    publicConfig: parseJson(row.public_config_json, {}),
    secretConfig: includeSecrets ? secretConfig : maskConfigObject(secretConfig),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeConfigObject(input, existing = {}, { secret = false } = {}) {
  const raw = input && typeof input === 'object' && !Array.isArray(input)
    ? input
    : {};
  const normalized = { ...existing };
  for (const [key, value] of Object.entries(raw)) {
    const cleanKey = normalizeText(key);
    if (!cleanKey) continue;
    const text = value == null ? '' : String(value).trim();
    if (secret && (!text || text.startsWith(SECRET_MASK_PREFIX))) {
      continue;
    }
    if (!secret && !text) {
      delete normalized[cleanKey];
      continue;
    }
    normalized[cleanKey] = text;
  }
  return normalized;
}

function maskConfigObject(configObject) {
  const masked = {};
  for (const [key, value] of Object.entries(configObject || {})) {
    const text = value == null ? '' : String(value);
    masked[key] = text ? `${SECRET_MASK_PREFIX}${text.slice(-4)}` : '';
  }
  return masked;
}

function normalizeProvider(value) {
  return normalizeText(value)?.toLowerCase().replace(/[^a-z0-9_]+/g, '_') || 'mpesa';
}

function providerLabel(provider) {
  switch (normalizeProvider(provider)) {
    case 'mpesa':
      return 'M-Pesa';
    default:
      return normalizeProvider(provider).replace(/_/g, ' ');
  }
}

function normalizePosPaymentRow(row) {
  const metadata = parseJson(row.metadata_json, {});
  return {
    id: row.id,
    businessId: row.business_id,
    saleId: row.sale_id,
    provider: row.provider,
    countryCode: row.country_code,
    currency: row.currency,
    amountMinor: Number(row.amount_minor || 0),
    phoneNumber: row.phone_number,
    status: row.status,
    externalReference: row.external_reference,
    checkoutRequestId: row.checkout_request_id,
    receiptNumber: readMpesaReceipt(metadata),
    metadata,
    createdAt: toIsoString(row.created_at),
    updatedAt: toIsoString(row.updated_at),
    completedAt: toIsoString(row.completed_at),
  };
}

function readMpesaReceipt(metadata) {
  const raw = parseJson(metadata, {});
  return (
    raw?.metadata?.MpesaReceiptNumber ||
    raw?.metadata?.mpesaReceiptNumber ||
    raw?.MpesaReceiptNumber ||
    raw?.mpesaReceiptNumber ||
    null
  );
}

function normalizeMpesaPhone(value) {
  const digits = String(value || '').replace(/\D/g, '');
  if (digits.startsWith('254') && digits.length === 12) {
    return digits;
  }
  if (digits.startsWith('0') && digits.length === 10) {
    return `254${digits.slice(1)}`;
  }
  if (digits.length === 9) {
    return `254${digits}`;
  }
  return digits;
}

function formatMpesaTimestamp(date) {
  const pad = (value) => String(value).padStart(2, '0');
  return [
    date.getUTCFullYear(),
    pad(date.getUTCMonth() + 1),
    pad(date.getUTCDate()),
    pad(date.getUTCHours()),
    pad(date.getUTCMinutes()),
    pad(date.getUTCSeconds()),
  ].join('');
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

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch (_) {
    return fallback;
  }
}

function normalizeText(value) {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized || null;
}

function toIsoString(value) {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
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
  ensurePosPaymentSchema,
  loadBusinessPaymentGateway,
  saveBusinessPaymentGateway,
  loadPosMpesaConfig,
  createMpesaPosCheckout,
  loadPosPayment,
  linkPosPaymentToSale,
  handlePosMpesaCallback,
  resolveMpesaGatewayConfig,
};
