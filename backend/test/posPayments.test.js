const test = require('node:test');
const assert = require('node:assert/strict');

const {
  resolveMpesaGatewayConfig,
  validateBusinessPaymentGatewayConfiguration,
} = require('../src/posPayments');

test('POS M-Pesa config uses business merchant credentials', () => {
  const config = resolveMpesaGatewayConfig(
    {
      publicConfig: {
        baseUrl: 'https://sandbox.safaricom.co.ke',
        shortcode: '999999',
        callbackUrl: 'https://platform.example/mpesa/callback',
      },
      secretConfig: {
        consumerKey: 'platform-key',
        consumerSecret: 'platform-secret',
        passkey: 'platform-passkey',
      },
    },
    {
      publicConfig: {
        shortcode: '123456',
        transactionType: 'CustomerBuyGoodsOnline',
        accountReference: 'SHOP-1',
      },
      secretConfig: {
        consumerKey: 'business-key',
        consumerSecret: 'business-secret',
        passkey: 'business-passkey',
      },
    },
  );

  assert.equal(config.baseUrl, 'https://sandbox.safaricom.co.ke');
  assert.equal(config.callbackUrl, 'https://platform.example/mpesa/callback');
  assert.equal(config.shortcode, '123456');
  assert.equal(config.transactionType, 'CustomerBuyGoodsOnline');
  assert.equal(config.accountReference, 'SHOP-1');
  assert.equal(config.consumerKey, 'business-key');
  assert.equal(config.consumerSecret, 'business-secret');
  assert.equal(config.passkey, 'business-passkey');
});

test('POS M-Pesa config does not fall back to platform merchant credentials', () => {
  const config = resolveMpesaGatewayConfig(
    {
      publicConfig: {
        shortcode: '999999',
        callbackUrl: 'https://platform.example/mpesa/callback',
      },
      secretConfig: {
        consumerKey: 'platform-key',
        consumerSecret: 'platform-secret',
        passkey: 'platform-passkey',
      },
    },
    null,
  );

  assert.equal(config.shortcode, '');
  assert.equal(config.consumerKey, '');
  assert.equal(config.consumerSecret, '');
  assert.equal(config.passkey, '');
  assert.equal(config.callbackUrl, 'https://platform.example/mpesa/callback');
});

test('active business M-Pesa settings require merchant credentials', () => {
  assert.throws(
    () =>
      validateBusinessPaymentGatewayConfiguration(
        {
          provider: 'mpesa',
          isActive: true,
          publicConfig: { shortcode: '123456' },
          secretConfig: { consumerKey: 'key' },
        },
        {
          publicConfig: {
            callbackUrl: 'https://platform.example/mpesa/callback',
          },
        },
      ),
    /consumer secret, passkey/,
  );
});

test('inactive business M-Pesa settings can be saved incomplete', () => {
  assert.doesNotThrow(() =>
    validateBusinessPaymentGatewayConfiguration(
      {
        provider: 'mpesa',
        isActive: false,
        publicConfig: {},
        secretConfig: {},
      },
      null,
    ),
  );
});
