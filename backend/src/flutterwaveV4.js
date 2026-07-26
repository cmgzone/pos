const crypto = require('node:crypto');

const DEFAULT_OAUTH_URL =
  'https://idp.flutterwave.com/realms/flutterwave/protocol/openid-connect/token';
const DEFAULT_SANDBOX_API_BASE_URL = 'https://developersandbox-api.flutterwave.com';
const DEFAULT_PRODUCTION_API_BASE_URL = 'https://f4bexperience.flutterwave.com';
const DEFAULT_REQUEST_TIMEOUT_MS = 15_000;

const ALLOWED_API_BASE_URLS = new Set([
  DEFAULT_SANDBOX_API_BASE_URL,
  DEFAULT_PRODUCTION_API_BASE_URL,
]);

class FlutterwaveV4ApiError extends Error {
  constructor(message, { httpStatus = 0, code = '', type = '' } = {}) {
    super(message);
    this.name = 'FlutterwaveV4ApiError';
    this.httpStatus = Number(httpStatus) || 0;
    this.code = cleanText(code);
    this.type = cleanText(type);
  }
}

async function requestFlutterwaveV4AccessToken({
  clientId,
  clientSecret,
  oauthUrl = DEFAULT_OAUTH_URL,
  timeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
  fetchImpl,
}) {
  const cleanClientId = requiredText(
    clientId,
    'Flutterwave v4 Client ID is required.',
  );
  const cleanClientSecret = requiredText(
    clientSecret,
    'Flutterwave v4 Client Secret is required.',
  );
  const cleanOauthUrl = cleanText(oauthUrl);
  if (cleanOauthUrl !== DEFAULT_OAUTH_URL) {
    throw new Error('Flutterwave v4 OAuth URL must use the official identity host.');
  }

  const fetch = fetchImpl || (await import('node-fetch')).default;
  const response = await fetchWithTimeout(
    fetch,
    cleanOauthUrl,
    {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        client_id: cleanClientId,
        client_secret: cleanClientSecret,
        grant_type: 'client_credentials',
      }).toString(),
    },
    timeoutMs,
  );
  const body = await readMaybeJson(response);
  if (!response.ok || !body.access_token) {
    throw buildApiError(
      body,
      response.status,
      'Flutterwave v4 authentication failed.',
    );
  }

  return {
    accessToken: String(body.access_token),
    expiresIn: positiveNumberOrZero(body.expires_in),
    tokenType: cleanText(body.token_type) || 'Bearer',
  };
}

function resolveFlutterwaveV4ApiBaseUrl({
  environment = 'sandbox',
  apiBaseUrl,
} = {}) {
  const explicitUrl = cleanText(apiBaseUrl).replace(/\/+$/, '');
  if (explicitUrl) {
    if (!ALLOWED_API_BASE_URLS.has(explicitUrl)) {
      throw new Error(
        'Flutterwave v4 API URL must use the official sandbox or production host.',
      );
    }
    return explicitUrl;
  }

  const cleanEnvironment = cleanText(environment).toLowerCase();
  if (['sandbox', 'test', 'testing'].includes(cleanEnvironment)) {
    return DEFAULT_SANDBOX_API_BASE_URL;
  }
  if (['production', 'live'].includes(cleanEnvironment)) {
    return DEFAULT_PRODUCTION_API_BASE_URL;
  }
  throw new Error('Flutterwave v4 environment must be sandbox/test or production/live.');
}

function generateFlutterwaveV4Nonce() {
  return crypto.randomBytes(9).toString('base64url');
}

function encryptFlutterwaveV4Value({
  value,
  encryptionKey,
  nonce = generateFlutterwaveV4Nonce(),
}) {
  const plainText = requiredText(
    value,
    'A value is required for Flutterwave v4 encryption.',
  );
  const cleanNonce = validateNonce(nonce);
  const key = decodeEncryptionKey(encryptionKey);
  const cipher = crypto.createCipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(cleanNonce, 'utf8'),
  );
  const encrypted = Buffer.concat([
    cipher.update(plainText, 'utf8'),
    cipher.final(),
    cipher.getAuthTag(),
  ]);
  return encrypted.toString('base64');
}

function encryptFlutterwaveV4Card({
  card,
  encryptionKey,
  nonce = generateFlutterwaveV4Nonce(),
}) {
  const source = requirePlainObject(card, 'Card details are required.');
  const cleanNonce = validateNonce(nonce);
  const cardNumber = cleanText(source.number || source.cardNumber).replace(
    /[\s-]+/g,
    '',
  );
  const expiryMonth = cleanText(source.expiryMonth || source.expiry_month).padStart(
    2,
    '0',
  );
  const expiryYear = cleanText(source.expiryYear || source.expiry_year);
  const cvv = cleanText(source.cvv);

  if (!/^\d{12,19}$/.test(cardNumber)) {
    throw new Error('A valid card number is required.');
  }
  if (!/^(0[1-9]|1[0-2])$/.test(expiryMonth)) {
    throw new Error('A valid card expiry month is required.');
  }
  if (!/^(\d{2}|\d{4})$/.test(expiryYear)) {
    throw new Error('A valid card expiry year is required.');
  }
  if (!/^\d{3,4}$/.test(cvv)) {
    throw new Error('A valid card CVV is required.');
  }

  return {
    nonce: cleanNonce,
    encrypted_card_number: encryptFlutterwaveV4Value({
      value: cardNumber,
      encryptionKey,
      nonce: cleanNonce,
    }),
    encrypted_expiry_month: encryptFlutterwaveV4Value({
      value: expiryMonth,
      encryptionKey,
      nonce: cleanNonce,
    }),
    encrypted_expiry_year: encryptFlutterwaveV4Value({
      value: expiryYear,
      encryptionKey,
      nonce: cleanNonce,
    }),
    encrypted_cvv: encryptFlutterwaveV4Value({
      value: cvv,
      encryptionKey,
      nonce: cleanNonce,
    }),
  };
}

function createFlutterwaveV4PinAuthorization({
  pin,
  encryptionKey,
  nonce = generateFlutterwaveV4Nonce(),
}) {
  const cleanNonce = validateNonce(nonce);
  const cleanPin = cleanText(pin);
  if (!/^\d{4,6}$/.test(cleanPin)) {
    throw new Error('A valid card PIN is required.');
  }
  return {
    type: 'pin',
    pin: {
      nonce: cleanNonce,
      encrypted_pin: encryptFlutterwaveV4Value({
        value: cleanPin,
        encryptionKey,
        nonce: cleanNonce,
      }),
    },
  };
}

async function createFlutterwaveV4Customer({
  accessToken,
  customer,
  environment,
  apiBaseUrl,
  traceId,
  idempotencyKey,
  timeoutMs,
  fetchImpl,
}) {
  const source = requirePlainObject(customer, 'Customer details are required.');
  const email = requiredText(source.email, 'Customer email is required.');
  const payload = { email };
  copyObjectField(payload, 'name', source.name);
  copyObjectField(payload, 'phone', source.phone);
  copyObjectField(payload, 'address', source.address);
  copyObjectField(payload, 'meta', source.meta);

  const result = await requestFlutterwaveV4Api({
    accessToken,
    environment,
    apiBaseUrl,
    path: '/customers',
    method: 'POST',
    body: payload,
    traceId,
    idempotencyKey,
    timeoutMs,
    fetchImpl,
  });
  return normalizeEnvelope(result, normalizeCustomer);
}

async function createFlutterwaveV4CardPaymentMethod({
  accessToken,
  encryptionKey,
  card,
  customerId,
  meta,
  nonce,
  environment,
  apiBaseUrl,
  traceId,
  idempotencyKey,
  timeoutMs,
  fetchImpl,
}) {
  const encryptedCard = encryptFlutterwaveV4Card({
    card,
    encryptionKey,
    nonce,
  });
  const payload = {
    type: 'card',
    card: encryptedCard,
  };
  if (cleanText(customerId)) payload.customer_id = cleanText(customerId);
  copyObjectField(payload, 'meta', meta);

  const result = await requestFlutterwaveV4Api({
    accessToken,
    environment,
    apiBaseUrl,
    path: '/payment-methods',
    method: 'POST',
    body: payload,
    traceId,
    idempotencyKey,
    timeoutMs,
    fetchImpl,
  });
  return normalizeEnvelope(result, normalizePaymentMethod);
}

async function createFlutterwaveV4Charge(options) {
  return createFlutterwaveV4PaymentEntity({
    ...options,
    entityName: 'charge',
    path: '/charges',
  });
}

async function createFlutterwaveV4Order(options) {
  return createFlutterwaveV4PaymentEntity({
    ...options,
    entityName: 'order',
    path: '/orders',
  });
}

async function createFlutterwaveV4PaymentEntity({
  accessToken,
  payment,
  charge,
  order,
  entityName,
  path,
  environment,
  apiBaseUrl,
  traceId,
  idempotencyKey,
  scenarioKey,
  timeoutMs,
  fetchImpl,
}) {
  const source = requirePlainObject(
    payment || charge || order,
    `Flutterwave v4 ${entityName} details are required.`,
  );
  const payload = buildPaymentEntityPayload(source, entityName);
  const result = await requestFlutterwaveV4Api({
    accessToken,
    environment,
    apiBaseUrl,
    path,
    method: 'POST',
    body: payload,
    traceId,
    idempotencyKey,
    scenarioKey,
    timeoutMs,
    fetchImpl,
  });
  return normalizeEnvelope(result, (data) =>
    normalizePaymentEntity(data, entityName),
  );
}

async function updateFlutterwaveV4ChargeAuthorization({
  accessToken,
  chargeId,
  authorization,
  meta,
  environment,
  apiBaseUrl,
  traceId,
  idempotencyKey,
  scenarioKey,
  timeoutMs,
  fetchImpl,
}) {
  const cleanChargeId = requiredText(
    chargeId,
    'Flutterwave v4 charge ID is required.',
  );
  const payload = {
    authorization: requirePlainObject(
      authorization,
      'Flutterwave v4 charge authorization is required.',
    ),
  };
  copyObjectField(payload, 'meta', meta);

  const result = await requestFlutterwaveV4Api({
    accessToken,
    environment,
    apiBaseUrl,
    path: `/charges/${encodeURIComponent(cleanChargeId)}`,
    method: 'PUT',
    body: payload,
    traceId,
    idempotencyKey,
    scenarioKey,
    timeoutMs,
    fetchImpl,
  });
  return normalizeEnvelope(result, (data) =>
    normalizePaymentEntity(data, 'charge'),
  );
}

async function retrieveFlutterwaveV4Charge({
  accessToken,
  chargeId,
  environment,
  apiBaseUrl,
  traceId,
  timeoutMs,
  fetchImpl,
}) {
  const cleanChargeId = requiredText(
    chargeId,
    'Flutterwave v4 charge ID is required.',
  );
  const result = await requestFlutterwaveV4Api({
    accessToken,
    environment,
    apiBaseUrl,
    path: `/charges/${encodeURIComponent(cleanChargeId)}`,
    method: 'GET',
    traceId,
    timeoutMs,
    fetchImpl,
  });
  return normalizeEnvelope(result, (data) =>
    normalizePaymentEntity(data, 'charge'),
  );
}

async function requestFlutterwaveV4Api({
  accessToken,
  environment,
  apiBaseUrl,
  path,
  method = 'GET',
  body,
  traceId,
  idempotencyKey,
  scenarioKey,
  timeoutMs = DEFAULT_REQUEST_TIMEOUT_MS,
  fetchImpl,
}) {
  const token = requiredText(
    accessToken,
    'Flutterwave v4 access token is required.',
  );
  const baseUrl = resolveFlutterwaveV4ApiBaseUrl({ environment, apiBaseUrl });
  const cleanMethod = cleanText(method).toUpperCase() || 'GET';
  const cleanPath = cleanText(path);
  if (!cleanPath.startsWith('/') || cleanPath.startsWith('//')) {
    throw new Error('Flutterwave v4 API path must be relative.');
  }

  const requestTraceId = validateRequestId(
    traceId || crypto.randomUUID(),
    'trace ID',
  );
  const mutation = !['GET', 'HEAD'].includes(cleanMethod);
  const requestIdempotencyKey = mutation
    ? validateRequestId(
        idempotencyKey || `req-${crypto.randomUUID()}`,
        'idempotency key',
      )
    : '';
  const cleanScenarioKey = cleanText(scenarioKey);
  if (cleanScenarioKey.length > 1000) {
    throw new Error('Flutterwave v4 scenario key cannot exceed 1000 characters.');
  }

  const headers = {
    Accept: 'application/json',
    Authorization: `Bearer ${token}`,
    'X-Trace-Id': requestTraceId,
  };
  if (mutation) {
    headers['Content-Type'] = 'application/json';
    headers['X-Idempotency-Key'] = requestIdempotencyKey;
  }
  if (cleanScenarioKey) headers['X-Scenario-Key'] = cleanScenarioKey;

  const fetch = fetchImpl || (await import('node-fetch')).default;
  const response = await fetchWithTimeout(
    fetch,
    `${baseUrl}${cleanPath}`,
    {
      method: cleanMethod,
      headers,
      ...(mutation ? { body: JSON.stringify(body || {}) } : {}),
    },
    timeoutMs,
  );
  const responseBody = await readMaybeJson(response);
  if (!response.ok || cleanText(responseBody.status).toLowerCase() === 'failed') {
    throw buildApiError(
      responseBody,
      response.status,
      'Flutterwave v4 request failed.',
    );
  }

  return {
    body: responseBody,
    traceId: requestTraceId,
    idempotencyKey: requestIdempotencyKey,
  };
}

function buildPaymentEntityPayload(source, entityName) {
  const amount = Number(source.amount);
  if (!Number.isFinite(amount) || amount < 0.01) {
    throw new Error(`Flutterwave v4 ${entityName} amount must be at least 0.01.`);
  }
  const currency = requiredText(
    source.currency,
    `Flutterwave v4 ${entityName} currency is required.`,
  ).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) {
    throw new Error(`Flutterwave v4 ${entityName} currency must be an ISO code.`);
  }
  const reference = requiredText(
    source.reference,
    `Flutterwave v4 ${entityName} reference is required.`,
  );
  if (!/^[a-zA-Z0-9-]{6,42}$/.test(reference)) {
    throw new Error(
      `Flutterwave v4 ${entityName} reference must be 6-42 letters, numbers, or hyphens.`,
    );
  }

  const payload = {
    amount,
    currency,
    reference,
    customer_id: requiredText(
      source.customerId || source.customer_id,
      `Flutterwave v4 ${entityName} customer ID is required.`,
    ),
    payment_method_id: requiredText(
      source.paymentMethodId || source.payment_method_id,
      `Flutterwave v4 ${entityName} payment method ID is required.`,
    ),
  };

  const redirectUrl = cleanText(source.redirectUrl || source.redirect_url);
  if (redirectUrl) {
    if (!isHttpsUrl(redirectUrl)) {
      throw new Error(
        `Flutterwave v4 ${entityName} redirect URL must be a valid HTTPS URL.`,
      );
    }
    payload.redirect_url = redirectUrl;
  }
  copyObjectField(payload, 'meta', source.meta);
  copyObjectField(payload, 'authorization', source.authorization);

  const merchantVatAmount = source.merchantVatAmount ?? source.merchant_vat_amount;
  if (merchantVatAmount !== undefined && merchantVatAmount !== null) {
    const amountValue = Number(merchantVatAmount);
    if (!Number.isFinite(amountValue) || amountValue < 0) {
      throw new Error('Flutterwave v4 merchant VAT amount must not be negative.');
    }
    payload.merchant_vat_amount = amountValue;
  }
  if (entityName === 'charge') {
    if (source.recurring !== undefined) payload.recurring = source.recurring === true;
    const orderId = cleanText(source.orderId || source.order_id);
    if (orderId) payload.order_id = orderId;
  }
  return payload;
}

function normalizeEnvelope(result, normalizeData) {
  const body = result.body || {};
  return {
    status: cleanText(body.status) || 'success',
    message: cleanText(body.message),
    data: normalizeData(body.data || {}),
    traceId: result.traceId,
    ...(result.idempotencyKey
      ? { idempotencyKey: result.idempotencyKey }
      : {}),
  };
}

function normalizeCustomer(data) {
  return {
    id: cleanText(data.id),
    email: cleanText(data.email),
    name: isPlainObject(data.name) ? { ...data.name } : null,
    phone: isPlainObject(data.phone) ? { ...data.phone } : null,
    address: isPlainObject(data.address) ? { ...data.address } : null,
    meta: isPlainObject(data.meta) ? { ...data.meta } : {},
    createdAt: cleanText(data.created_datetime || data.created_at),
  };
}

function normalizePaymentMethod(data) {
  const card = isPlainObject(data.card) ? data.card : {};
  const customer =
    isPlainObject(data.customer) ? data.customer.id : data.customer;
  return {
    id: cleanText(data.id),
    type: cleanText(data.type),
    customerId: cleanText(data.customer_id || customer),
    card:
      cleanText(data.type).toLowerCase() === 'card' || Object.keys(card).length
        ? {
            first6: cleanText(card.first6),
            last4: cleanText(card.last4),
            network: cleanText(card.network),
            expiryMonth: cleanText(card.expiry_month),
            expiryYear: cleanText(card.expiry_year),
          }
        : null,
    meta: isPlainObject(data.meta) ? { ...data.meta } : {},
    createdAt: cleanText(data.created_datetime || data.created_at),
  };
}

function normalizePaymentEntity(data, entityType) {
  const nextAction = normalizeNextAction(data.next_action);
  const customer =
    isPlainObject(data.customer) ? data.customer.id : data.customer;
  const processor = isPlainObject(data.processor_response)
    ? data.processor_response
    : isPlainObject(data.issuer_response)
      ? data.issuer_response
      : {};
  const paymentMethodSource = isPlainObject(data.payment_method_details)
    ? data.payment_method_details
    : isPlainObject(data.payment_method)
      ? data.payment_method
      : null;
  const paymentMethod = paymentMethodSource
    ? normalizePaymentMethod(paymentMethodSource)
    : null;
  return {
    entityType,
    id: cleanText(data.id),
    orderId: cleanText(data.order_id),
    status: cleanText(data.status),
    reference: cleanText(data.reference),
    amount: finiteNumberOrNull(data.amount),
    currency: cleanText(data.currency).toUpperCase(),
    customerId: cleanText(data.customer_id || customer),
    paymentMethodId:
      cleanText(data.payment_method_id) || cleanText(paymentMethod?.id),
    paymentMethod,
    recurring: data.recurring === true,
    redirectUrl:
      cleanText(data.redirect_url) || cleanText(nextAction?.redirectUrl),
    nextAction,
    processorResponse: {
      type: cleanText(processor.type),
      code: cleanText(processor.code),
      message: cleanText(processor.message),
    },
    settled: data.settled === true,
    meta: isPlainObject(data.meta) ? { ...data.meta } : {},
    createdAt: cleanText(data.created_datetime || data.created_at),
  };
}

function normalizeNextAction(value) {
  if (!isPlainObject(value)) return null;
  const redirect = isPlainObject(value.redirect_url) ? value.redirect_url : {};
  const authorization = isPlainObject(value.authorization)
    ? value.authorization
    : {};
  const instruction = isPlainObject(value.payment_instruction)
    ? value.payment_instruction
    : {};
  const additionalFields = isPlainObject(value.requires_additional_fields)
    ? value.requires_additional_fields
    : {};
  const type = cleanText(value.type);
  return {
    type,
    authorizationType:
      cleanText(authorization.type) ||
      (type.startsWith('requires_') ? type.slice('requires_'.length) : ''),
    redirectUrl: cleanText(redirect.url || value.url),
    instruction: cleanText(instruction.note || instruction.message),
    requiredFields: Array.isArray(additionalFields.fields)
      ? additionalFields.fields.map(cleanText).filter(Boolean)
      : [],
  };
}

function buildApiError(body, httpStatus, fallbackMessage) {
  const error = isPlainObject(body?.error) ? body.error : {};
  const message =
    cleanText(error.message) ||
    cleanText(body?.error_description) ||
    (typeof body?.error === 'string' ? cleanText(body.error) : '') ||
    cleanText(body?.message) ||
    fallbackMessage;
  return new FlutterwaveV4ApiError(message.slice(0, 500), {
    httpStatus,
    code: error.code || body?.code,
    type: error.type || body?.type,
  });
}

async function fetchWithTimeout(fetch, url, options, timeoutMs) {
  const duration = Number(timeoutMs);
  if (!Number.isFinite(duration) || duration < 1 || duration > 120_000) {
    throw new Error(
      'Flutterwave v4 request timeout must be between 1 and 120000 milliseconds.',
    );
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), duration);
  if (typeof timer.unref === 'function') timer.unref();
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } catch (error) {
    if (controller.signal.aborted) {
      throw new FlutterwaveV4ApiError('Flutterwave v4 request timed out.');
    }
    throw error;
  } finally {
    clearTimeout(timer);
  }
}

async function readMaybeJson(response) {
  if (response && typeof response.text === 'function') {
    try {
      const text = await response.text();
      if (!text) return {};
      return JSON.parse(text);
    } catch (_) {
      return {};
    }
  }
  try {
    return await response.json();
  } catch (_) {
    return {};
  }
}

function decodeEncryptionKey(value) {
  const encoded = requiredText(
    value,
    'Flutterwave v4 Encryption Key is required.',
  ).replace(/\s+/g, '');
  const key = Buffer.from(encoded, 'base64');
  const normalizedInput = encoded.replace(/=+$/, '');
  const normalizedOutput = key.toString('base64').replace(/=+$/, '');
  if (key.length !== 32 || normalizedInput !== normalizedOutput) {
    throw new Error(
      'Flutterwave v4 Encryption Key must be a valid base64-encoded 256-bit key.',
    );
  }
  return key;
}

function validateNonce(value) {
  const nonce = requiredText(value, 'Flutterwave v4 encryption nonce is required.');
  if (Buffer.byteLength(nonce, 'utf8') !== 12) {
    throw new Error('Flutterwave v4 encryption nonce must be exactly 12 bytes.');
  }
  return nonce;
}

function validateRequestId(value, label) {
  const id = requiredText(value, `Flutterwave v4 ${label} is required.`);
  if (id.length < 12 || id.length > 255) {
    throw new Error(
      `Flutterwave v4 ${label} must be between 12 and 255 characters.`,
    );
  }
  return id;
}

function copyObjectField(target, key, value) {
  if (value === undefined || value === null) return;
  target[key] = { ...requirePlainObject(value, `${key} must be an object.`) };
}

function requirePlainObject(value, message) {
  if (!isPlainObject(value)) throw new Error(message);
  return value;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function requiredText(value, message) {
  const text = cleanText(value);
  if (!text) throw new Error(message);
  return text;
}

function cleanText(value) {
  return String(value ?? '').trim();
}

function finiteNumberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function positiveNumberOrZero(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : 0;
}

function isHttpsUrl(value) {
  try {
    return new URL(String(value || '')).protocol === 'https:';
  } catch (_) {
    return false;
  }
}

module.exports = {
  DEFAULT_OAUTH_URL,
  DEFAULT_SANDBOX_API_BASE_URL,
  DEFAULT_PRODUCTION_API_BASE_URL,
  DEFAULT_REQUEST_TIMEOUT_MS,
  FlutterwaveV4ApiError,
  resolveFlutterwaveV4ApiBaseUrl,
  generateFlutterwaveV4Nonce,
  encryptFlutterwaveV4Value,
  encryptFlutterwaveV4Card,
  createFlutterwaveV4PinAuthorization,
  requestFlutterwaveV4AccessToken,
  requestFlutterwaveV4Api,
  createFlutterwaveV4Customer,
  createFlutterwaveV4CardPaymentMethod,
  createFlutterwaveV4Charge,
  createFlutterwaveV4Order,
  updateFlutterwaveV4ChargeAuthorization,
  retrieveFlutterwaveV4Charge,
};
