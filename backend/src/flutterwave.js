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

function flutterwavePaymentPlanInterval(value) {
  switch (String(value || '').trim().toLowerCase()) {
    case 'annual':
    case 'yearly':
      return 'yearly';
    case 'quarterly':
      return 'quarterly';
    case 'weekly':
      return 'weekly';
    case 'daily':
      return 'daily';
    case 'monthly':
      return 'monthly';
    default:
      return null;
  }
}

function flutterwavePaymentPlanId(value) {
  if (value && typeof value === 'object') {
    return flutterwavePaymentPlanId(value.id ?? value.plan_id);
  }
  const id = String(value ?? '').trim();
  return id || null;
}

function flutterwaveWebhookSubscription(event = {}) {
  const data = event?.data && typeof event.data === 'object' ? event.data : {};
  const plan = data.payment_plan ?? data.paymentPlan ?? data.plan;
  const customer = data.customer && typeof data.customer === 'object' ? data.customer : {};
  return {
    paymentPlanId: flutterwavePaymentPlanId(plan),
    customerEmail: String(customer.email || '').trim().toLowerCase() || null,
  };
}

function flutterwaveWebhookPaymentId(event = {}) {
  const data = event?.data && typeof event.data === 'object' ? event.data : {};
  const meta = data.meta && typeof data.meta === 'object' ? data.meta : null;
  if (Array.isArray(meta)) {
    const paymentId = meta.find((item) =>
      String(item?.metaname || item?.name || '').trim() === 'paymentId',
    );
    return String(paymentId?.metavalue || paymentId?.value || '').trim() || null;
  }
  return String(meta?.paymentId || meta?.payment_id || '').trim() || null;
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
  flutterwavePaymentPlanInterval,
  flutterwavePaymentPlanId,
  flutterwaveWebhookTransaction,
  flutterwaveWebhookSubscription,
  flutterwaveWebhookPaymentId,
  isFlutterwaveSuccessfulWebhook,
  isFlutterwaveWebhookSignatureValid,
};
