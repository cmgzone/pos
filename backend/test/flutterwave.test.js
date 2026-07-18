const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const test = require('node:test');

const {
  buildFlutterwavePayloadHash,
  flutterwaveWebhookTransaction,
  isFlutterwaveSuccessfulWebhook,
  isFlutterwaveWebhookSignatureValid,
} = require('../src/flutterwave');

test('Flutterwave checksum matches the documented Standard formula', () => {
  const amount = '1500.00';
  const currency = 'KES';
  const customerEmail = 'admin@example.com';
  const txRef = 'sub_payment-123';
  const secretKey = 'FLWSECK_TEST-example';
  const hashedSecretKey = crypto
    .createHash('sha256')
    .update(secretKey)
    .digest('hex');
  const expected = crypto
    .createHash('sha256')
    .update(`${amount}${currency}${customerEmail}${txRef}${hashedSecretKey}`)
    .digest('hex');

  assert.equal(
    buildFlutterwavePayloadHash({
      amount,
      currency,
      customerEmail,
      txRef,
      secretKey,
    }),
    expected,
  );
});

test('Flutterwave webhook validates the current HMAC signature against raw bytes', () => {
  const rawBody = Buffer.from('{"type":"charge.completed","data":{"status":"succeeded"}}');
  const secretHash = 'webhook-secret';
  const signature = crypto
    .createHmac('sha256', secretHash)
    .update(rawBody)
    .digest('base64');

  assert.equal(
    isFlutterwaveWebhookSignatureValid(rawBody, signature, secretHash),
    true,
  );
  assert.equal(
    isFlutterwaveWebhookSignatureValid(Buffer.from(`${rawBody}\n`), signature, secretHash),
    false,
  );
  assert.equal(
    isFlutterwaveWebhookSignatureValid(rawBody, 'invalid-signature', secretHash),
    false,
  );
});

test('Flutterwave webhook parser supports current and legacy transaction fields', () => {
  const current = flutterwaveWebhookTransaction({
    type: 'charge.completed',
    data: { id: 'chg_123', reference: 'sub_123', status: 'succeeded' },
  });
  assert.deepEqual(current, {
    eventType: 'charge.completed',
    status: 'succeeded',
    transactionId: 'chg_123',
    transactionReference: 'sub_123',
  });
  assert.equal(isFlutterwaveSuccessfulWebhook({
    type: 'charge.completed',
    data: { id: 123, reference: 'sub_123', status: 'succeeded' },
  }), true);
  assert.equal(isFlutterwaveSuccessfulWebhook({
    event: 'charge.completed',
    data: { id: 123, tx_ref: 'sub_123', status: 'successful' },
  }), true);
});
