const test = require('node:test');
const assert = require('node:assert/strict');

const {
  consumeEmailOtpVerification,
  requestEmailOtp,
  resetPasswordWithVerifiedOtp,
  verifyEmailOtp,
} = require('../src/authOtp');

test('signup OTP request, verify, and consume flow succeeds once', async () => {
  const db = createOtpDb();
  const sent = [];

  const request = await requestEmailOtp({
    email: ' Owner@Example.com ',
    target: db.query,
    sendEmail: async (payload) => sent.push(payload),
    now: new Date('2026-06-13T10:00:00.000Z'),
  });

  assert.equal(request.sent, true);
  assert.equal(request.email, 'owner@example.com');
  assert.equal(sent.length, 1);
  assert.match(sent[0].code, /^\d{6}$/);

  const verification = await verifyEmailOtp({
    email: 'owner@example.com',
    code: sent[0].code,
    target: db.query,
    now: new Date('2026-06-13T10:01:00.000Z'),
  });

  assert.equal(verification.email, 'owner@example.com');
  assert.ok(verification.verificationToken);

  const consumed = await consumeEmailOtpVerification({
    email: 'owner@example.com',
    verificationToken: verification.verificationToken,
    target: db.query,
    now: new Date('2026-06-13T10:02:00.000Z'),
  });

  assert.equal(consumed.ok, true);
  await assert.rejects(
    () =>
      consumeEmailOtpVerification({
        email: 'owner@example.com',
        verificationToken: verification.verificationToken,
        target: db.query,
        now: new Date('2026-06-13T10:03:00.000Z'),
      }),
    /Email verification expired/,
  );
});

test('signup OTP rejects duplicate email before sending', async () => {
  const db = createOtpDb({
    users: [{ email: 'owner@example.com' }],
  });
  const sent = [];

  await assert.rejects(
    () =>
      requestEmailOtp({
        email: 'owner@example.com',
        target: db.query,
        sendEmail: async (payload) => sent.push(payload),
      }),
    /already exists/,
  );
  assert.equal(sent.length, 0);
});

test('signup OTP rejects incorrect code and records an attempt', async () => {
  const db = createOtpDb();
  const sent = [];

  await requestEmailOtp({
    email: 'owner@example.com',
    target: db.query,
    sendEmail: async (payload) => sent.push(payload),
    now: new Date('2026-06-13T10:00:00.000Z'),
  });

  await assert.rejects(
    () =>
      verifyEmailOtp({
        email: 'owner@example.com',
        code: '000000',
        target: db.query,
        now: new Date('2026-06-13T10:01:00.000Z'),
      }),
    /incorrect/,
  );
  assert.equal(db.otps[0].attempts, 1);
});

test('password reset OTP updates the matching cloud user password', async () => {
  const db = createOtpDb({
    users: [
      {
        id: 'user-1',
        business_id: 'business-1',
        email: 'owner@example.com',
        password: 'old-password',
      },
    ],
  });
  const sent = [];

  await requestEmailOtp({
    email: 'owner@example.com',
    purpose: 'password_reset',
    target: db.query,
    sendEmail: async (payload) => sent.push(payload),
    now: new Date('2026-06-13T10:00:00.000Z'),
  });

  const verification = await verifyEmailOtp({
    email: 'owner@example.com',
    purpose: 'password_reset',
    code: sent[0].code,
    target: db.query,
    now: new Date('2026-06-13T10:01:00.000Z'),
  });

  const result = await resetPasswordWithVerifiedOtp({
    email: 'owner@example.com',
    verificationToken: verification.verificationToken,
    newPassword: 'new-secret',
    target: db.query,
    now: new Date('2026-06-13T10:02:00.000Z'),
  });

  assert.equal(result.updatedUsers, 1);
  assert.notEqual(db.users[0].password, 'old-password');
  assert.notEqual(db.users[0].password, 'new-secret');
});

test('password reset OTP rejects unknown emails', async () => {
  const db = createOtpDb();

  await assert.rejects(
    () =>
      requestEmailOtp({
        email: 'missing@example.com',
        purpose: 'password_reset',
        target: db.query,
        sendEmail: async () => {},
      }),
    /No account/,
  );
});

function createOtpDb({ users = [] } = {}) {
  const otps = [];

  const query = async (sql, params = []) => {
    if (/CREATE TABLE|CREATE INDEX/i.test(sql)) {
      return { rows: [] };
    }

    if (/SELECT id\s+FROM users/i.test(sql)) {
      const email = String(params[0] || '').trim().toLowerCase();
      return {
        rows: users.filter((user) => user.email.toLowerCase() === email),
      };
    }

    if (/SELECT id, business_id\s+FROM users/i.test(sql)) {
      const email = String(params[0] || '').trim().toLowerCase();
      return {
        rows: users.filter((user) => user.email.toLowerCase() === email),
      };
    }

    if (/SELECT sent_at\s+FROM email_otps/i.test(sql)) {
      const [email, purpose] = params;
      const rows = otps
        .filter(
          (otp) =>
            otp.email === email &&
            otp.purpose === purpose &&
            otp.consumed_at == null,
        )
        .sort((left, right) => new Date(right.sent_at) - new Date(left.sent_at))
        .slice(0, 1);
      return { rows };
    }

    if (/INSERT INTO email_otps/i.test(sql)) {
      otps.push({
        id: params[0],
        email: params[1],
        purpose: params[2],
        code_hash: params[3],
        attempts: 0,
        expires_at: params[4],
        sent_at: params[5],
        created_at: params[5],
        updated_at: params[5],
        verified_at: null,
        verification_token_hash: null,
        token_expires_at: null,
        consumed_at: null,
      });
      return { rows: [] };
    }

    if (/SELECT \*\s+FROM email_otps/i.test(sql)) {
      const [email, purpose] = params;
      let rows = otps.filter(
        (otp) =>
          otp.email === email &&
          otp.purpose === purpose &&
          otp.consumed_at == null,
      );
      if (/verification_token_hash = \$3/i.test(sql)) {
        rows = rows.filter(
          (otp) =>
            otp.verification_token_hash === params[2] && otp.verified_at != null,
        );
      }
      rows = rows
        .sort(
          (left, right) =>
            new Date(right.verified_at || right.created_at) -
            new Date(left.verified_at || left.created_at),
        )
        .slice(0, 1);
      return { rows };
    }

    if (/SET attempts = attempts \+ 1/i.test(sql)) {
      const otp = otps.find((row) => row.id === params[0]);
      if (otp) {
        otp.attempts += 1;
        otp.updated_at = params[1];
      }
      return { rows: [] };
    }

    if (/SET verified_at = \$2/i.test(sql)) {
      const otp = otps.find((row) => row.id === params[0]);
      if (otp) {
        otp.verified_at = params[1];
        otp.verification_token_hash = params[2];
        otp.token_expires_at = params[3];
        otp.updated_at = params[1];
      }
      return { rows: [] };
    }

    if (/SET consumed_at = \$2/i.test(sql)) {
      const otp = otps.find((row) => row.id === params[0]);
      if (otp) {
        otp.consumed_at = params[1];
        otp.updated_at = params[1];
      }
      return { rows: [] };
    }

    if (/UPDATE users/i.test(sql)) {
      const [email, password, updatedAt] = params;
      const rows = users.filter((user) => user.email.toLowerCase() === email);
      for (const user of rows) {
        user.password = password;
        user.updated_at = updatedAt;
      }
      return { rows: rows.map((user) => ({ id: user.id })), rowCount: rows.length };
    }

    throw new Error(`Unexpected SQL in OTP test: ${sql}`);
  };

  return { otps, query, users };
}
