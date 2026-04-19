const path = require('path');
const dotenv = require('dotenv');

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

const DEFAULT_LICENSE_SIGNING_SECRET =
  'velora-pos-dev-license-secret-change-me';

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value.trim();
}

const config = {
  port: Number(process.env.PORT || 3000),
  nodeEnv: process.env.NODE_ENV || 'development',
  neonDatabaseUrl: requireEnv('NEON_DATABASE_URL'),
  subscriptionTrialDays: Number(process.env.SUBSCRIPTION_TRIAL_DAYS || 30),
  subscriptionGraceDays: Number(process.env.SUBSCRIPTION_GRACE_DAYS || 5),
  licenseSigningSecret:
    process.env.LICENSE_SIGNING_SECRET?.trim() ||
    DEFAULT_LICENSE_SIGNING_SECRET,
  platformAdminEmail: process.env.PLATFORM_ADMIN_EMAIL?.trim() || 'superadmin@velora.pos',
  platformAdminPassword: process.env.PLATFORM_ADMIN_PASSWORD || 'superadmin123',
  platformJwtSecret: process.env.PLATFORM_JWT_SECRET?.trim() || 'velora-platform-jwt-super-secret-dev',
};

module.exports = { config };
