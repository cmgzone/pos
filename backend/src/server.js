const express = require('express');
const cors = require('cors');

const { config } = require('./config');
const { query, withTransaction, withReadTransaction } = require('./db');
const { syncTables } = require('./syncTables');
const {
  buildRejectedWriteResult,
  canonicalizeRecord,
  prepareIncomingRecord,
} = require('./syncHelpers');
const { maxCursor, normalizeCursor } = require('./syncCursor');
const {
  activateBusinessAccess,
  parseBearerToken,
  refreshBusinessAccess,
  resolveBusinessAccess,
} = require('./businessAccess');
const {
  issueLicense,
  resolveSubscriptionState,
} = require('./licenseTokens');

const app = express();

// Serialize write transactions so revision cursors stay in commit order.
const PUSH_LOCK_CLASS_ID = 41831;
const PUSH_LOCK_OBJECT_ID = 1;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

app.get('/api/health', async (req, res) => {
  try {
    await query('SELECT 1');
    res.json({
      ok: true,
      service: 'velora-pos-sync-backend',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      error: error.message,
    });
  }
});

app.post('/api/license/activate', async (req, res, next) => {
  try {
    const access = await activateBusinessAccess({
      deviceId: req.body?.deviceId,
      deviceName: req.body?.deviceName,
      businessName: req.body?.businessName,
      ownerName: req.body?.ownerName,
      ownerEmail: req.body?.ownerEmail,
    });

    res.json({
      ok: true,
      serverTime: new Date().toISOString(),
      ...access,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/license/refresh', async (req, res, next) => {
  try {
    const accessToken = parseBearerToken(req.headers.authorization);
    if (!accessToken) {
      throw createHttpError(401, 'Authorization token is required');
    }

    const access = await refreshBusinessAccess({
      accessToken,
      deviceId: req.body?.deviceId ?? req.query?.deviceId,
    });

    if (!access) {
      throw createHttpError(401, 'Invalid business access token or device');
    }

    res.json({
      ok: true,
      serverTime: new Date().toISOString(),
      ...access,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

// ── SaaS Authentication ──────────────────────────────────────────────────────

app.post('/api/auth/register', async (req, res, next) => {
  try {
    const businessName = normalizeOptionalText(req.body?.businessName);
    const ownerName = normalizeOptionalText(req.body?.ownerName);
    const ownerEmail = normalizeOptionalText(req.body?.ownerEmail);
    const phone = normalizeOptionalText(req.body?.phone);
    const password = req.body?.password;
    const deviceId = normalizeOptionalText(req.body?.deviceId);
    const deviceName = normalizeOptionalText(req.body?.deviceName);

    if (!businessName) {
      throw createHttpError(400, 'Business name is required');
    }
    if (!ownerName) {
      throw createHttpError(400, 'Owner name is required');
    }
    if (!ownerEmail || !ownerEmail.includes('@')) {
      throw createHttpError(400, 'A valid email address is required');
    }
    if (!password || String(password).length < 6) {
      throw createHttpError(400, 'Password must be at least 6 characters');
    }
    if (!deviceId) {
      throw createHttpError(400, 'deviceId is required');
    }

    const result = await withTransaction(async (client) => {
      // Check for existing user with same email across all businesses
      const existingUser = await client.query(
        `SELECT id, business_id FROM users
         WHERE LOWER(TRIM(email)) = LOWER(TRIM($1)) AND deleted_at IS NULL
         LIMIT 1`,
        [ownerEmail],
      );
      if (existingUser.rows.length > 0) {
        throw createHttpError(
          409,
          'An account with that email already exists. Please sign in instead.',
        );
      }

      const now = new Date();
      const crypto = require('crypto');

      // Create business
      const businessId = crypto.randomUUID();
      await client.query(
        `INSERT INTO businesses (id, name, owner_name, owner_email, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $5)`,
        [businessId, businessName, ownerName, ownerEmail, now.toISOString()],
      );

      // Create trial subscription
      const expiresAt = addDays(now, config.subscriptionTrialDays);
      const graceUntil = addDays(expiresAt, config.subscriptionGraceDays);
      await client.query(
        `INSERT INTO subscriptions (
           business_id, plan, status, expires_at, grace_until,
           last_verified_at, created_at, updated_at
         ) VALUES ($1, 'trial', 'active', $2, $3, $4, $4, $4)`,
        [businessId, expiresAt.toISOString(), graceUntil.toISOString(), now.toISOString()],
      );

      // Create device
      await client.query(
        `INSERT INTO devices (id, business_id, name, last_seen_at, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $4, $4)
         ON CONFLICT (id) DO UPDATE
         SET business_id = EXCLUDED.business_id,
             name = COALESCE(EXCLUDED.name, devices.name),
             last_seen_at = EXCLUDED.last_seen_at,
             updated_at = EXCLUDED.updated_at`,
        [deviceId, businessId, deviceName, now.toISOString()],
      );

      // Create access token
      const accessToken = crypto.randomBytes(32).toString('base64url');
      await client.query(
        `INSERT INTO business_access_tokens (business_id, access_token, created_at, updated_at)
         VALUES ($1, $2, $3, $3)
         ON CONFLICT (business_id) DO UPDATE
         SET access_token = EXCLUDED.access_token,
             updated_at = EXCLUDED.updated_at`,
        [businessId, accessToken, now.toISOString()],
      );

      // Create user
      const userId = crypto.randomUUID();
      await client.query(
        `INSERT INTO users (
           id, business_id, name, email, phone, password, role,
           feature_access_json, allowed_service_ids_json, pos_mode, service_order_scope,
           last_seen_at, created_at, updated_at, sync_status,
           server_revision
         ) VALUES (
           $1, $2, $3, $4, $5, $6, 'ADMIN',
           NULL, NULL, 'both', 'all_visible_services',
           $7, $7, $7, 'synced',
           nextval('sync_revision_seq')
         )`,
        [userId, businessId, ownerName, ownerEmail.toLowerCase(), phone, password, now.toISOString()],
      );

      // Load context for license
      const contextResult = await client.query(
        `SELECT b.id AS business_id, b.name AS business_name,
                s.plan, s.status, s.expires_at, s.grace_until, s.last_verified_at
         FROM businesses b
         JOIN subscriptions s ON s.business_id = b.id
         WHERE b.id = $1`,
        [businessId],
      );
      const businessContext = contextResult.rows[0];

      const license = issueLicense({
        businessId,
        businessName,
        deviceId,
        subscription: businessContext,
        issuedAt: now,
      });

      return {
        business: { id: businessId, name: businessName },
        accessToken,
        subscription: {
          plan: 'trial',
          status: 'active',
          expiresAt: expiresAt.toISOString(),
          graceUntil: graceUntil.toISOString(),
          lastVerifiedAt: now.toISOString(),
        },
        license,
        user: {
          id: userId,
          name: ownerName,
          email: ownerEmail.toLowerCase(),
          phone,
          role: 'ADMIN',
          feature_access_json: null,
          allowed_service_ids_json: null,
          allowed_branch_ids_json: null,
          pos_mode: 'both',
          service_order_scope: 'all_visible_services',
          created_at: now.toISOString(),
          updated_at: now.toISOString(),
        },
      };
    });

    res.json({ ok: true, serverTime: new Date().toISOString(), ...result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/auth/login', async (req, res, next) => {
  try {
    const email = normalizeOptionalText(req.body?.email);
    const password = req.body?.password;
    const deviceId = normalizeOptionalText(req.body?.deviceId);
    const deviceName = normalizeOptionalText(req.body?.deviceName);

    if (!email) {
      throw createHttpError(400, 'Email is required');
    }
    if (!password) {
      throw createHttpError(400, 'Password is required');
    }
    if (!deviceId) {
      throw createHttpError(400, 'deviceId is required');
    }

    const result = await withTransaction(async (client) => {
      const userResult = await client.query(
        `SELECT u.*, b.name AS business_name
         FROM users u
         JOIN businesses b ON b.id = u.business_id
         WHERE LOWER(TRIM(u.email)) = LOWER(TRIM($1))
           AND u.deleted_at IS NULL
         LIMIT 1`,
        [email],
      );

      if (!userResult.rows.length) {
        throw createHttpError(401, 'Invalid email or password');
      }

      const user = userResult.rows[0];

      // Password verification — the client sends the password pre-hashed
      // using the same velora.v1 scheme, so we compare directly.
      // If the password doesn't match, reject.
      if (user.password !== password) {
        throw createHttpError(401, 'Invalid email or password');
      }

      const businessId = user.business_id;
      const now = new Date();

      // Ensure device is linked to this business
      await client.query(
        `INSERT INTO devices (id, business_id, name, last_seen_at, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $4, $4)
         ON CONFLICT (id) DO UPDATE
         SET business_id = EXCLUDED.business_id,
             name = COALESCE(EXCLUDED.name, devices.name),
             last_seen_at = EXCLUDED.last_seen_at,
             updated_at = EXCLUDED.updated_at`,
        [deviceId, businessId, deviceName, now.toISOString()],
      );

      // Ensure access token exists
      const crypto = require('crypto');
      const tokenResult = await client.query(
        `SELECT access_token FROM business_access_tokens WHERE business_id = $1`,
        [businessId],
      );
      let accessToken;
      if (tokenResult.rows.length) {
        accessToken = tokenResult.rows[0].access_token;
      } else {
        accessToken = crypto.randomBytes(32).toString('base64url');
        await client.query(
          `INSERT INTO business_access_tokens (business_id, access_token, created_at, updated_at)
           VALUES ($1, $2, $3, $3)`,
          [businessId, accessToken, now.toISOString()],
        );
      }

      // Update last seen
      await client.query(
        `UPDATE users SET last_seen_at = $2 WHERE id = $1`,
        [user.id, now.toISOString()],
      );

      // Refresh subscription verification
      await client.query(
        `UPDATE subscriptions SET last_verified_at = $2, updated_at = $2 WHERE business_id = $1`,
        [businessId, now.toISOString()],
      );

      // Load subscription for license
      const subResult = await client.query(
        `SELECT * FROM subscriptions WHERE business_id = $1`,
        [businessId],
      );
      const subscription = subResult.rows[0] || {};

      const license = issueLicense({
        businessId,
        businessName: user.business_name,
        deviceId,
        subscription,
        issuedAt: now,
      });

      const subState = resolveSubscriptionState(subscription, now);

      return {
        business: { id: businessId, name: user.business_name },
        accessToken,
        subscription: {
          plan: String(subscription.plan || 'trial'),
          status: subState.status,
          expiresAt: toIsoString(subscription.expires_at),
          graceUntil: toIsoString(subscription.grace_until),
          lastVerifiedAt: now.toISOString(),
        },
        license,
        user: {
          id: user.id,
          name: user.name,
          email: user.email,
          phone: user.phone,
          role: user.role,
          feature_access_json: user.feature_access_json,
          allowed_service_ids_json: user.allowed_service_ids_json,
          allowed_branch_ids_json: user.allowed_branch_ids_json,
          pos_mode: user.pos_mode,
          service_order_scope: user.service_order_scope,
          created_at: toIsoString(user.created_at),
          updated_at: toIsoString(user.updated_at),
        },
      };
    });

    res.json({ ok: true, serverTime: new Date().toISOString(), ...result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/users/upsert', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const rawUser =
      req.body && typeof req.body === 'object' ? req.body.user : null;
    if (!rawUser || typeof rawUser !== 'object' || Array.isArray(rawUser)) {
      throw createHttpError(400, 'user payload is required');
    }

    const prepared = prepareIncomingRecord('users', rawUser);
    if (!prepared.ok) {
      throw createHttpError(400, prepared.error.message);
    }

    const result = await withTransaction(async (client) =>
      upsertRow(client, 'users', prepared.record, businessContext.businessId),
    );

    if (result.status === 'conflict') {
      return res.status(409).json({
        ok: false,
        error: 'The cloud user record is newer than the local copy.',
        conflict: result.conflict,
      });
    }

    if (result.status === 'invalid') {
      return res.status(400).json({
        ok: false,
        error: result.error?.message || 'The user payload was invalid.',
        details: result.error || null,
      });
    }

    res.json({
      ok: true,
      status: result.status,
      user: canonicalizeRecord(
        'users',
        result.row ?? prepared.record,
        { forceSyncedStatus: true },
      ),
    });
  } catch (error) {
    if (
      error?.code === '23505' &&
      String(error?.constraint || '').includes('users_business_email')
    ) {
      return res.status(409).json({
        ok: false,
        error: 'An account with that email already exists in the cloud.',
      });
    }
    next(normalizeRouteError(error));
  }
});

app.get('/api/reports/daily-cashier-summary', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const date = normalizeReportDate(req.query.date);
    const cashierId = normalizeOptionalText(req.query.cashierId);
    const userId = normalizeOptionalText(req.query.userId);
    const branchId = normalizeOptionalText(req.query.branchId);

    if (userId) {
      await updateLastSeen(userId, businessContext.businessId);
    }

    const whereClauses = ['s.business_id = $1', 'DATE(s.created_at) = $2'];
    const params = [businessContext.businessId, date];
    if (cashierId) {
      whereClauses.push(`s.user_id = $${params.length + 1}`);
      params.push(cashierId);
    }
    if (branchId) {
      whereClauses.push(`COALESCE(s.branch_id, 'main_branch') = $${params.length + 1}`);
      params.push(branchId);
    }

    const result = await query(
      `SELECT
         base.cashier_id,
         COALESCE(
           NULLIF(BTRIM(u.name), ''),
           CASE
             WHEN base.cashier_id = 'admin' THEN 'Admin'
             WHEN COALESCE(base.cashier_id, '') = '' THEN 'Unknown Cashier'
             ELSE base.cashier_id
           END
         ) AS cashier_name,
         COALESCE(u.role, 'CASHIER') AS cashier_role,
         u.last_seen_at,
         COUNT(*) FILTER (WHERE base.payment_type NOT LIKE 'refund%')::int AS total_sales,
         COALESCE(SUM(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.total_amount ELSE 0 END), 0) AS total_revenue,
         COALESCE(SUM(CASE WHEN base.payment_type = 'cash' THEN base.total_amount ELSE 0 END), 0) AS cash_revenue,
         COALESCE(SUM(CASE WHEN base.payment_type = 'kopesha' THEN base.total_amount ELSE 0 END), 0) AS kopesha_revenue,
         COALESCE(SUM(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.sale_profit ELSE 0 END), 0) AS gross_profit,
         COALESCE(SUM(CASE WHEN base.payment_type LIKE 'refund%' THEN ABS(base.total_amount) ELSE 0 END), 0) AS refunds_issued,
         COUNT(*) FILTER (WHERE base.payment_type LIKE 'refund%')::int AS refund_count,
         MIN(base.created_at) FILTER (WHERE base.payment_type NOT LIKE 'refund%') AS first_sale_at,
         MAX(base.created_at) FILTER (WHERE base.payment_type NOT LIKE 'refund%') AS last_sale_at
       FROM (
         SELECT
           COALESCE(s.user_id, '') AS cashier_id,
           s.payment_type,
           s.total_amount,
           s.created_at,
           (
             COALESCE((
               SELECT SUM(si.quantity * (si.unit_price - si.unit_cost))
               FROM sale_items si
               WHERE si.sale_id = s.id
                 AND si.business_id = s.business_id
             ), 0)
             + COALESCE((
               SELECT SUM(ssi.quantity * ssi.unit_price)
               FROM service_sale_items ssi
               WHERE ssi.sale_id = s.id
                 AND ssi.business_id = s.business_id
             ), 0)
             - s.discount
           ) AS sale_profit
         FROM sales s
         WHERE ${whereClauses.join(' AND ')}
       ) base
       LEFT JOIN users u
         ON u.id = base.cashier_id
        AND u.business_id = $1
       GROUP BY base.cashier_id, cashier_name, cashier_role, u.last_seen_at
       ORDER BY total_revenue DESC, total_sales DESC, LOWER(cashier_name) ASC`,
      params,
    );

    res.json({
      ok: true,
      date,
      cashiers: result.rows,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/sync/status', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const syncWindow = parseSyncWindow(req.query);
    const userId = normalizeOptionalText(req.query.userId);
    const branchId = normalizeOptionalText(req.query.branchId);

    if (userId) {
      await updateLastSeen(userId, businessContext.businessId);
    }

    const summary = await withReadTransaction(async (client) => {
      const snapshotCursor = await getSnapshotCursor(
        client,
        businessContext.businessId,
        branchId,
      );
      const tables = {};

      for (const table of syncTables) {
        const { sql, params } = buildStatusQuery(
          table.name,
          syncWindow,
          businessContext.businessId,
          branchId,
        );
        const result = await client.query(sql, params);
        tables[table.name] = result.rows[0];
      }

      return {
        snapshotCursor: maxCursor(syncWindow.cursor, snapshotCursor),
        tables,
      };
    });

    res.json({
      ok: true,
      serverTime: new Date().toISOString(),
      businessId: businessContext.businessId,
      since: syncWindow.since,
      cursor: syncWindow.cursor,
      snapshotCursor: summary.snapshotCursor,
      tables: summary.tables,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/sync/pull', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const syncWindow = parseSyncWindow(req.query);
    const userId = normalizeOptionalText(req.query.userId);
    const branchId = normalizeOptionalText(req.query.branchId);

    if (userId) {
      await updateLastSeen(userId, businessContext.businessId);
    }

    const summary = await withReadTransaction(async (client) => {
      const snapshotCursor = await getSnapshotCursor(
        client,
        businessContext.businessId,
        branchId,
      );
      const data = {};

      for (const table of syncTables) {
        const { sql, params } = buildPullQuery(
          table.name,
          syncWindow,
          businessContext.businessId,
          branchId,
        );
        const result = await client.query(sql, params);
        data[table.name] = result.rows.map((row) =>
          canonicalizeRecord(table.name, row, { forceSyncedStatus: true }),
        );
      }

      return {
        data,
        nextCursor: maxCursor(syncWindow.cursor, snapshotCursor),
      };
    });

    res.json({
      ok: true,
      serverTime: new Date().toISOString(),
      businessId: businessContext.businessId,
      since: syncWindow.since,
      cursor: syncWindow.cursor,
      nextCursor: summary.nextCursor,
      data: summary.data,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/sync/push', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const changes =
      req.body && typeof req.body === 'object' ? req.body.changes : null;
    const deviceId = normalizeOptionalText(req.body?.deviceId);
    const userId = normalizeOptionalText(req.body?.userId);
    const branchId = normalizeOptionalText(req.body?.branchId);

    if (!deviceId) {
      return res.status(400).json({ ok: false, error: 'deviceId is required' });
    }

    if (!changes || typeof changes !== 'object') {
      return res
        .status(400)
        .json({ ok: false, error: 'changes payload is required' });
    }

    if (userId) {
      await updateLastSeen(userId, businessContext.businessId);
    }

    const summary = await withTransaction(async (client) => {
      await client.query('SELECT pg_advisory_xact_lock($1, $2)', [
        PUSH_LOCK_CLASS_ID,
        PUSH_LOCK_OBJECT_ID,
      ]);

      const received = {};
      const applied = {};
      const unchanged = {};
      const invalid = {};
      const skipped = {};
      const conflictCount = {};
      const conflicts = {};
      const invalidRows = {};
      let latestAppliedCursor = null;

      for (const table of syncTables) {
        const incomingRows = Array.isArray(changes[table.name])
          ? changes[table.name]
          : [];
        received[table.name] = incomingRows.length;
        applied[table.name] = 0;
        unchanged[table.name] = 0;
        invalid[table.name] = 0;
        skipped[table.name] = 0;
        conflictCount[table.name] = 0;

        const tableConflicts = [];
        const tableInvalidRows = [];

        for (const row of incomingRows) {
          const prepared = prepareIncomingRecord(table.name, row || {});
          if (!prepared.ok) {
            invalid[table.name] += 1;
            tableInvalidRows.push({
              id: row?.id != null ? String(row.id).trim() : null,
              ...prepared.error,
            });
            continue;
          }
          if (branchId && isBranchScopedTable(table.name)) {
            const rowBranchId = normalizeOptionalText(prepared.record.branch_id);
            if (rowBranchId && rowBranchId !== branchId) {
              invalid[table.name] += 1;
              tableInvalidRows.push({
                id: prepared.record.id,
                code: 'branch_scope_mismatch',
                message: 'Record branch does not match the sync branch',
              });
              continue;
            }
            prepared.record.branch_id = rowBranchId || branchId;
          }

          const result = await upsertRow(
            client,
            table.name,
            prepared.record,
            businessContext.businessId,
          );

          if (result.status === 'applied') {
            applied[table.name] += 1;
            latestAppliedCursor = maxCursor(
              latestAppliedCursor,
              result.row?.server_revision,
            );
            continue;
          }

          if (result.status === 'duplicate') {
            unchanged[table.name] += 1;
            continue;
          }

          if (result.status === 'conflict') {
            conflictCount[table.name] += 1;
            tableConflicts.push(result.conflict);
            continue;
          }

          invalid[table.name] += 1;
          if (result.error) {
            tableInvalidRows.push({
              id: prepared.record.id,
              ...result.error,
            });
          }
        }

        skipped[table.name] =
          unchanged[table.name] +
          invalid[table.name] +
          conflictCount[table.name];

        if (tableConflicts.length) {
          conflicts[table.name] = tableConflicts;
        }
        if (tableInvalidRows.length) {
          invalidRows[table.name] = tableInvalidRows;
        }
      }

      return {
        received,
        applied,
        unchanged,
        invalid,
        skipped,
        conflictCount,
        conflicts,
        invalidRows,
        latestAppliedCursor,
      };
    });

    res.json({
      ok: true,
      deviceId,
      businessId: businessContext.businessId,
      serverTime: new Date().toISOString(),
      ...summary,
    });
  } catch (error) {
    next(error);
  }
});

// ── Platform Admin Routes ────────────────────────────────────────────────────
const jwt = require('jsonwebtoken');

function requirePlatformAdmin(req, res, next) {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw createHttpError(401, 'Admin token required');
    }
    const token = authHeader.split(' ')[1];
    jwt.verify(token, config.platformJwtSecret);
    next();
  } catch (error) {
    next(createHttpError(401, 'Invalid or expired admin token'));
  }
}

app.post('/api/platform/login', (req, res, next) => {
  try {
    const email = normalizeOptionalText(req.body?.email);
    const password = req.body?.password;

    if (!email || !password) {
      throw createHttpError(400, 'Email and password are required');
    }

    if (
      email === config.platformAdminEmail &&
      password === config.platformAdminPassword
    ) {
      const token = jwt.sign({ role: 'superadmin' }, config.platformJwtSecret, { expiresIn: '12h' });
      res.json({ ok: true, token });
    } else {
      throw createHttpError(401, 'Invalid admin credentials');
    }
  } catch (error) {
    next(error);
  }
});

app.get('/api/platform/dashboard', requirePlatformAdmin, async (req, res, next) => {
  try {
    const result = await withReadTransaction(async (client) => {
      const bizRes = await client.query('SELECT COUNT(*) FROM businesses');
      const subRes = await client.query("SELECT COUNT(*) FROM subscriptions WHERE status = 'active'");
      const usrRes = await client.query('SELECT COUNT(*) FROM users WHERE deleted_at IS NULL');
      return {
        totalBusinesses: parseInt(bizRes.rows[0].count, 10),
        activeSubscriptions: parseInt(subRes.rows[0].count, 10),
        totalUsers: parseInt(usrRes.rows[0].count, 10),
      };
    });
    res.json({ ok: true, data: result });
  } catch (error) {
    next(error);
  }
});

app.get('/api/platform/businesses', requirePlatformAdmin, async (req, res, next) => {
  try {
    const result = await query(`
      SELECT b.id, b.name, b.owner_name, b.owner_email, b.created_at,
             s.plan, s.status, s.expires_at 
      FROM businesses b
      LEFT JOIN subscriptions s ON s.business_id = b.id
      ORDER BY b.created_at DESC
    `);
    res.json({ ok: true, data: result.rows });
  } catch (error) {
    next(error);
  }
});

app.get('/api/platform/users', requirePlatformAdmin, async (req, res, next) => {
  try {
    const result = await query(`
      SELECT u.id, u.name, u.email, u.role, u.created_at, u.last_seen_at, b.name as business_name
      FROM users u
      LEFT JOIN businesses b ON b.id = u.business_id
      WHERE u.deleted_at IS NULL
      ORDER BY u.created_at DESC
    `);
    res.json({ ok: true, data: result.rows });
  } catch (error) {
    next(error);
  }
});

// ── Platform Admin: AI Configuration ─────────────────────────────────────────

app.get('/api/platform/ai-config', requirePlatformAdmin, async (req, res, next) => {
  try {
    const result = await query(
      'SELECT api_key, model, enabled, updated_at FROM platform_ai_config WHERE id = 1'
    );
    const row = result.rows[0] || { api_key: '', model: 'openai/gpt-4o-mini', enabled: false };
    const hasKey = Boolean(row.api_key && row.api_key.length > 0);
    // Mask the API key for security — only show last 4 chars
    const maskedKey = row.api_key
      ? `${'•'.repeat(Math.max(0, row.api_key.length - 4))}${row.api_key.slice(-4)}`
      : '';
    res.json({
      ok: true,
      data: {
        apiKey: maskedKey,
        hasKey,
        model: row.model,
        enabled: Boolean(row.enabled && hasKey),
        updatedAt: row.updated_at,
      },
    });
  } catch (error) {
    next(error);
  }
});

app.put('/api/platform/ai-config', requirePlatformAdmin, async (req, res, next) => {
  try {
    const model = normalizeOptionalText(req.body?.model) || 'openai/gpt-4o-mini';
    const enabled = Boolean(req.body?.enabled);
    const rawApiKey = typeof req.body?.apiKey === 'string' ? req.body.apiKey.trim() : '';
    const currentResult = await query(
      'SELECT api_key FROM platform_ai_config WHERE id = 1'
    );
    const currentApiKey = currentResult.rows[0]?.api_key || '';

    // Only update the API key if a new one was explicitly provided
    // (not the masked version echoed back)
    const hasNewKey = rawApiKey.length > 0 && !rawApiKey.startsWith('•');
    const nextApiKey = hasNewKey ? rawApiKey : currentApiKey;

    if (enabled && !nextApiKey) {
      throw createHttpError(400, 'Add a valid OpenRouter API key before enabling AI');
    }

    if (hasNewKey) {
      await query(
        `INSERT INTO platform_ai_config (id, api_key, model, enabled, updated_at)
         VALUES (1, $1, $2, $3, NOW())
         ON CONFLICT (id) DO UPDATE
         SET api_key = $1, model = $2, enabled = $3, updated_at = NOW()`,
        [rawApiKey, model, enabled]
      );
    } else {
      await query(
        `INSERT INTO platform_ai_config (id, model, enabled, updated_at)
         VALUES (1, $1, $2, NOW())
         ON CONFLICT (id) DO UPDATE
         SET model = $1, enabled = $2, updated_at = NOW()`,
        [model, enabled]
      );
    }

    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.post('/api/platform/ai-test', requirePlatformAdmin, async (req, res, next) => {
  try {
    const result = await query(
      'SELECT api_key, model FROM platform_ai_config WHERE id = 1'
    );
    const row = result.rows[0];
    if (!row || !row.api_key) {
      throw createHttpError(400, 'No API key configured');
    }

    const fetch = (await import('node-fetch')).default;
    const orResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${row.api_key}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://devispos.com',
        'X-Title': 'Devis POS AI',
      },
      body: JSON.stringify({
        model: row.model,
        messages: [{ role: 'user', content: 'Say "AI is connected!" in exactly those words.' }],
        max_tokens: 30,
      }),
    });

    const orBody = await orResponse.json();
    if (!orResponse.ok) {
      throw createHttpError(
        orResponse.status,
        orBody?.error?.message || 'OpenRouter request failed'
      );
    }

    const content = orBody?.choices?.[0]?.message?.content || '';
    res.json({ ok: true, response: content, model: row.model });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

// ── Business-Auth'd AI Routes ────────────────────────────────────────────────

const AI_RATE_LIMIT = 30; // requests per hour per business
const AI_RATE_WINDOW_MS = 60 * 60 * 1000; // 1 hour

async function checkAiRateLimit(businessId) {
  const now = new Date();
  const result = await query(
    'SELECT request_count, window_start FROM ai_rate_limits WHERE business_id = $1',
    [businessId]
  );

  if (result.rows.length === 0) {
    await query(
      'INSERT INTO ai_rate_limits (business_id, request_count, window_start) VALUES ($1, 1, $2)',
      [businessId, now.toISOString()]
    );
    return { allowed: true, remaining: AI_RATE_LIMIT - 1 };
  }

  const row = result.rows[0];
  const windowStart = new Date(row.window_start);
  const elapsed = now.getTime() - windowStart.getTime();

  if (elapsed > AI_RATE_WINDOW_MS) {
    // Reset window
    await query(
      'UPDATE ai_rate_limits SET request_count = 1, window_start = $2 WHERE business_id = $1',
      [businessId, now.toISOString()]
    );
    return { allowed: true, remaining: AI_RATE_LIMIT - 1 };
  }

  if (row.request_count >= AI_RATE_LIMIT) {
    const resetIn = Math.ceil((AI_RATE_WINDOW_MS - elapsed) / 60000);
    return { allowed: false, remaining: 0, resetInMinutes: resetIn };
  }

  await query(
    'UPDATE ai_rate_limits SET request_count = request_count + 1 WHERE business_id = $1',
    [businessId]
  );
  return { allowed: true, remaining: AI_RATE_LIMIT - row.request_count - 1 };
}

app.get('/api/ai/config', async (req, res, next) => {
  try {
    await requireBusinessContext(req);
    const result = await query(
      'SELECT api_key, model, enabled FROM platform_ai_config WHERE id = 1'
    );
    const row = result.rows[0] || { api_key: '', model: 'openai/gpt-4o-mini', enabled: false };
    res.json({
      ok: true,
      aiEnabled: Boolean(row.enabled && row.api_key),
      aiModel: row.model,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/chat', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);

    // Check if AI is enabled
    const configResult = await query(
      'SELECT api_key, model, enabled FROM platform_ai_config WHERE id = 1'
    );
    const aiConfig = configResult.rows[0];
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }

    // Rate limiting
    const rateCheck = await checkAiRateLimit(businessContext.businessId);
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`
      );
    }

    const messages = req.body?.messages;
    if (!Array.isArray(messages) || messages.length === 0) {
      throw createHttpError(400, 'messages array is required');
    }

    // Build system prompt with business context
    const systemPrompt = req.body?.systemPrompt || '';

    const fullMessages = [
      ...(systemPrompt ? [{ role: 'system', content: systemPrompt }] : []),
      ...messages,
    ];

    const fetch = (await import('node-fetch')).default;
    const orResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${aiConfig.api_key}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://devispos.com',
        'X-Title': 'Devis POS AI',
      },
      body: JSON.stringify({
        model: aiConfig.model,
        messages: fullMessages,
        max_tokens: 1024,
        temperature: 0.7,
      }),
    });

    const orBody = await orResponse.json();
    if (!orResponse.ok) {
      const errorMsg = orBody?.error?.message || 'OpenRouter request failed';
      throw createHttpError(orResponse.status === 401 ? 502 : orResponse.status, errorMsg);
    }

    const content = orBody?.choices?.[0]?.message?.content || '';
    const usage = orBody?.usage || {};

    res.json({
      ok: true,
      content,
      model: aiConfig.model,
      usage: {
        promptTokens: usage.prompt_tokens || 0,
        completionTokens: usage.completion_tokens || 0,
      },
      remaining: rateCheck.remaining,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.use((error, req, res, next) => {

  const statusCode =
    error && Number.isInteger(error.statusCode) ? error.statusCode : 500;

  res.status(statusCode).json({
    ok: false,
    error: error.message || 'Unexpected server error',
  });
});

app.listen(config.port, () => {
  console.log(
    `Velora POS sync backend listening on port ${config.port} (${config.nodeEnv})`,
  );
});

async function requireBusinessContext(req) {
  const accessToken = parseBearerToken(req.headers.authorization);
  if (!accessToken) {
    throw createHttpError(401, 'Authorization token is required');
  }

  const deviceId = normalizeOptionalText(
    req.query?.deviceId ?? req.body?.deviceId ?? req.headers['x-device-id'],
  );
  if (!deviceId) {
    throw createHttpError(400, 'deviceId is required');
  }

  const businessContext = await resolveBusinessAccess({
    accessToken,
    deviceId,
  });
  if (!businessContext) {
    throw createHttpError(401, 'Invalid business access token or device');
  }
  if (!businessContext.usable) {
    throw createHttpError(
      402,
      'Subscription expired. Renew the business subscription to continue syncing.',
    );
  }

  return businessContext;
}

async function updateLastSeen(userId, businessId) {
  const normalizedUserId = normalizeOptionalText(userId);
  const normalizedBusinessId = normalizeOptionalText(businessId);
  if (!normalizedUserId || !normalizedBusinessId) {
    return;
  }
  try {
    await query(
      `
      UPDATE users
      SET last_seen_at = NOW()
      WHERE id = $1 AND business_id = $2
      `,
      [normalizedUserId, normalizedBusinessId],
    );
  } catch (error) {
    console.error('Failed to update last_seen_at:', error);
  }
}

function parseSyncWindow(queryParams) {
  const rawCursor = queryParams?.cursor;
  const rawSince = queryParams?.since;
  const hasCursor = rawCursor != null && String(rawCursor).trim() !== '';
  const hasSince = rawSince != null && String(rawSince).trim() !== '';

  if (hasCursor && hasSince) {
    throw createHttpError(400, 'Use either cursor or since, not both');
  }

  let cursor = null;
  if (hasCursor) {
    try {
      cursor = normalizeCursor(rawCursor);
    } catch (error) {
      throw createHttpError(400, 'Invalid cursor');
    }
  }

  return {
    cursor,
    since: normalizeSince(rawSince),
  };
}

function normalizeSince(value) {
  if (value == null || String(value).trim() === '') {
    return null;
  }

  const parsed = new Date(String(value));
  if (Number.isNaN(parsed.getTime())) {
    throw createHttpError(400, 'Invalid since timestamp');
  }

  return parsed.toISOString();
}

function normalizeOptionalText(value) {
  if (value == null) {
    return null;
  }

  const normalized = String(value).trim();
  return normalized === '' ? null : normalized;
}

function normalizeReportDate(value) {
  const normalized = normalizeOptionalText(value);
  if (!normalized) {
    return new Date().toISOString().slice(0, 10);
  }

  if (!/^\d{4}-\d{2}-\d{2}$/.test(normalized)) {
    throw createHttpError(400, 'Invalid report date');
  }

  return normalized;
}

function createHttpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function normalizeRouteError(error) {
  if (error && Number.isInteger(error.statusCode)) {
    return error;
  }

  const message = String(error?.message || '');
  if (message.endsWith('is required')) {
    return createHttpError(400, message);
  }

  return error;
}

function addDays(date, days) {
  const next = new Date(date.getTime());
  next.setUTCDate(next.getUTCDate() + Math.max(0, Number(days) || 0));
  return next;
}

function toIsoString(value) {
  if (!value) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function branchScopeClause(tableName, branchId, params) {
  if (!branchId || !isBranchScopedTable(tableName)) {
    return '';
  }
  params.push(branchId);
  return ` AND COALESCE(branch_id, 'main_branch') = $${params.length}`;
}

function isBranchScopedTable(tableName) {
  const table = syncTables.find((entry) => entry.name === tableName);
  return Boolean(table?.columns?.includes('branch_id'));
}

function buildStatusQuery(tableName, syncWindow, businessId, branchId) {
  const baseParams = [businessId];
  const branchClause = branchScopeClause(tableName, branchId, baseParams);
  if (syncWindow.cursor != null) {
    const params = [...baseParams, syncWindow.cursor];
    const cursorParam = `$${params.length}`;
    return {
      sql: `SELECT
              COUNT(*)::int AS total_records,
              COUNT(*) FILTER (WHERE deleted_at IS NOT NULL)::int AS deleted_records,
              COUNT(*) FILTER (WHERE server_revision > ${cursorParam}::bigint)::int AS changed_since,
              MAX(updated_at) AS latest_update,
              MAX(server_revision)::text AS latest_revision
            FROM ${tableName}
            WHERE business_id = $1${branchClause}`,
      params,
    };
  }

  if (syncWindow.since != null) {
    const params = [...baseParams, syncWindow.since];
    const sinceParam = `$${params.length}`;
    return {
      sql: `SELECT
              COUNT(*)::int AS total_records,
              COUNT(*) FILTER (WHERE deleted_at IS NOT NULL)::int AS deleted_records,
              COUNT(*) FILTER (WHERE updated_at > ${sinceParam})::int AS changed_since,
              MAX(updated_at) AS latest_update,
              MAX(server_revision)::text AS latest_revision
            FROM ${tableName}
            WHERE business_id = $1${branchClause}`,
      params,
    };
  }

  return {
    sql: `SELECT
            COUNT(*)::int AS total_records,
            COUNT(*) FILTER (WHERE deleted_at IS NOT NULL)::int AS deleted_records,
            NULL::int AS changed_since,
            MAX(updated_at) AS latest_update,
            MAX(server_revision)::text AS latest_revision
          FROM ${tableName}
          WHERE business_id = $1${branchClause}`,
    params: baseParams,
  };
}

function buildPullQuery(tableName, syncWindow, businessId, branchId) {
  const baseParams = [businessId];
  const branchClause = branchScopeClause(tableName, branchId, baseParams);
  if (syncWindow.cursor != null) {
    const params = [...baseParams, syncWindow.cursor];
    const cursorParam = `$${params.length}`;
    return {
      sql: `SELECT *
            FROM ${tableName}
            WHERE business_id = $1
              ${branchClause}
              AND server_revision > ${cursorParam}::bigint
            ORDER BY server_revision ASC, id ASC`,
      params,
    };
  }

  if (syncWindow.since != null) {
    const params = [...baseParams, syncWindow.since];
    const sinceParam = `$${params.length}`;
    return {
      sql: `SELECT *
            FROM ${tableName}
            WHERE business_id = $1
              ${branchClause}
              AND updated_at > ${sinceParam}
            ORDER BY updated_at ASC, id ASC`,
      params,
    };
  }

  return {
    sql: `SELECT *
          FROM ${tableName}
          WHERE business_id = $1${branchClause}
          ORDER BY updated_at ASC, id ASC`,
    params: baseParams,
  };
}

async function getSnapshotCursor(client, businessId, branchId = null) {
  const revisionUnion = syncTables
    .map(
      (table) => {
        const branchClause =
          branchId && isBranchScopedTable(table.name)
            ? " AND COALESCE(branch_id, 'main_branch') = $2"
            : '';
        return `SELECT MAX(server_revision) AS latest_revision FROM ${table.name} WHERE business_id = $1${branchClause}`;
      },
    )
    .join(' UNION ALL ');

  const result = await client.query(
    `SELECT MAX(latest_revision)::text AS snapshot_cursor
     FROM (${revisionUnion}) AS revision_snapshot`,
    branchId ? [businessId, branchId] : [businessId],
  );

  return normalizeCursor(result.rows[0]?.snapshot_cursor);
}

async function upsertRow(client, tableName, row, businessId) {
  const scopedRow = {
    ...row,
    business_id: businessId,
  };
  const columns = Object.keys(scopedRow);
  if (!columns.length) {
    return {
      status: 'invalid',
      error: {
        code: 'empty_record',
        message: 'Record did not contain any writable columns',
      },
    };
  }

  const values = columns.map((column) => scopedRow[column]);
  const insertColumns = columns.join(', ');
  const placeholders = columns.map((_, index) => `$${index + 1}`).join(', ');
  const updateColumns = columns.filter(
    (column) => column !== 'id' && column !== 'business_id',
  );
  const updateAssignments = [
    ...updateColumns.map((column) => `${column} = EXCLUDED.${column}`),
    "server_revision = nextval('sync_revision_seq')",
  ].join(', ');

  const sql = `
    INSERT INTO ${tableName} (${insertColumns})
    VALUES (${placeholders})
    ON CONFLICT (id) DO UPDATE
    SET ${updateAssignments}
    WHERE ${tableName}.business_id = EXCLUDED.business_id
      AND (
        ${tableName}.updated_at IS NULL
        OR EXCLUDED.updated_at > ${tableName}.updated_at
      )
    RETURNING *
  `;

  const result = await client.query(sql, values);
  if (result.rowCount > 0) {
    return {
      status: 'applied',
      row: result.rows[0],
    };
  }

  const existingResult = await client.query(
    `SELECT * FROM ${tableName} WHERE id = $1`,
    [row.id],
  );
  const existingRow = existingResult.rows[0];

  if (existingRow && existingRow.business_id !== businessId) {
    return {
      status: 'invalid',
      error: {
        code: 'cross_business_id_conflict',
        message: 'Record id already exists for another business',
      },
    };
  }

  return buildRejectedWriteResult(tableName, row, existingRow);
}
