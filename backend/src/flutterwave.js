const crypto = require('crypto');

function buildFlutterwavePayloadHash({
  amount,
  currency,
  customerEmail,
  txRef,
  secretKey,
}) {
  const hashedSecretKey = crypto
    .createHash('sha256')
    .update(String(secretKey || ''), 'utf8')
    .digest('hex');
  return crypto
    .createHash('sha256')
    .update(
      `${String(amount || '')}${String(currency || '')}${String(customerEmail || '')}${String(txRef || '')}${hashedSecretKey}`,
      'utf8',
    )
    .digest('hex');
}

function isFlutterwaveWebhookSignatureValid(rawBody, signature, secretHash) {
  const provided = String(signature || '').trim();
  const secret = String(secretHash || '').trim();
  if (!provided || !secret || rawBody == null) {
    return false;
  }
  const expected = crypto
    .createHmac('sha256', secret)
    .update(Buffer.isBuffer(rawBody) ? rawBody : Buffer.from(String(rawBody), 'utf8'))
    .digest('base64');
  return safeEquals(provided, expected);
}

function safeEquals(left, right) {
  const leftValue = String(left || '');
  const rightValue = String(right || '');
  const length = Math.max(leftValue.length, rightValue.length);
  const leftBuffer = Buffer.alloc(length);
  const rightBuffer = Buffer.alloc(length);
  Buffer.from(leftValue).copy(leftBuffer);
  Buffer.from(rightValue).copy(rightBuffer);
  return (
    crypto.timingSafeEqual(leftBuffer, rightBuffer) &&
    leftValue.length === rightValue.length
  );
}

function flutterwaveWebhookTransaction(event = {}) {
  const data = event?.data && typeof event.data === 'object' ? event.data : {};
  return {
    eventType: String(event.type || event.event || '').trim().toLowerCase(),
    status: String(data.status || '').trim().toLowerCase(),
    transactionId: data.id == null ? '' : String(data.id).trim(),
    transactionReference: String(
      data.tx_ref || data.reference || data.merchant_reference || '',
    ).trim(),
  };
}

function isFlutterwaveSuccessfulWebhook(event = {}) {
  const transaction = flutterwaveWebhookTransaction(event);
  return (
    ['charge.completed', 'transaction.completed'].includes(transaction.eventType) &&
    ['successful', 'succeeded', 'success', 'completed'].includes(transaction.status)
  );
}

module.exports = {
  buildFlutterwavePayloadHash,
  flutterwaveWebhookTransaction,
  isFlutterwaveSuccessfulWebhook,
  isFlutterwaveWebhookSignatureValid,
};
