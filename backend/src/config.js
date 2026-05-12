const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const DEFAULT_LICENSE_SIGNING_SECRET =
  'velora-pos-dev-license-secret-change-me';

function requireAnyEnv(names) {
  for (const name of names) {
    const value = process.env[name];
    if (value && value.trim()) {
      return value.trim();
    }
  }

  throw new Error(
    `Missing required environment variable. Set one of: ${names.join(', ')}`,
  );
}

const config = {
  port: Number(process.env.PORT || 3000),
  nodeEnv: process.env.NODE_ENV || 'development',
  neonDatabaseUrl: requireAnyEnv([
    'NEON_DATABASE_URL',
    'DATABASE_URL',
    'POSTGRES_URL',
  ]),
  subscriptionTrialDays: Number(process.env.SUBSCRIPTION_TRIAL_DAYS || 30),
  subscriptionGraceDays: Number(process.env.SUBSCRIPTION_GRACE_DAYS || 5),
  licenseSigningSecret:
    process.env.LICENSE_SIGNING_SECRET?.trim() ||
    DEFAULT_LICENSE_SIGNING_SECRET,
  platformAdminEmail: process.env.PLATFORM_ADMIN_EMAIL?.trim() || 'superadmin@velora.pos',
  platformAdminPassword: process.env.PLATFORM_ADMIN_PASSWORD || 'superadmin123',
  platformJwtSecret: process.env.PLATFORM_JWT_SECRET?.trim() || 'velora-platform-jwt-super-secret-dev',
  googlePayEnvironment:
    process.env.GOOGLE_PAY_ENVIRONMENT?.trim().toUpperCase() || 'TEST',
  googlePayMerchantId: process.env.GOOGLE_PAY_MERCHANT_ID?.trim() || '',
  googlePayGateway: process.env.GOOGLE_PAY_GATEWAY?.trim() || 'example',
  googlePayGatewayMerchantId:
    process.env.GOOGLE_PAY_GATEWAY_MERCHANT_ID?.trim() || 'exampleGatewayMerchantId',
  googlePayGatewayChargeUrl:
    process.env.GOOGLE_PAY_GATEWAY_CHARGE_URL?.trim() || '',
  googlePayGatewayApiKey: process.env.GOOGLE_PAY_GATEWAY_API_KEY?.trim() || '',
  mpesaBaseUrl:
    process.env.MPESA_BASE_URL?.trim() || 'https://sandbox.safaricom.co.ke',
  mpesaConsumerKey: process.env.MPESA_CONSUMER_KEY?.trim() || '',
  mpesaConsumerSecret: process.env.MPESA_CONSUMER_SECRET?.trim() || '',
  mpesaShortcode: process.env.MPESA_SHORTCODE?.trim() || '',
  mpesaPasskey: process.env.MPESA_PASSKEY?.trim() || '',
  mpesaCallbackUrl: process.env.MPESA_CALLBACK_URL?.trim() || '',
};

module.exports = { config };
