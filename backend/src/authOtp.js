const crypto = require('crypto');

const { config } = require('./config');
const { query } = require('./db');
const { normalizePasswordForStorage } = require('./passwords');

const OTP_PURPOSES = new Set(['signup', 'password_reset']);

let schemaReady = false;

async function ensureEmailOtpSchema(target = query) {
  const canUseCache = target === query;
  if (canUseCache && schemaReady) {
    return;
  }

  await runDbQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS email_otps (
      id text PRIMARY KEY,
      email text NOT NULL,
      purpose text NOT NULL,
      code_hash text NOT NULL,
      attempts integer NOT NULL DEFAULT 0,
      expires_at timestamptz NOT NULL,
      sent_at timestamptz NOT NULL DEFAULT NOW(),
      verified_at timestamptz,
      verification_token_hash text,
      token_expires_at timestamptz,
      consumed_at timestamptz,
      last_error text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );
  await runDbQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_email_otps_lookup
      ON email_otps(email, purpose, created_at DESC)
    `,
  );
  await runDbQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_email_otps_token
      ON email_otps(email, purpose, verification_token_hash)
      WHERE verification_token_hash IS NOT NULL
    `,
  );

  if (canUseCache) {
    schemaReady = true;
  }
}

async function requestEmailOtp({
  email,
  purpose = 'signup',
  now = new Date(),
  target = query,
  sendEmail = sendOtpEmail,
} = {}) {
  await ensureEmailOtpSchema(target);
  const cleanEmail = normalizeEmail(email);
  const cleanPurpose = normalizePurpose(purpose);

  if (cleanPurpose === 'signup') {
    const existingUser = await runDbQuery(
      target,
      `
      SELECT id
      FROM users
      WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))
        AND deleted_at IS NULL
      LIMIT 1
      `,
      [cleanEmail],
    );
    if (existingUser.rows.length > 0) {
      throw createOtpError(409, 'An account with that email already exists. Please sign in instead.');
    }
  } else if (cleanPurpose === 'password_reset') {
    const existingUser = await runDbQuery(
      target,
      `
      SELECT id
      FROM users
      WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))
        AND deleted_at IS NULL
      LIMIT 1
      `,
      [cleanEmail],
    );
    if (existingUser.rows.length === 0) {
      throw createOtpError(404, 'No account was found with that email address.');
    }
  }

  const latest = await runDbQuery(
    target,
    `
    SELECT sent_at
    FROM email_otps
    WHERE email = $1
      AND purpose = $2
      AND consumed_at IS NULL
    ORDER BY sent_at DESC
    LIMIT 1
    `,
    [cleanEmail, cleanPurpose],
  );
  const cooldownSeconds = Math.max(1, Math.floor(config.emailOtpCooldownSeconds || 60));
  const latestSentAt = latest.rows[0]?.sent_at
    ? new Date(latest.rows[0].sent_at)
    : null;
  if (
    latestSentAt &&
    Number.isFinite(latestSentAt.getTime()) &&
    now.getTime() - latestSentAt.getTime() < cooldownSeconds * 1000
  ) {
    const retryAfterSeconds = Math.max(
      1,
      Math.ceil((cooldownSeconds * 1000 - (now.getTime() - latestSentAt.getTime())) / 1000),
    );
    return {
      email: cleanEmail,
      sent: false,
      retryAfterSeconds,
    };
  }

  const code = createOtpCode();
  const otpId = crypto.randomUUID();
  const expiresAt = new Date(
    now.getTime() + Math.max(1, Math.floor(config.emailOtpTtlMinutes || 10)) * 60 * 1000,
  );
  await runDbQuery(
    target,
    `
    INSERT INTO email_otps (
      id,
      email,
      purpose,
      code_hash,
      attempts,
      expires_at,
      sent_at,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, 0, $5, $6, $6, $6)
    `,
    [
      otpId,
      cleanEmail,
      cleanPurpose,
      hashOtpCode({ email: cleanEmail, purpose: cleanPurpose, code }),
      expiresAt.toISOString(),
      now.toISOString(),
    ],
  );

  try {
    await sendEmail({
      email: cleanEmail,
      code,
      expiresAt,
    });
  } catch (error) {
    await runDbQuery(
      target,
      `
      UPDATE email_otps
      SET consumed_at = $2,
          last_error = $3,
          updated_at = $2
      WHERE id = $1
      `,
      [otpId, now.toISOString(), limitText(error.message || 'OTP email failed', 500)],
    );
    throw error;
  }

  return {
    email: cleanEmail,
    sent: true,
    expiresAt: expiresAt.toISOString(),
  };
}

async function verifyEmailOtp({
  email,
  code,
  purpose = 'signup',
  now = new Date(),
  target = query,
} = {}) {
  await ensureEmailOtpSchema(target);
  const cleanEmail = normalizeEmail(email);
  const cleanPurpose = normalizePurpose(purpose);
  const cleanCode = normalizeCode(code);

  const result = await runDbQuery(
    target,
    `
    SELECT *
    FROM email_otps
    WHERE email = $1
      AND purpose = $2
      AND consumed_at IS NULL
    ORDER BY created_at DESC
    LIMIT 1
    `,
    [cleanEmail, cleanPurpose],
  );
  const row = result.rows[0];
  if (!row) {
    throw createOtpError(400, 'Request a verification code first.');
  }
  if (isPast(row.expires_at, now)) {
    throw createOtpError(400, 'That verification code has expired. Request a new code.');
  }

  const maxAttempts = Math.max(1, Math.floor(config.emailOtpMaxAttempts || 5));
  const attempts = Number(row.attempts || 0);
  if (attempts >= maxAttempts) {
    throw createOtpError(429, 'Too many incorrect attempts. Request a new code.');
  }

  const expectedHash = String(row.code_hash || '');
  const actualHash = hashOtpCode({
    email: cleanEmail,
    purpose: cleanPurpose,
    code: cleanCode,
  });
  if (!safeEqual(expectedHash, actualHash)) {
    await runDbQuery(
      target,
      `
      UPDATE email_otps
      SET attempts = attempts + 1,
          updated_at = $2
      WHERE id = $1
      `,
      [row.id, now.toISOString()],
    );
    throw createOtpError(400, 'The verification code is incorrect.');
  }

  const verificationToken = crypto.randomBytes(32).toString('base64url');
  const tokenExpiresAt = new Date(
    Math.min(
      new Date(row.expires_at).getTime(),
      now.getTime() + 10 * 60 * 1000,
    ),
  );
  await runDbQuery(
    target,
    `
    UPDATE email_otps
    SET verified_at = $2,
        verification_token_hash = $3,
        token_expires_at = $4,
        updated_at = $2
    WHERE id = $1
    `,
    [
      row.id,
      now.toISOString(),
      hashVerificationToken(verificationToken),
      tokenExpiresAt.toISOString(),
    ],
  );

  return {
    email: cleanEmail,
    verificationToken,
    expiresAt: tokenExpiresAt.toISOString(),
  };
}

async function consumeEmailOtpVerification({
  email,
  verificationToken,
  purpose = 'signup',
  now = new Date(),
  target = query,
} = {}) {
  if (!config.emailOtpRequired) {
    return { ok: true, skipped: true };
  }

  await ensureEmailOtpSchema(target);
  const cleanEmail = normalizeEmail(email);
  const cleanPurpose = normalizePurpose(purpose);
  const cleanToken = String(verificationToken || '').trim();
  if (!cleanToken) {
    throw createOtpError(403, 'Verify your email before creating account.');
  }

  const result = await runDbQuery(
    target,
    `
    SELECT *
    FROM email_otps
    WHERE email = $1
      AND purpose = $2
      AND verification_token_hash = $3
      AND verified_at IS NOT NULL
      AND consumed_at IS NULL
    ORDER BY verified_at DESC
    LIMIT 1
    `,
    [cleanEmail, cleanPurpose, hashVerificationToken(cleanToken)],
  );
  const row = result.rows[0];
  if (
    !row ||
    isPast(row.expires_at, now) ||
    isPast(row.token_expires_at, now)
  ) {
    throw createOtpError(403, 'Email verification expired. Request a new code.');
  }

  await runDbQuery(
    target,
    `
    UPDATE email_otps
    SET consumed_at = $2,
        updated_at = $2
    WHERE id = $1
    `,
    [row.id, now.toISOString()],
  );
  return { ok: true };
}

async function resetPasswordWithVerifiedOtp({
  email,
  verificationToken,
  newPassword,
  now = new Date(),
  target = query,
} = {}) {
  const cleanEmail = normalizeEmail(email);
  const cleanPassword = String(newPassword || '');
  if (cleanPassword.length < 6) {
    throw createOtpError(400, 'Password must be at least 6 characters.');
  }

  await ensureEmailOtpSchema(target);
  const users = await runDbQuery(
    target,
    `
    SELECT id, business_id
    FROM users
    WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))
      AND deleted_at IS NULL
    `,
    [cleanEmail],
  );
  if (users.rows.length === 0) {
    throw createOtpError(404, 'No account was found with that email address.');
  }

  const businessIds = new Set(users.rows.map((row) => row.business_id).filter(Boolean));
  if (businessIds.size > 1) {
    throw createOtpError(
      409,
      'This email is used in more than one business. Ask an admin to reset the staff password.',
    );
  }

  await consumeEmailOtpVerification({
    email: cleanEmail,
    purpose: 'password_reset',
    verificationToken,
    now,
    target,
  });

  const result = await runDbQuery(
    target,
    `
    UPDATE users
    SET password = $2,
        updated_at = $3,
        server_revision = nextval('sync_revision_seq')
    WHERE LOWER(TRIM(email)) = LOWER(TRIM($1))
      AND deleted_at IS NULL
    RETURNING id
    `,
    [
      cleanEmail,
      normalizePasswordForStorage(cleanPassword),
      now.toISOString(),
    ],
  );

  return {
    ok: true,
    email: cleanEmail,
    updatedUsers: result.rowCount || result.rows?.length || 0,
  };
}

async function sendOtpEmail({ email, code, expiresAt }) {
  if (!config.resendApiKey) {
    throw createOtpError(503, 'Email verification is not configured. Add RESEND_API_KEY.');
  }
  if (!config.otpFromEmail) {
    throw createOtpError(503, 'Email verification sender is not configured. Add OTP_FROM_EMAIL.');
  }

  const fetch = (await import('node-fetch')).default;
  const response = await fetch(`${config.resendApiBaseUrl}/emails`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.resendApiKey}`,
      'Content-Type': 'application/json',
    },
      body: JSON.stringify({
        from: config.otpFromEmail,
        to: [email],
        subject: 'Your Piki POS verification code',
        html: buildOtpHtml(code, expiresAt),
        text: `Your Piki POS verification code is ${code}. It expires in ${Math.max(
        1,
        Math.floor(config.emailOtpTtlMinutes || 10),
      )} minutes.`,
      tags: [
        { name: 'kind', value: 'signup_otp' },
      ],
    }),
  });

  if (response.ok) {
    return;
  }

  let message = `Resend rejected the OTP email (${response.status})`;
  try {
    const body = await response.json();
    message = body?.message || body?.error?.message || message;
  } catch (_) {
    // Keep the generic message.
  }
  throw createOtpError(502, message);
}

function buildOtpHtml(code, expiresAt) {
  const minutes = Math.max(1, Math.floor(config.emailOtpTtlMinutes || 10));
  const expiry = expiresAt ? new Date(expiresAt).toISOString() : '';
  return `
    <div style="font-family:Arial,sans-serif;color:#171421;line-height:1.5">
      <h2 style="margin:0 0 12px">Verify your Piki POS email</h2>
      <p>Use this code to finish creating your Piki POS account:</p>
      <p style="font-size:32px;font-weight:700;letter-spacing:8px;margin:20px 0">${code}</p>
      <p>This code expires in ${minutes} minutes.</p>
      ${expiry ? `<p style="color:#6b6478;font-size:12px">Expires at ${expiry}</p>` : ''}
      <p style="color:#6b6478;font-size:12px">If you did not request this, you can ignore this email.</p>
    </div>
  `;
}

function createOtpCode() {
  return crypto.randomInt(0, 1000000).toString().padStart(6, '0');
}

function normalizeEmail(email) {
  const clean = String(email || '').trim().toLowerCase();
  if (!clean || !clean.includes('@') || !clean.includes('.')) {
    throw createOtpError(400, 'A valid email address is required.');
  }
  return clean;
}

function normalizePurpose(purpose) {
  const clean = String(purpose || 'signup').trim().toLowerCase();
  if (!OTP_PURPOSES.has(clean)) {
    throw createOtpError(400, 'Unsupported verification purpose.');
  }
  return clean;
}

function normalizeCode(code) {
  const clean = String(code || '').replace(/\D/g, '');
  if (!/^\d{6}$/.test(clean)) {
    throw createOtpError(400, 'Enter the 6 digit verification code.');
  }
  return clean;
}

function hashOtpCode({ email, purpose, code }) {
  return crypto
    .createHmac('sha256', otpSecret())
    .update([email, purpose, code].join(':'))
    .digest('hex');
}

function hashVerificationToken(token) {
  return crypto
    .createHmac('sha256', otpSecret())
    .update(String(token || ''))
    .digest('hex');
}

function otpSecret() {
  return config.emailOtpSecret;
}

function safeEqual(left, right) {
  const leftBuffer = Buffer.from(String(left || ''), 'utf8');
  const rightBuffer = Buffer.from(String(right || ''), 'utf8');
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function isPast(value, now) {
  const parsed = new Date(value);
  return !Number.isFinite(parsed.getTime()) || parsed.getTime() <= now.getTime();
}

async function runDbQuery(target, sql, params = []) {
  if (typeof target === 'function') {
    return target(sql, params);
  }
  return target.query(sql, params);
}

function createOtpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.exposeMessage = true;
  return error;
}

function limitText(value, maxLength) {
  const text = String(value || '').trim();
  return text.length <= maxLength ? text : text.slice(0, maxLength);
}

module.exports = {
  createOtpCode,
  consumeEmailOtpVerification,
  ensureEmailOtpSchema,
  requestEmailOtp,
  resetPasswordWithVerifiedOtp,
  sendOtpEmail,
  verifyEmailOtp,
};
