const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const DEFAULT_LICENSE_SIGNING_SECRET =
  'velora-pos-dev-license-secret-change-me';
const DEFAULT_PLATFORM_ADMIN_PASSWORD = 'superadmin123';
const DEFAULT_PLATFORM_JWT_SECRET = 'velora-platform-jwt-super-secret-dev';
const DEFAULT_DEV_ALLOWED_ORIGINS = [
  'http://localhost:4000',
  'http://127.0.0.1:4000',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
];

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
  platformAdminPassword:
    process.env.PLATFORM_ADMIN_PASSWORD || DEFAULT_PLATFORM_ADMIN_PASSWORD,
  platformJwtSecret:
    process.env.PLATFORM_JWT_SECRET?.trim() || DEFAULT_PLATFORM_JWT_SECRET,
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
  mpesaCallbackSecret: process.env.MPESA_CALLBACK_SECRET?.trim() || '',
  serpApiKey:
    process.env.SERPAPI_API_KEY?.trim() ||
    process.env.SERP_API_KEY?.trim() ||
    '',
  serpApiBaseUrl:
    process.env.SERPAPI_BASE_URL?.trim() || 'https://google.serper.dev/search',
};

config.allowedOrigins = parseOriginList(
  process.env.PLATFORM_ALLOWED_ORIGINS ||
    process.env.CORS_ALLOWED_ORIGINS ||
    process.env.APP_ALLOWED_ORIGINS,
);
if (config.nodeEnv !== 'production' && config.allowedOrigins.length === 0) {
  config.allowedOrigins = DEFAULT_DEV_ALLOWED_ORIGINS;
}

if (config.nodeEnv === 'production') {
  assertNonDefaultSecret(
    'LICENSE_SIGNING_SECRET',
    config.licenseSigningSecret,
    DEFAULT_LICENSE_SIGNING_SECRET,
  );
  assertNonDefaultSecret(
    'PLATFORM_ADMIN_PASSWORD',
    config.platformAdminPassword,
    DEFAULT_PLATFORM_ADMIN_PASSWORD,
  );
  assertNonDefaultSecret(
    'PLATFORM_JWT_SECRET',
    config.platformJwtSecret,
    DEFAULT_PLATFORM_JWT_SECRET,
  );
  assertNonDefaultSecret(
    'PLATFORM_ADMIN_EMAIL',
    config.platformAdminEmail,
    'superadmin@velora.pos',
  );
  if (config.allowedOrigins.length === 0) {
    throw new Error(
      'PLATFORM_ALLOWED_ORIGINS or CORS_ALLOWED_ORIGINS must be set in production',
    );
  }
}

function assertNonDefaultSecret(name, value, defaultValue) {
  if (!value || value === defaultValue) {
    throw new Error(`${name} must be set to a non-default value in production`);
  }
}

function parseOriginList(value) {
  return String(value || '')
    .split(',')
    .map((origin) => origin.trim().replace(/\/+$/, ''))
    .filter(Boolean);
}

module.exports = { config };
