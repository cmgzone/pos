const crypto = require('crypto');

const { query } = require('./db');
const { isHttpsUrl } = require('./subscriptionPlans');

const SECRET_MASK_PREFIX = '********';
const DEFAULT_SUBMIT_PATH = '/invoices';

let schemaReady = false;

async function ensureEtimsSchema(target = query) {
  const canUseCache = target === query;
  if (canUseCache && schemaReady) {
    return;
  }

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS platform_etims_config (
      id integer PRIMARY KEY DEFAULT 1,
      provider_name text NOT NULL DEFAULT 'KRA eTIMS OSCU/VSCU',
      is_active boolean NOT NULL DEFAULT false,
      base_url text NOT NULL DEFAULT '',
      submit_path text NOT NULL DEFAULT '${DEFAULT_SUBMIT_PATH}',
      public_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      secret_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      CONSTRAINT platform_etims_config_single_row CHECK (id = 1)
    )
    `,
  );

  await runQuery(
    target,
    `
    INSERT INTO platform_etims_config (id)
    VALUES (1)
    ON CONFLICT (id) DO NOTHING
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS business_etims_settings (
      business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
      is_active boolean NOT NULL DEFAULT false,
      taxpayer_pin text NOT NULL DEFAULT '',
      vat_number text NOT NULL DEFAULT '',
      solution_type text NOT NULL DEFAULT 'OSCU',
      branch_code text NOT NULL DEFAULT '',
      device_serial text NOT NULL DEFAULT '',
      auto_submit boolean NOT NULL DEFAULT true,
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
    CREATE TABLE IF NOT EXISTS etims_submissions (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      sale_id text NOT NULL,
      status text NOT NULL DEFAULT 'pending',
      provider_name text NOT NULL DEFAULT 'KRA eTIMS OSCU/VSCU',
      invoice_number text,
      control_unit_invoice_number text,
      control_unit_serial text,
      verification_url text,
      qr_code text,
      request_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      response_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      error_message text,
      submitted_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_etims_submissions_business_sale
      ON etims_submissions(business_id, sale_id, created_at DESC)
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE sales
      ADD COLUMN IF NOT EXISTS etims_status text,
      ADD COLUMN IF NOT EXISTS etims_invoice_number text,
      ADD COLUMN IF NOT EXISTS etims_control_unit_invoice_number text,
      ADD COLUMN IF NOT EXISTS etims_control_unit_serial text,
      ADD COLUMN IF NOT EXISTS etims_verification_url text,
      ADD COLUMN IF NOT EXISTS etims_qr_code text,
      ADD COLUMN IF NOT EXISTS etims_submitted_at timestamptz,
      ADD COLUMN IF NOT EXISTS etims_error text,
      ADD COLUMN IF NOT EXISTS etims_response_json jsonb
    `,
  );

  if (canUseCache) {
    schemaReady = true;
  }
}

async function loadPlatformEtimsConfig(
  { includeSecrets = false } = {},
  target = query,
) {
  await ensureEtimsSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM platform_etims_config
    WHERE id = 1
    LIMIT 1
    `,
  );
  return normalizePlatformConfigRow(result.rows[0] || {}, { includeSecrets });
}

async function savePlatformEtimsConfig(input = {}, target = query) {
  await ensureEtimsSchema(target);
  const existing = await loadPlatformEtimsConfig({ includeSecrets: true }, target);
  const normalized = normalizePlatformConfigInput(input, existing);
  validatePlatformEtimsConfig(normalized);

  const result = await runQuery(
    target,
    `
    INSERT INTO platform_etims_config (
      id,
      provider_name,
      is_active,
      base_url,
      submit_path,
      public_config_json,
      secret_config_json,
      created_at,
      updated_at
    )
    VALUES (1, $1, $2, $3, $4, $5::jsonb, $6::jsonb, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE
    SET provider_name = EXCLUDED.provider_name,
        is_active = EXCLUDED.is_active,
        base_url = EXCLUDED.base_url,
        submit_path = EXCLUDED.submit_path,
        public_config_json = EXCLUDED.public_config_json,
        secret_config_json = EXCLUDED.secret_config_json,
        updated_at = NOW()
    RETURNING *
    `,
    [
      normalized.providerName,
      normalized.isActive,
      normalized.baseUrl,
      normalized.submitPath,
      JSON.stringify(normalized.publicConfig),
      JSON.stringify(normalized.secretConfig),
    ],
  );

  return normalizePlatformConfigRow(result.rows[0], { includeSecrets: false });
}

async function getBusinessEtimsSettings(
  businessId,
  { includeSecrets = false } = {},
  target = query,
) {
  await ensureEtimsSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM business_etims_settings
    WHERE business_id = $1
    LIMIT 1
    `,
    [businessId],
  );
  return normalizeBusinessSettingsRow(
    result.rows[0] || {
      business_id: businessId,
      is_active: false,
      taxpayer_pin: '',
      vat_number: '',
      solution_type: 'OSCU',
      branch_code: '',
      device_serial: '',
      auto_submit: true,
      public_config_json: '{}',
      secret_config_json: '{}',
    },
    { includeSecrets },
  );
}

async function saveBusinessEtimsSettings(
  businessId,
  input = {},
  target = query,
) {
  await ensureEtimsSchema(target);
  const existing = await getBusinessEtimsSettings(
    businessId,
    { includeSecrets: true },
    target,
  );
  const normalized = normalizeBusinessSettingsInput(input, existing);
  validateBusinessEtimsSettings(normalized);

  const result = await runQuery(
    target,
    `
    INSERT INTO business_etims_settings (
      business_id,
      is_active,
      taxpayer_pin,
      vat_number,
      solution_type,
      branch_code,
      device_serial,
      auto_submit,
      public_config_json,
      secret_config_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb, NOW(), NOW())
    ON CONFLICT (business_id) DO UPDATE
    SET is_active = EXCLUDED.is_active,
        taxpayer_pin = EXCLUDED.taxpayer_pin,
        vat_number = EXCLUDED.vat_number,
        solution_type = EXCLUDED.solution_type,
        branch_code = EXCLUDED.branch_code,
        device_serial = EXCLUDED.device_serial,
        auto_submit = EXCLUDED.auto_submit,
        public_config_json = EXCLUDED.public_config_json,
        secret_config_json = EXCLUDED.secret_config_json,
        updated_at = NOW()
    RETURNING *
    `,
    [
      businessId,
      normalized.isActive,
      normalized.taxpayerPin,
      normalized.vatNumber,
      normalized.solutionType,
      normalized.branchCode,
      normalized.deviceSerial,
      normalized.autoSubmit,
      JSON.stringify(normalized.publicConfig),
      JSON.stringify(normalized.secretConfig),
    ],
  );

  return normalizeBusinessSettingsRow(result.rows[0], {
    includeSecrets: false,
  });
}

async function submitEtimsSale({
  businessContext,
  sale,
  items = [],
  userId,
  target = query,
}) {
  await ensureEtimsSchema(target);
  const businessId = businessContext?.businessId;
  const saleId = normalizeText(sale?.id || sale?.saleId);
  if (!businessId) {
    throw new Error('businessId is required');
  }
  if (!saleId) {
    throw new Error('sale.id is required');
  }

  const platformConfig = await loadPlatformEtimsConfig(
    { includeSecrets: true },
    target,
  );
  const businessSettings = await getBusinessEtimsSettings(
    businessId,
    { includeSecrets: true },
    target,
  );
  const payload = buildEtimsPayload({
    businessContext,
    businessSettings,
    sale: { ...sale, id: saleId },
    items,
    userId,
  });
  const submissionId = crypto.randomUUID();
  await insertSubmission(target, {
    id: submissionId,
    businessId,
    saleId,
    status: 'pending',
    providerName: platformConfig.providerName,
    request: payload,
  });

  const configurationErrors = [
    ...platformEtimsReadinessErrors(platformConfig),
    ...businessEtimsReadinessErrors(businessSettings),
  ];
  if (configurationErrors.length > 0) {
    const errorMessage = configurationErrors.join(' ');
    const result = {
      id: submissionId,
      saleId,
      status: 'pending_configuration',
      errorMessage,
      providerName: platformConfig.providerName,
    };
    await finalizeSubmission(target, {
      ...result,
      response: { configurationErrors },
    });
    await updateSaleEtimsFields(target, businessId, saleId, result);
    return result;
  }

  try {
    const response = await postEtimsPayload(platformConfig, payload);
    const mapped = mapEtimsResponse(response.body || {});
    const status = response.ok && !mapped.failed ? 'submitted' : 'failed';
    const errorMessage = status === 'failed'
      ? mapped.errorMessage || `eTIMS provider returned HTTP ${response.statusCode}`
      : null;
    const result = {
      id: submissionId,
      saleId,
      status,
      providerName: platformConfig.providerName,
      invoiceNumber: mapped.invoiceNumber || payload.invoice.invoiceNumber,
      controlUnitInvoiceNumber: mapped.controlUnitInvoiceNumber,
      controlUnitSerial: mapped.controlUnitSerial,
      verificationUrl: mapped.verificationUrl,
      qrCode: mapped.qrCode,
      submittedAt: status === 'submitted' ? new Date().toISOString() : null,
      errorMessage,
      response: response.body || {},
    };
    await finalizeSubmission(target, result);
    await updateSaleEtimsFields(target, businessId, saleId, result);
    return result;
  } catch (error) {
    const result = {
      id: submissionId,
      saleId,
      status: 'failed',
      providerName: platformConfig.providerName,
      errorMessage: error.message || 'eTIMS submission failed',
      response: {},
    };
    await finalizeSubmission(target, result);
    await updateSaleEtimsFields(target, businessId, saleId, result);
    return result;
  }
}

async function listEtimsSubmissions(
  businessId,
  { limit = 50 } = {},
  target = query,
) {
  await ensureEtimsSchema(target);
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM etims_submissions
    WHERE business_id = $1
    ORDER BY created_at DESC
    LIMIT $2
    `,
    [businessId, safeLimit],
  );
  return result.rows.map(normalizeSubmissionRow);
}

function platformEtimsReadinessErrors(config) {
  const errors = [];
  if (!config?.isActive) {
    errors.push('Platform eTIMS connector is not active.');
  }
  if (!config?.baseUrl || !isHttpsUrl(config.baseUrl)) {
    errors.push('Add a valid HTTPS OSCU/VSCU provider URL.');
  }
  if (!config?.submitPath) {
    errors.push('Add the invoice submission path.');
  }
  return errors;
}

function businessEtimsReadinessErrors(settings) {
  const errors = [];
  if (!settings?.isActive) {
    errors.push('Business eTIMS is not active.');
  }
  if (!settings?.taxpayerPin) {
    errors.push('Add the business KRA PIN.');
  }
  if (!settings?.deviceSerial) {
    errors.push('Add the OSCU/VSCU device serial.');
  }
  return errors;
}

function buildEtimsPayload({
  businessContext,
  businessSettings,
  sale,
  items,
  userId,
}) {
  const currency =
    normalizeText(sale.currency) ||
    normalizeText(businessContext?.currency) ||
    'KES';
  const total = toMoney(sale.totalAmount ?? sale.total_amount);
  const tax = toMoney(sale.tax);
  const discount = toMoney(sale.discount);
  const subtotal = toMoney(sale.subtotal ?? total - tax + discount);
  const invoiceNumber =
    normalizeText(sale.invoiceNumber || sale.invoice_number) ||
    normalizeText(sale.id).slice(0, 12).toUpperCase();

  return {
    integration: {
      source: 'piki_pos',
      solutionType: businessSettings.solutionType,
      submittedBy: normalizeText(userId) || null,
    },
    taxpayer: {
      pin: businessSettings.taxpayerPin,
      vatNumber: businessSettings.vatNumber || null,
      branchCode: businessSettings.branchCode || null,
      deviceSerial: businessSettings.deviceSerial || null,
    },
    invoice: {
      saleId: normalizeText(sale.id),
      invoiceNumber,
      invoiceType: sale.refundForSaleId || sale.refund_for_sale_id
        ? 'credit_note'
        : 'sale',
      currency,
      issuedAt:
        normalizeText(sale.createdAt || sale.created_at) ||
        new Date().toISOString(),
      paymentType: normalizeText(sale.paymentType || sale.payment_type) || null,
      customerName: normalizeText(sale.customerName || sale.customer_name) || null,
      customerPin: normalizeText(sale.customerPin || sale.customer_pin) || null,
      customerPhone: normalizeText(sale.customerPhone || sale.customer_phone) || null,
      paymentReference:
        normalizeText(sale.paymentReference || sale.payment_reference) || null,
    },
    totals: {
      subtotal,
      tax,
      discount,
      total,
    },
    items: items.map((item, index) => {
      const quantity = toMoney(item.quantity, 1);
      const unitPrice = toMoney(item.unitPrice ?? item.unit_price);
      const lineTotal = toMoney(item.lineTotal ?? item.line_total ?? quantity * unitPrice);
      return {
        lineNumber: index + 1,
        productId: normalizeText(item.productId || item.product_id) || null,
        description:
          normalizeText(
            item.productName ||
              item.product_name ||
              item.serviceName ||
              item.service_name,
          ) || 'Item',
        quantity,
        unit: normalizeText(item.unit) || 'pcs',
        unitPrice,
        lineTotal,
        taxAmount: toMoney(item.taxAmount ?? item.tax_amount),
      };
    }),
  };
}

async function postEtimsPayload(platformConfig, payload) {
  const fetch = (await import('node-fetch')).default;
  const url = `${platformConfig.baseUrl.replace(/\/+$/, '')}/${platformConfig.submitPath.replace(/^\/+/, '')}`;
  const timeoutMs = Number(platformConfig.publicConfig?.timeoutMs || 20000);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: buildEtimsHeaders(platformConfig),
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    const body = await readMaybeJson(response);
    return {
      ok: response.ok,
      statusCode: response.status,
      body,
    };
  } finally {
    clearTimeout(timer);
  }
}

function buildEtimsHeaders(platformConfig) {
  const publicConfig = platformConfig.publicConfig || {};
  const secretConfig = platformConfig.secretConfig || {};
  const headers = {
    'Content-Type': 'application/json',
    'User-Agent': 'Piki POS eTIMS Connector',
  };
  const apiKey = normalizeText(secretConfig.apiKey || secretConfig.accessToken);
  if (apiKey) {
    const headerName = normalizeText(publicConfig.authHeaderName) || 'Authorization';
    const prefix = normalizeText(publicConfig.authHeaderPrefix);
    headers[headerName] = prefix === ''
      ? apiKey
      : `${prefix || 'Bearer'} ${apiKey}`;
  }
  const extraHeaders = parseJsonValue(publicConfig.headers, {});
  for (const [key, value] of Object.entries(extraHeaders)) {
    if (normalizeText(key) && value != null) {
      headers[key] = String(value);
    }
  }
  return headers;
}

function mapEtimsResponse(body) {
  const data = body?.data && typeof body.data === 'object' ? body.data : body;
  const statusText = normalizeText(data?.status || data?.result || data?.code);
  const failed = /fail|error|reject/i.test(statusText || '');
  return {
    failed,
    invoiceNumber:
      normalizeText(data?.invoiceNumber) ||
      normalizeText(data?.etimsInvoiceNumber) ||
      normalizeText(data?.receiptNumber),
    controlUnitInvoiceNumber:
      normalizeText(data?.controlUnitInvoiceNumber) ||
      normalizeText(data?.cuInvoiceNumber) ||
      normalizeText(data?.cuInvoiceNo),
    controlUnitSerial:
      normalizeText(data?.controlUnitSerial) ||
      normalizeText(data?.controlUnitSerialNumber) ||
      normalizeText(data?.deviceSerial),
    verificationUrl:
      normalizeText(data?.verificationUrl) ||
      normalizeText(data?.verifyUrl) ||
      normalizeText(data?.invoiceUrl),
    qrCode:
      normalizeText(data?.qrCode) ||
      normalizeText(data?.qrCodeUrl) ||
      normalizeText(data?.qr),
    errorMessage:
      normalizeText(data?.errorMessage) ||
      normalizeText(data?.message) ||
      normalizeText(body?.error),
  };
}

async function insertSubmission(target, input) {
  await runQuery(
    target,
    `
    INSERT INTO etims_submissions (
      id,
      business_id,
      sale_id,
      status,
      provider_name,
      request_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5, $6::jsonb, NOW(), NOW())
    `,
    [
      input.id,
      input.businessId,
      input.saleId,
      input.status,
      input.providerName,
      JSON.stringify(input.request || {}),
    ],
  );
}

async function finalizeSubmission(target, result) {
  await runQuery(
    target,
    `
    UPDATE etims_submissions
    SET status = $2,
        invoice_number = $3,
        control_unit_invoice_number = $4,
        control_unit_serial = $5,
        verification_url = $6,
        qr_code = $7,
        response_json = $8::jsonb,
        error_message = $9,
        submitted_at = $10,
        updated_at = NOW()
    WHERE id = $1
    `,
    [
      result.id,
      result.status,
      result.invoiceNumber || null,
      result.controlUnitInvoiceNumber || null,
      result.controlUnitSerial || null,
      result.verificationUrl || null,
      result.qrCode || null,
      JSON.stringify(result.response || {}),
      result.errorMessage || null,
      result.submittedAt || null,
    ],
  );
}

async function updateSaleEtimsFields(target, businessId, saleId, result) {
  await runQuery(
    target,
    `
    UPDATE sales
    SET etims_status = $3,
        etims_invoice_number = $4,
        etims_control_unit_invoice_number = $5,
        etims_control_unit_serial = $6,
        etims_verification_url = $7,
        etims_qr_code = $8,
        etims_submitted_at = $9,
        etims_error = $10,
        etims_response_json = $11::jsonb,
        updated_at = NOW(),
        server_revision = nextval('sync_revision_seq')
    WHERE business_id = $1 AND id = $2
    `,
    [
      businessId,
      saleId,
      result.status,
      result.invoiceNumber || null,
      result.controlUnitInvoiceNumber || null,
      result.controlUnitSerial || null,
      result.verificationUrl || null,
      result.qrCode || null,
      result.submittedAt || null,
      result.errorMessage || null,
      JSON.stringify(result.response || {}),
    ],
  );
}

function normalizePlatformConfigInput(input, fallback = {}) {
  return {
    providerName:
      normalizeText(input.providerName || input.provider_name) ||
      fallback.providerName ||
      'KRA eTIMS OSCU/VSCU',
    isActive: input.isActive ?? input.is_active ?? fallback.isActive ?? false,
    baseUrl:
      normalizeUrl(input.baseUrl || input.base_url) ||
      fallback.baseUrl ||
      '',
    submitPath:
      normalizePath(input.submitPath || input.submit_path) ||
      fallback.submitPath ||
      DEFAULT_SUBMIT_PATH,
    publicConfig: {
      ...(fallback.publicConfig || {}),
      ...parseJsonValue(input.publicConfig ?? input.public_config, {}),
    },
    secretConfig: mergeSecretConfig(
      fallback.secretConfig || {},
      parseJsonValue(input.secretConfig ?? input.secret_config, {}),
    ),
  };
}

function normalizeBusinessSettingsInput(input, fallback = {}) {
  return {
    isActive: input.isActive ?? input.is_active ?? fallback.isActive ?? false,
    taxpayerPin:
      normalizeText(input.taxpayerPin || input.taxpayer_pin) ||
      fallback.taxpayerPin ||
      '',
    vatNumber:
      normalizeText(input.vatNumber || input.vat_number) ||
      fallback.vatNumber ||
      '',
    solutionType:
      normalizeSolutionType(input.solutionType || input.solution_type) ||
      fallback.solutionType ||
      'OSCU',
    branchCode:
      normalizeText(input.branchCode || input.branch_code) ||
      fallback.branchCode ||
      '',
    deviceSerial:
      normalizeText(input.deviceSerial || input.device_serial) ||
      fallback.deviceSerial ||
      '',
    autoSubmit:
      input.autoSubmit ?? input.auto_submit ?? fallback.autoSubmit ?? true,
    publicConfig: {
      ...(fallback.publicConfig || {}),
      ...parseJsonValue(input.publicConfig ?? input.public_config, {}),
    },
    secretConfig: mergeSecretConfig(
      fallback.secretConfig || {},
      parseJsonValue(input.secretConfig ?? input.secret_config, {}),
    ),
  };
}

function normalizePlatformConfigRow(row, { includeSecrets = false } = {}) {
  const publicConfig = parseJsonValue(row.public_config_json, {});
  const secretConfig = parseJsonValue(row.secret_config_json, {});
  return {
    providerName: row.provider_name || 'KRA eTIMS OSCU/VSCU',
    isActive: row.is_active === true,
    baseUrl: row.base_url || '',
    submitPath: row.submit_path || DEFAULT_SUBMIT_PATH,
    publicConfig,
    secretConfig: includeSecrets ? secretConfig : maskConfigObject(secretConfig),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeBusinessSettingsRow(row, { includeSecrets = false } = {}) {
  const publicConfig = parseJsonValue(row.public_config_json, {});
  const secretConfig = parseJsonValue(row.secret_config_json, {});
  return {
    businessId: row.business_id,
    isActive: row.is_active === true,
    taxpayerPin: row.taxpayer_pin || '',
    vatNumber: row.vat_number || '',
    solutionType: row.solution_type || 'OSCU',
    branchCode: row.branch_code || '',
    deviceSerial: row.device_serial || '',
    autoSubmit: row.auto_submit !== false,
    publicConfig,
    secretConfig: includeSecrets ? secretConfig : maskConfigObject(secretConfig),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeSubmissionRow(row) {
  return {
    id: row.id,
    businessId: row.business_id,
    saleId: row.sale_id,
    status: row.status,
    providerName: row.provider_name,
    invoiceNumber: row.invoice_number,
    controlUnitInvoiceNumber: row.control_unit_invoice_number,
    controlUnitSerial: row.control_unit_serial,
    verificationUrl: row.verification_url,
    qrCode: row.qr_code,
    errorMessage: row.error_message,
    submittedAt: toIsoString(row.submitted_at),
    createdAt: toIsoString(row.created_at),
    updatedAt: toIsoString(row.updated_at),
  };
}

function validatePlatformEtimsConfig(input) {
  if (!input.isActive) {
    return;
  }
  if (!input.baseUrl || !isHttpsUrl(input.baseUrl)) {
    throw createError(400, 'KRA/eTIMS provider URL must be a valid HTTPS URL.');
  }
  if (!input.submitPath) {
    throw createError(400, 'KRA/eTIMS submit path is required.');
  }
}

function validateBusinessEtimsSettings(input) {
  if (!input.isActive) {
    return;
  }
  if (!input.taxpayerPin) {
    throw createError(400, 'KRA PIN is required before enabling eTIMS.');
  }
  if (!input.deviceSerial) {
    throw createError(
      400,
      'OSCU/VSCU device serial is required before enabling eTIMS.',
    );
  }
}

function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function readMaybeJson(response) {
  const text = await response.text();
  if (!text) {
    return {};
  }
  try {
    return JSON.parse(text);
  } catch (_) {
    return { message: text };
  }
}

function runQuery(target, text, params = []) {
  if (typeof target === 'function') {
    return target(text, params);
  }
  return target.query(text, params);
}

function normalizeText(value) {
  const text = value == null ? '' : String(value).trim();
  return text;
}

function normalizeUrl(value) {
  const text = normalizeText(value);
  return text.replace(/\/+$/, '');
}

function normalizePath(value) {
  const text = normalizeText(value);
  if (!text) {
    return '';
  }
  return text.startsWith('/') ? text : `/${text}`;
}

function normalizeSolutionType(value) {
  const text = normalizeText(value).toUpperCase();
  return ['OSCU', 'VSCU'].includes(text) ? text : '';
}

function toMoney(value, fallback = 0) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }
  return Math.round(number * 100) / 100;
}

function parseJsonValue(value, fallback) {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
        ? parsed
        : fallback;
    } catch (_) {
      return fallback;
    }
  }
  return fallback;
}

function maskConfigObject(configObject) {
  const masked = {};
  for (const [key, value] of Object.entries(configObject || {})) {
    if (value == null || String(value).trim() === '') {
      masked[key] = '';
      continue;
    }
    masked[key] = `${SECRET_MASK_PREFIX}${String(value).slice(-4)}`;
  }
  return masked;
}

function mergeSecretConfig(fallback, input) {
  const merged = { ...(fallback || {}) };
  for (const [key, value] of Object.entries(input || {})) {
    if (typeof value === 'string' && value.startsWith(SECRET_MASK_PREFIX)) {
      continue;
    }
    merged[key] = value;
  }
  return merged;
}

function toIsoString(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.toISOString();
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

module.exports = {
  ensureEtimsSchema,
  loadPlatformEtimsConfig,
  savePlatformEtimsConfig,
  getBusinessEtimsSettings,
  saveBusinessEtimsSettings,
  submitEtimsSale,
  listEtimsSubmissions,
  platformEtimsReadinessErrors,
  businessEtimsReadinessErrors,
};
