const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const {
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
  createFlutterwaveV4Customer,
  createFlutterwaveV4CardPaymentMethod,
  createFlutterwaveV4Charge,
  createFlutterwaveV4Order,
  updateFlutterwaveV4ChargeAuthorization,
  retrieveFlutterwaveV4Charge,
} = require('../src/flutterwaveV4');

const ENCRYPTION_KEY_BYTES = Buffer.from(
  '0123456789abcdef0123456789abcdef',
  'utf8',
);
const ENCRYPTION_KEY = ENCRYPTION_KEY_BYTES.toString('base64');
const NONCE = 'Abc123Xyz789';
const TRACE_ID = 'trace-1234567890';
const IDEMPOTENCY_KEY = 'request-1234567890';

function jsonResponse(body, { ok = true, status = ok ? 200 : 400 } = {}) {
  return {
    ok,
    status,
    async json() {
      return body;
    },
  };
}

function decrypt(encrypted, nonce = NONCE) {
  const bytes = Buffer.from(encrypted, 'base64');
  const authTag = bytes.subarray(bytes.length - 16);
  const ciphertext = bytes.subarray(0, bytes.length - 16);
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    ENCRYPTION_KEY_BYTES,
    Buffer.from(nonce, 'utf8'),
  );
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString(
    'utf8',
  );
}

test('Flutterwave v4 exchanges client credentials for an access token', async () => {
  let request;
  const result = await requestFlutterwaveV4AccessToken({
    clientId: 'client-id',
    clientSecret: 'client-secret',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse({
        access_token: 'token-value',
        expires_in: 600,
        token_type: 'Bearer',
      });
    },
  });

  assert.equal(request.url, DEFAULT_OAUTH_URL);
  assert.equal(request.options.method, 'POST');
  assert.equal(request.options.headers.Accept, 'application/json');
  assert.match(request.options.body, /client_id=client-id/);
  assert.match(request.options.body, /client_secret=client-secret/);
  assert.deepEqual(result, {
    accessToken: 'token-value',
    expiresIn: 600,
    tokenType: 'Bearer',
  });
});

test('Flutterwave v4 reports OAuth failures without exposing credentials', async () => {
  const clientSecret = 'do-not-expose-this-secret';
  await assert.rejects(
    requestFlutterwaveV4AccessToken({
      clientId: 'bad-id',
      clientSecret,
      fetchImpl: async () =>
        jsonResponse(
          { error_description: 'Invalid client credentials' },
          { ok: false, status: 401 },
        ),
    }),
    (error) => {
      assert.ok(error instanceof FlutterwaveV4ApiError);
      assert.equal(error.httpStatus, 401);
      assert.match(error.message, /Invalid client credentials/);
      assert.doesNotMatch(error.message, new RegExp(clientSecret));
      return true;
    },
  );
});

test('Flutterwave v4 rejects non-official OAuth URLs before sending credentials', async () => {
  let fetched = false;
  await assert.rejects(
    requestFlutterwaveV4AccessToken({
      clientId: 'client-id',
      clientSecret: 'client-secret',
      oauthUrl: 'https://example.com/token',
      fetchImpl: async () => {
        fetched = true;
        return jsonResponse({});
      },
    }),
    /official identity host/,
  );
  assert.equal(fetched, false);
});

test('Flutterwave v4 resolves only official sandbox and production API URLs', () => {
  assert.equal(
    resolveFlutterwaveV4ApiBaseUrl({ environment: 'test' }),
    DEFAULT_SANDBOX_API_BASE_URL,
  );
  assert.equal(
    resolveFlutterwaveV4ApiBaseUrl({ environment: 'live' }),
    DEFAULT_PRODUCTION_API_BASE_URL,
  );
  assert.equal(
    resolveFlutterwaveV4ApiBaseUrl({
      apiBaseUrl: `${DEFAULT_PRODUCTION_API_BASE_URL}/`,
    }),
    DEFAULT_PRODUCTION_API_BASE_URL,
  );
  assert.throws(
    () =>
      resolveFlutterwaveV4ApiBaseUrl({
        apiBaseUrl: 'https://example.com',
      }),
    /official sandbox or production host/,
  );
  assert.throws(
    () => resolveFlutterwaveV4ApiBaseUrl({ environment: 'unknown' }),
    /sandbox\/test or production\/live/,
  );
});

test('Flutterwave v4 AES-GCM encryption includes an authentication tag', () => {
  const encrypted = encryptFlutterwaveV4Value({
    value: '1234123412341234',
    encryptionKey: ENCRYPTION_KEY,
    nonce: NONCE,
  });

  assert.equal(decrypt(encrypted), '1234123412341234');
  assert.notEqual(encrypted, '1234123412341234');
  assert.equal(generateFlutterwaveV4Nonce().length, 12);
  assert.throws(
    () =>
      encryptFlutterwaveV4Value({
        value: 'secret',
        encryptionKey: 'not-a-key',
        nonce: NONCE,
      }),
    /base64-encoded 256-bit key/,
  );
  assert.throws(
    () =>
      encryptFlutterwaveV4Value({
        value: 'secret',
        encryptionKey: ENCRYPTION_KEY,
        nonce: 'short',
      }),
    /exactly 12 bytes/,
  );
});

test('Flutterwave v4 encrypts every sensitive card field with one nonce', () => {
  const result = encryptFlutterwaveV4Card({
    card: {
      number: '1234 1234 1234 1234',
      expiryMonth: '8',
      expiryYear: '32',
      cvv: '123',
    },
    encryptionKey: ENCRYPTION_KEY,
    nonce: NONCE,
  });

  assert.equal(result.nonce, NONCE);
  assert.equal(decrypt(result.encrypted_card_number), '1234123412341234');
  assert.equal(decrypt(result.encrypted_expiry_month), '08');
  assert.equal(decrypt(result.encrypted_expiry_year), '32');
  assert.equal(decrypt(result.encrypted_cvv), '123');
  assert.doesNotMatch(JSON.stringify(result), /1234123412341234/);
});

test('Flutterwave v4 builds encrypted PIN authorization', () => {
  const authorization = createFlutterwaveV4PinAuthorization({
    pin: '1234',
    encryptionKey: ENCRYPTION_KEY,
    nonce: NONCE,
  });

  assert.equal(authorization.type, 'pin');
  assert.equal(authorization.pin.nonce, NONCE);
  assert.equal(decrypt(authorization.pin.encrypted_pin), '1234');
  assert.doesNotMatch(JSON.stringify(authorization), /"1234"/);
});

test('Flutterwave v4 creates and normalizes a customer', async () => {
  let request;
  const result = await createFlutterwaveV4Customer({
    accessToken: 'access-token',
    customer: {
      email: 'customer@example.com',
      name: { first: 'Piki', last: 'Customer' },
      phone: { country_code: '254', number: '700000000' },
      meta: { businessId: 'business-1' },
    },
    traceId: TRACE_ID,
    idempotencyKey: IDEMPOTENCY_KEY,
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse({
        status: 'success',
        message: 'Customer created',
        data: {
          id: 'cus_123',
          email: 'customer@example.com',
          name: { first: 'Piki', last: 'Customer' },
          phone: { country_code: '254', number: '700000000' },
          meta: { businessId: 'business-1' },
          created_datetime: '2026-07-26T12:00:00Z',
        },
      });
    },
  });

  assert.equal(request.url, `${DEFAULT_SANDBOX_API_BASE_URL}/customers`);
  assert.equal(request.options.method, 'POST');
  assert.equal(request.options.headers.Authorization, 'Bearer access-token');
  assert.equal(request.options.headers['X-Trace-Id'], TRACE_ID);
  assert.equal(
    request.options.headers['X-Idempotency-Key'],
    IDEMPOTENCY_KEY,
  );
  assert.deepEqual(JSON.parse(request.options.body), {
    email: 'customer@example.com',
    name: { first: 'Piki', last: 'Customer' },
    phone: { country_code: '254', number: '700000000' },
    meta: { businessId: 'business-1' },
  });
  assert.equal(result.data.id, 'cus_123');
  assert.equal(result.data.createdAt, '2026-07-26T12:00:00Z');
  assert.equal(result.traceId, TRACE_ID);
  assert.equal(result.idempotencyKey, IDEMPOTENCY_KEY);
});

test('Flutterwave v4 sends only encrypted card values to payment methods', async () => {
  let requestBody;
  const result = await createFlutterwaveV4CardPaymentMethod({
    accessToken: 'access-token',
    encryptionKey: ENCRYPTION_KEY,
    customerId: 'cus_123',
    card: {
      number: '1234123412341234',
      expiryMonth: '08',
      expiryYear: '32',
      cvv: '123',
    },
    nonce: NONCE,
    traceId: TRACE_ID,
    idempotencyKey: IDEMPOTENCY_KEY,
    fetchImpl: async (url, options) => {
      assert.equal(url, `${DEFAULT_SANDBOX_API_BASE_URL}/payment-methods`);
      requestBody = options.body;
      return jsonResponse({
        status: 'success',
        message: 'Payment method created',
        data: {
          id: 'pmd_123',
          type: 'card',
          customer_id: 'cus_123',
          card: {
            first6: '123412',
            last4: '1234',
            network: 'mastercard',
            expiry_month: 8,
            expiry_year: 32,
          },
        },
      });
    },
  });

  const payload = JSON.parse(requestBody);
  assert.equal(payload.type, 'card');
  assert.equal(payload.customer_id, 'cus_123');
  assert.equal(payload.card.nonce, NONCE);
  assert.equal(decrypt(payload.card.encrypted_card_number), '1234123412341234');
  assert.doesNotMatch(requestBody, /1234123412341234/);
  assert.doesNotMatch(requestBody, /"cvv":"123"/);
  assert.deepEqual(result.data.card, {
    first6: '123412',
    last4: '1234',
    network: 'mastercard',
    expiryMonth: '8',
    expiryYear: '32',
  });
});

test('Flutterwave v4 creates a recurring charge and normalizes redirect action', async () => {
  let request;
  const result = await createFlutterwaveV4Charge({
    accessToken: 'access-token',
    charge: {
      amount: 15,
      currency: 'usd',
      reference: 'SUB-123456',
      customerId: 'cus_123',
      paymentMethodId: 'pmd_123',
      recurring: true,
      redirectUrl: 'https://pikipos.com/subscription/callback',
      meta: { planId: 'starter' },
    },
    environment: 'live',
    traceId: TRACE_ID,
    idempotencyKey: IDEMPOTENCY_KEY,
    scenarioKey: 'scenario:auth_redirect',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse({
        status: 'success',
        message: 'Charge created',
        data: {
          id: 'chg_123',
          amount: 15,
          currency: 'USD',
          customer_id: 'cus_123',
          payment_method_details: { id: 'pmd_123', type: 'card' },
          reference: 'SUB-123456',
          status: 'pending',
          next_action: {
            type: 'redirect_url',
            redirect_url: { url: 'https://flutterwave.example/authorize' },
          },
          processor_response: { type: 'pending', code: '02' },
        },
      });
    },
  });

  assert.equal(request.url, `${DEFAULT_PRODUCTION_API_BASE_URL}/charges`);
  assert.equal(
    request.options.headers['X-Scenario-Key'],
    'scenario:auth_redirect',
  );
  assert.deepEqual(JSON.parse(request.options.body), {
    amount: 15,
    currency: 'USD',
    reference: 'SUB-123456',
    customer_id: 'cus_123',
    payment_method_id: 'pmd_123',
    redirect_url: 'https://pikipos.com/subscription/callback',
    meta: { planId: 'starter' },
    recurring: true,
  });
  assert.equal(result.data.entityType, 'charge');
  assert.equal(result.data.id, 'chg_123');
  assert.equal(result.data.paymentMethodId, 'pmd_123');
  assert.equal(result.data.status, 'pending');
  assert.deepEqual(result.data.nextAction, {
    type: 'redirect_url',
    authorizationType: '',
    redirectUrl: 'https://flutterwave.example/authorize',
    instruction: '',
    requiredFields: [],
  });
});

test('Flutterwave v4 creates an order through the orders endpoint', async () => {
  let request;
  const result = await createFlutterwaveV4Order({
    accessToken: 'access-token',
    order: {
      amount: 75,
      currency: 'KES',
      reference: 'ORDER-123456',
      customer_id: 'cus_123',
      payment_method_id: 'pmd_123',
    },
    traceId: TRACE_ID,
    idempotencyKey: IDEMPOTENCY_KEY,
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse({
        status: 'success',
        message: 'Order created',
        data: {
          id: 'ord_123',
          amount: 75,
          currency: 'KES',
          reference: 'ORDER-123456',
          status: 'pending',
        },
      });
    },
  });

  assert.equal(request.url, `${DEFAULT_SANDBOX_API_BASE_URL}/orders`);
  assert.equal(JSON.parse(request.options.body).recurring, undefined);
  assert.equal(result.data.entityType, 'order');
  assert.equal(result.data.id, 'ord_123');
});

test('Flutterwave v4 updates a charge with OTP authorization', async () => {
  let request;
  const result = await updateFlutterwaveV4ChargeAuthorization({
    accessToken: 'access-token',
    chargeId: 'chg/unsafe',
    authorization: {
      type: 'otp',
      otp: { code: '123456' },
    },
    traceId: TRACE_ID,
    idempotencyKey: IDEMPOTENCY_KEY,
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse({
        status: 'success',
        message: 'Charge updated',
        data: {
          id: 'chg/unsafe',
          status: 'succeeded',
          reference: 'SUB-123456',
        },
      });
    },
  });

  assert.equal(
    request.url,
    `${DEFAULT_SANDBOX_API_BASE_URL}/charges/chg%2Funsafe`,
  );
  assert.equal(request.options.method, 'PUT');
  assert.deepEqual(JSON.parse(request.options.body), {
    authorization: {
      type: 'otp',
      otp: { code: '123456' },
    },
  });
  assert.equal(result.data.status, 'succeeded');
});

test('Flutterwave v4 retrieves and normalizes a charge without an idempotency key', async () => {
  let request;
  const result = await retrieveFlutterwaveV4Charge({
    accessToken: 'access-token',
    chargeId: 'chg_123',
    traceId: TRACE_ID,
    fetchImpl: async (url, options) => {
      request = { url, options };
      return jsonResponse({
        status: 'success',
        message: 'Charge fetched',
        data: {
          id: 'chg_123',
          amount: '15.00',
          currency: 'usd',
          customer: { id: 'cus_123' },
          payment_method: {
            id: 'pmd_123',
            type: 'card',
            customer: { id: 'cus_123' },
          },
          reference: 'SUB-123456',
          status: 'succeeded',
          next_action: {
            type: 'requires_additional_fields',
            requires_additional_fields: {
              fields: [
                'authorization.avs.address.line1',
                'authorization.avs.address.postal_code',
              ],
            },
          },
          issuer_response: {
            type: 'approved',
            code: '00',
            message: 'Approved',
          },
          settled: true,
        },
      });
    },
  });

  assert.equal(request.url, `${DEFAULT_SANDBOX_API_BASE_URL}/charges/chg_123`);
  assert.equal(request.options.method, 'GET');
  assert.equal(request.options.body, undefined);
  assert.equal(request.options.headers['X-Idempotency-Key'], undefined);
  assert.equal(result.idempotencyKey, undefined);
  assert.equal(result.data.amount, 15);
  assert.equal(result.data.currency, 'USD');
  assert.equal(result.data.customerId, 'cus_123');
  assert.equal(result.data.paymentMethodId, 'pmd_123');
  assert.equal(result.data.paymentMethod.customerId, 'cus_123');
  assert.deepEqual(result.data.nextAction.requiredFields, [
    'authorization.avs.address.line1',
    'authorization.avs.address.postal_code',
  ]);
  assert.equal(result.data.processorResponse.code, '00');
  assert.equal(result.data.settled, true);
});

test('Flutterwave v4 returns structured API errors without response payloads', async () => {
  await assert.rejects(
    createFlutterwaveV4Charge({
      accessToken: 'access-token',
      charge: {
        amount: 15,
        currency: 'USD',
        reference: 'SUB-123456',
        customerId: 'cus_123',
        paymentMethodId: 'pmd_123',
      },
      traceId: TRACE_ID,
      idempotencyKey: IDEMPOTENCY_KEY,
      fetchImpl: async () =>
        jsonResponse(
          {
            status: 'failed',
            error: {
              type: 'CHARGE_CREATION_FAILED',
              code: '1107500',
              message: 'Unable to create a charge',
              validation_errors: [{ field: 'card', value: 'sensitive' }],
            },
          },
          { ok: false, status: 422 },
        ),
    }),
    (error) => {
      assert.ok(error instanceof FlutterwaveV4ApiError);
      assert.equal(error.httpStatus, 422);
      assert.equal(error.code, '1107500');
      assert.equal(error.type, 'CHARGE_CREATION_FAILED');
      assert.equal(error.message, 'Unable to create a charge');
      assert.equal(error.validation_errors, undefined);
      return true;
    },
  );
});

test('Flutterwave v4 validates charge data before making a request', async () => {
  let fetched = false;
  await assert.rejects(
    createFlutterwaveV4Charge({
      accessToken: 'access-token',
      charge: {
        amount: 0,
        currency: 'USD',
        reference: 'bad',
        customerId: 'cus_123',
        paymentMethodId: 'pmd_123',
      },
      fetchImpl: async () => {
        fetched = true;
        return jsonResponse({});
      },
    }),
    /amount must be at least 0.01/,
  );
  assert.equal(fetched, false);
});

test('Flutterwave v4 aborts requests that exceed the configured timeout', async () => {
  assert.equal(DEFAULT_REQUEST_TIMEOUT_MS, 15_000);
  await assert.rejects(
    retrieveFlutterwaveV4Charge({
      accessToken: 'access-token',
      chargeId: 'chg_123',
      traceId: TRACE_ID,
      timeoutMs: 5,
      fetchImpl: async (url, options) =>
        new Promise((resolve, reject) => {
          options.signal.addEventListener('abort', () => {
            const error = new Error('aborted');
            error.name = 'AbortError';
            reject(error);
          });
        }),
    }),
    (error) => {
      assert.ok(error instanceof FlutterwaveV4ApiError);
      assert.equal(error.message, 'Flutterwave v4 request timed out.');
      return true;
    },
  );
});
