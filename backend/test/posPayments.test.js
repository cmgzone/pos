const test = require('node:test');
const assert = require('node:assert/strict');

const {
  resolveMpesaGatewayConfig,
  validateBusinessPaymentGatewayConfiguration,
} = require('../src/posPayments');

const infrastructure = {
  baseUrl: 'https://sandbox.safaricom.co.ke',
  callbackUrl: 'https://platform.example/api/payments/mpesa/stk-callback',
};

test('POS M-Pesa config uses only business merchant credentials', () => {
  const config = resolveMpesaGatewayConfig(
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
    infrastructure,
  );

  assert.equal(config.baseUrl, infrastructure.baseUrl);
  assert.equal(config.callbackUrl, infrastructure.callbackUrl);
  assert.equal(config.shortcode, '123456');
  assert.equal(config.transactionType, 'CustomerBuyGoodsOnline');
  assert.equal(config.accountReference, 'SHOP-1');
  assert.equal(config.consumerKey, 'business-key');
  assert.equal(config.consumerSecret, 'business-secret');
  assert.equal(config.passkey, 'business-passkey');
});

test('POS M-Pesa config trims copied merchant credentials', () => {
  const config = resolveMpesaGatewayConfig(
    {
      publicConfig: {
        shortcode: ' 123456 ',
        accountReference: ' SHOP-1 ',
      },
      secretConfig: {
        consumerKey: ' key ',
        consumerSecret: ' secret ',
        passkey: ' passkey ',
      },
    },
    {
      baseUrl: ` ${infrastructure.baseUrl} `,
      callbackUrl: ` ${infrastructure.callbackUrl} `,
    },
  );

  assert.equal(config.baseUrl, infrastructure.baseUrl);
  assert.equal(config.callbackUrl, infrastructure.callbackUrl);
  assert.equal(config.shortcode, '123456');
  assert.equal(config.accountReference, 'SHOP-1');
  assert.equal(config.consumerKey, 'key');
  assert.equal(config.consumerSecret, 'secret');
  assert.equal(config.passkey, 'passkey');
});

test('POS M-Pesa config has no merchant credentials without business settings', () => {
  const config = resolveMpesaGatewayConfig(null, infrastructure);

  assert.equal(config.shortcode, '');
  assert.equal(config.consumerKey, '');
  assert.equal(config.consumerSecret, '');
  assert.equal(config.passkey, '');
  assert.equal(config.callbackUrl, infrastructure.callbackUrl);
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
        infrastructure,
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
      infrastructure,
    ),
  );
});

test('active business M-Pesa settings reject an invalid server callback URL', () => {
  assert.throws(
    () =>
      validateBusinessPaymentGatewayConfiguration(
        {
          provider: 'mpesa',
          isActive: true,
          publicConfig: { shortcode: '123456' },
          secretConfig: {
            consumerKey: 'key',
            consumerSecret: 'secret',
            passkey: 'passkey',
          },
        },
        { baseUrl: infrastructure.baseUrl, callbackUrl: 'superadmin@example.com' },
      ),
    /callback URL must be a valid HTTPS URL/,
  );
});
