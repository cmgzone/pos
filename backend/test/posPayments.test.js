const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeMpesaPhone,
  saveBusinessPaymentGateway,
  shouldIgnoreMpesaCallback,
  resolveMpesaGatewayConfig,
  validateBusinessPaymentGatewayConfiguration,
} = require('../src/posPayments');
const { config: serverConfig } = require('../src/config');

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
            passkey: 'p'.repeat(40),
          },
        },
        { baseUrl: infrastructure.baseUrl, callbackUrl: 'superadmin@example.com' },
      ),
    /callback URL must be a valid HTTPS URL/,
  );
});

test('active business M-Pesa settings reject a copied login password as passkey', () => {
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
            passkey: 'my-password',
          },
        },
        infrastructure,
      ),
    /passkey looks invalid/,
  );
});

test('business M-Pesa credentials are encrypted before database storage', async () => {
  const previousKey = serverConfig.paymentSecretsEncryptionKey;
  serverConfig.paymentSecretsEncryptionKey = Buffer.alloc(32, 7).toString(
    'base64',
  );
  let storedSecrets = null;
  const target = async (sql, params = []) => {
    if (sql.includes('INSERT INTO business_payment_gateways')) {
      storedSecrets = JSON.parse(params[5]);
      return {
        rows: [
          {
            business_id: params[0],
            provider: params[1],
            display_name: params[2],
            is_active: params[3],
            public_config_json: JSON.parse(params[4]),
            secret_config_json: storedSecrets,
            updated_at: new Date(),
          },
        ],
      };
    }
    return { rows: [] };
  };

  try {
    const saved = await saveBusinessPaymentGateway(
      'business-1',
      'mpesa',
      {
        isActive: false,
        publicConfig: { shortcode: '123456' },
        secretConfig: {
          consumerKey: 'merchant-key',
          consumerSecret: 'merchant-secret',
          passkey: 'merchant-passkey',
        },
      },
      target,
    );

    assert.ok(storedSecrets?.__pikiEncryptedSecret);
    assert.equal(JSON.stringify(storedSecrets).includes('merchant-secret'), false);
    assert.equal(saved.secretConfig.consumerSecret, '********cret');
  } finally {
    serverConfig.paymentSecretsEncryptionKey = previousKey;
  }
});

test('M-Pesa phone normalization accepts current Kenyan mobile formats', () => {
  assert.equal(normalizeMpesaPhone('0712 345 678'), '254712345678');
  assert.equal(normalizeMpesaPhone('0112-345-678'), '254112345678');
  assert.equal(normalizeMpesaPhone('+254 712 345 678'), '254712345678');
  assert.throws(() => normalizeMpesaPhone('12345'), /valid Kenyan/);
});

test('merchant credentials cannot be saved without server-side encryption', async () => {
  const previousKey = serverConfig.paymentSecretsEncryptionKey;
  serverConfig.paymentSecretsEncryptionKey = '';
  const target = async () => ({ rows: [] });
  try {
    await assert.rejects(
      saveBusinessPaymentGateway(
        'business-1',
        'mpesa',
        {
          isActive: false,
          secretConfig: { consumerKey: 'merchant-key' },
        },
        target,
      ),
      /Secure payment credential storage is not configured/,
    );
  } finally {
    serverConfig.paymentSecretsEncryptionKey = previousKey;
  }
});

test('duplicate M-Pesa callbacks cannot re-apply a completed payment', () => {
  assert.equal(shouldIgnoreMpesaCallback('paid', 0), true);
  assert.equal(shouldIgnoreMpesaCallback('paid', 1032), true);
  assert.equal(shouldIgnoreMpesaCallback('failed', 1032), true);
  assert.equal(shouldIgnoreMpesaCallback('failed', 0), false);
  assert.equal(shouldIgnoreMpesaCallback('pending', 0), false);
});
