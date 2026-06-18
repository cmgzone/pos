const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const DEFAULT_LICENSE_SIGNING_SECRET =
  'velora-pos-dev-license-secret-change-me';
const DEFAULT_PLATFORM_ADMIN_PASSWORD = 'superadmin123';
const DEFAULT_PLATFORM_JWT_SECRET = 'velora-platform-jwt-super-secret-dev';
const DEFAULT_EMAIL_OTP_SECRET = 'piki-pos-email-otp-dev-secret';
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
  databaseUrl: requireAnyEnv([
    'DATABASE_URL',
    'POSTGRES_URL',
    'NEON_DATABASE_URL',
  ]),
  databasePoolMax: positiveNumberEnv(process.env.DATABASE_POOL_MAX, 20),
  databaseIdleTimeoutMs: positiveNumberEnv(
    process.env.DATABASE_IDLE_TIMEOUT_MS,
    30000,
  ),
  databaseConnectionTimeoutMs: positiveNumberEnv(
    process.env.DATABASE_CONNECTION_TIMEOUT_MS,
    10000,
  ),
  databaseSsl: parseOptionalBooleanEnv(process.env.DATABASE_SSL),
  databaseSslRejectUnauthorized: parseBooleanEnv(
    process.env.DATABASE_SSL_REJECT_UNAUTHORIZED,
    true,
  ),
  redisUrl: process.env.REDIS_URL?.trim() || '',
  redisCacheTtlSeconds: positiveNumberEnv(
    process.env.REDIS_CACHE_TTL_SECONDS,
    30,
  ),
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
  publicBaseUrl:
    process.env.PUBLIC_BASE_URL?.trim().replace(/\/+$/, '') ||
    process.env.APP_PUBLIC_URL?.trim().replace(/\/+$/, '') ||
    '',
  publicCatalogRootDomain:
    process.env.PUBLIC_CATALOG_ROOT_DOMAIN?.trim().toLowerCase() ||
    'pikipos.com',
  googlePlayPackageName:
    process.env.GOOGLE_PLAY_PACKAGE_NAME?.trim() || 'com.example.pos_app',
  googlePlayServiceAccountEmail:
    process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL?.trim() || '',
  googlePlayServiceAccountPrivateKey: String(
    process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY || '',
  ).replace(/\\n/g, '\n'),
  googlePlayApiBaseUrl:
    process.env.GOOGLE_PLAY_API_BASE_URL?.trim() ||
    'https://androidpublisher.googleapis.com/androidpublisher/v3/applications',
  paypalBaseUrl:
    process.env.PAYPAL_BASE_URL?.trim() || 'https://api-m.sandbox.paypal.com',
  paypalClientId: process.env.PAYPAL_CLIENT_ID?.trim() || '',
  paypalClientSecret: process.env.PAYPAL_CLIENT_SECRET?.trim() || '',
  flutterwaveBaseUrl:
    process.env.FLUTTERWAVE_BASE_URL?.trim() || 'https://api.flutterwave.com/v3',
  flutterwaveSecretKey: process.env.FLUTTERWAVE_SECRET_KEY?.trim() || '',
  mpesaBaseUrl:
    process.env.MPESA_BASE_URL?.trim() || 'https://sandbox.safaricom.co.ke',
  mpesaCallbackUrl: process.env.MPESA_CALLBACK_URL?.trim() || '',
  mpesaCallbackSecret: process.env.MPESA_CALLBACK_SECRET?.trim() || '',
  serpApiKey:
    process.env.SERPAPI_API_KEY?.trim() ||
    process.env.SERP_API_KEY?.trim() ||
    '',
  serpApiBaseUrl:
    process.env.SERPAPI_BASE_URL?.trim() || 'https://google.serper.dev/search',
  bunnyStorageZone: process.env.BUNNY_STORAGE_ZONE?.trim() || '',
  bunnyStorageAccessKey:
    process.env.BUNNY_STORAGE_ACCESS_KEY?.trim() ||
    process.env.BUNNY_STORAGE_PASSWORD?.trim() ||
    '',
  bunnyStorageRegion: process.env.BUNNY_STORAGE_REGION?.trim() || '',
  bunnyStorageEndpoint: buildBunnyStorageEndpoint({
    endpoint: process.env.BUNNY_STORAGE_ENDPOINT,
    region: process.env.BUNNY_STORAGE_REGION,
  }),
  bunnyCdnBaseUrl:
    trimTrailingUrl(process.env.BUNNY_CDN_BASE_URL) ||
    trimTrailingUrl(process.env.BUNNY_PULL_ZONE_URL) ||
    trimTrailingUrl(process.env.BUNNY_CDN_URL) ||
    '',
  bunnyUploadPath: trimSlashes(process.env.BUNNY_UPLOAD_PATH || 'product-images'),
  bunnyMaxImageBytes: positiveNumberEnv(
    process.env.BUNNY_MAX_IMAGE_BYTES,
    5 * 1024 * 1024,
  ),
  resendApiKey: process.env.RESEND_API_KEY?.trim() || '',
  resendApiBaseUrl:
    trimTrailingUrl(process.env.RESEND_API_BASE_URL) ||
    'https://api.resend.com',
  otpFromEmail:
    process.env.OTP_FROM_EMAIL?.trim() ||
    process.env.EMAIL_OTP_FROM?.trim() ||
    'Piki POS <otp@notify.pikipos.com>',
  emailOtpRequired: parseBooleanEnv(process.env.EMAIL_OTP_REQUIRED, true),
  emailOtpTtlMinutes: positiveNumberEnv(process.env.EMAIL_OTP_TTL_MINUTES, 10),
  emailOtpCooldownSeconds: positiveNumberEnv(
    process.env.EMAIL_OTP_COOLDOWN_SECONDS,
    60,
  ),
  emailOtpMaxAttempts: positiveNumberEnv(process.env.EMAIL_OTP_MAX_ATTEMPTS, 5),
  supportEmail:
    process.env.SUPPORT_EMAIL?.trim() ||
    process.env.LANDING_CONTACT_NOTIFY_EMAIL?.trim() ||
    'support@pikipos.com',
  landingContactNotifyEmail:
    process.env.LANDING_CONTACT_NOTIFY_EMAIL?.trim() ||
    process.env.SUPPORT_EMAIL?.trim() ||
    'support@pikipos.com',
  smtpHost:
    process.env.SMTP_HOST?.trim() ||
    process.env.MAIL_SMTP_HOST?.trim() ||
    'smtp.zoho.com',
  smtpPort: positiveNumberEnv(
    process.env.SMTP_PORT || process.env.MAIL_SMTP_PORT,
    465,
  ),
  smtpSecure: parseBooleanEnv(
    process.env.SMTP_SECURE || process.env.MAIL_SMTP_SECURE,
    true,
  ),
  smtpUser:
    process.env.SMTP_USER?.trim() ||
    process.env.MAIL_SMTP_USER?.trim() ||
    process.env.SUPPORT_EMAIL?.trim() ||
    'support@pikipos.com',
  smtpPass: process.env.SMTP_PASS || process.env.MAIL_SMTP_PASS || '',
  smtpFromEmail:
    process.env.SMTP_FROM_EMAIL?.trim() ||
    process.env.MAIL_FROM?.trim() ||
    process.env.SUPPORT_EMAIL?.trim() ||
    'Piki POS <support@pikipos.com>',
  appReleaseDir:
    process.env.APP_RELEASE_DIR?.trim() ||
    path.resolve(__dirname, '..', 'app-releases'),
  appReleaseMaxBytes: positiveNumberEnv(
    process.env.APP_RELEASE_MAX_BYTES,
    300 * 1024 * 1024,
  ),
};

config.emailOtpSecret =
  process.env.EMAIL_OTP_SECRET?.trim() ||
  config.licenseSigningSecret ||
  DEFAULT_EMAIL_OTP_SECRET;

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
  assertNonDefaultSecret(
    'EMAIL_OTP_SECRET',
    config.emailOtpSecret,
    DEFAULT_EMAIL_OTP_SECRET,
  );
  if (!config.mpesaCallbackSecret) {
    throw new Error(
      'MPESA_CALLBACK_SECRET must be set to a non-empty value in production. ' +
        'Without it, M-Pesa callback endpoints accept unauthenticated requests.',
    );
  }
  assertNonSandboxUrl('PAYPAL_BASE_URL', config.paypalBaseUrl);
  assertNonSandboxUrl('MPESA_BASE_URL', config.mpesaBaseUrl);
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

function assertNonSandboxUrl(name, value) {
  const lower = String(value || '').toLowerCase();
  if (lower.includes('sandbox')) {
    throw new Error(
      `${name} must point to a production endpoint in production (found sandbox URL: ${value}). ` +
        'Set the environment variable to the live API base URL.',
    );
  }
}

function parseOriginList(value) {
  return String(value || '')
    .split(',')
    .map((origin) => origin.trim().replace(/\/+$/, ''))
    .filter(Boolean);
}

function trimTrailingUrl(value) {
  return String(value || '').trim().replace(/\/+$/, '');
}

function trimSlashes(value) {
  return String(value || '')
    .trim()
    .replace(/^\/+/, '')
    .replace(/\/+$/, '');
}

function positiveNumberEnv(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function parseBooleanEnv(value, fallback) {
  if (value == null || String(value).trim() === '') {
    return fallback;
  }
  return ['1', 'true', 'yes', 'on'].includes(String(value).trim().toLowerCase());
}

function parseOptionalBooleanEnv(value) {
  if (value == null || String(value).trim() === '') {
    return null;
  }
  return parseBooleanEnv(value, false);
}

function buildBunnyStorageEndpoint({ endpoint, region }) {
  const customEndpoint = trimTrailingUrl(endpoint);
  if (customEndpoint) {
    return /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(customEndpoint)
      ? customEndpoint
      : `https://${customEndpoint}`;
  }

  const cleanRegion = String(region || '').trim().replace(/^\.+|\.+$/g, '');
  if (!cleanRegion || cleanRegion.toLowerCase() === 'storage') {
    return 'https://storage.bunnycdn.com';
  }

  return `https://${cleanRegion}.storage.bunnycdn.com`;
}

module.exports = { config };
