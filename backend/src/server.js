const express = require('express');
const cors = require('cors');
const crypto = require('crypto');

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
const {
  hashPassword,
  needsPasswordRehash,
  normalizePasswordForStorage,
  verifyPassword,
} = require('./passwords');
const {
  ensurePikiProactiveSchema,
  refreshBusinessInsights,
  startPikiProactiveWorker,
} = require('./pikiProactive');
const {
  FEATURE_KEYS,
  applySellingModeToEntitlements,
  ensureSubscriptionSchema,
  isHttpsUrl,
  listPaymentGateways,
  listPlans,
  listPublicPlans,
  listPublicMarkets,
  loadEntitlementsForPlan,
  loadPaymentGateway,
  loadPlatformSubscriptionSettings,
  normalizeCountryCode,
  normalizePlanInput,
  normalizePriceInput,
  normalizeProvider,
  normalizeSellingMode,
  renewalBaseDate,
  resolvePlanPrice,
  savePaymentGateway,
  savePlatformSubscriptionSettings,
  validatePaymentGatewayConfiguration,
  validateSellingModeEntitlement,
} = require('./subscriptionPlans');
const {
  ensureCommunicationSchema,
  listMessageGateways,
  saveMessageGateway,
  getBusinessCommunicationSettings,
  saveBusinessCommunicationSettings,
  sendBusinessMessage,
  listMessageLogs,
} = require('./communication');
const {
  ensurePosPaymentSchema,
  loadBusinessPaymentGateway,
  saveBusinessPaymentGateway,
  loadPosMpesaConfig,
  createMpesaPosCheckout,
  loadPosPayment,
  linkPosPaymentToSale,
  handlePosMpesaCallback,
} = require('./posPayments');
const {
  ensureEtimsSchema,
  loadPlatformEtimsConfig,
  savePlatformEtimsConfig,
  getBusinessEtimsSettings,
  saveBusinessEtimsSettings,
  submitEtimsSale,
  listEtimsSubmissions,
  platformEtimsReadinessErrors,
} = require('./etims');
const { searchWithSerpApi } = require('./serpApi');

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
      countryCode: req.body?.countryCode,
      currency: req.body?.currency,
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
    const requestedCountry = normalizeOptionalText(req.body?.countryCode);
    const requestedCurrency = normalizeBusinessCurrency(req.body?.currency);
    const requestedProvider = normalizeOptionalText(req.body?.provider);
    const requestedPlanCode = normalizeOptionalText(
      req.body?.requestedPlanCode || req.body?.planCode || req.body?.plan,
    );
    const requestedSellingMode = normalizeSellingMode(
      req.body?.sellingMode || req.body?.businessType || req.body?.saleMode,
    );

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
    if (!requestedCountry) {
      throw createHttpError(400, 'Country is required');
    }
    const passwordForStorage = normalizePasswordForStorage(password);

    await ensureSubscriptionSchema();
    const markets = await listPublicMarkets();
    const market = selectSubscriptionMarket(markets, {
      countryCode: requestedCountry,
      provider: requestedProvider,
    });
    if (!market) {
      throw createHttpError(400, 'No active subscription market is configured for this country');
    }
    const countryCode = normalizeCountryCode(market.countryCode || requestedCountry);
    const currency = requestedCurrency || displayCurrencyForCountry(countryCode);
    const provider = normalizeProvider(market.provider || requestedProvider);
    const registrationSelection = await resolveRegistrationPlanSelection({
      requestedPlanCode,
      countryCode,
      provider,
    });
    if (!registrationSelection) {
      throw createHttpError(
        404,
        requestedPlanCode
          ? 'No active price is configured for the selected plan'
          : 'No free trial plan is configured for this country',
      );
    }
    const selectedPlanCode = registrationSelection.planCode;
    const selectedPrice = registrationSelection.price;
    const planEntitlements = await loadEntitlementsForPlan(selectedPlanCode);
    const sellingMode = selectSellingModeForPlan(
      planEntitlements,
      requestedSellingMode,
    );
    const selectedEntitlements = applySellingModeToEntitlements(
      planEntitlements,
      sellingMode,
    );
    const subscriptionSettings = await loadPlatformSubscriptionSettings();
    const activatesSelectedPlan = Number(selectedPrice.amountMinor || 0) === 0;
    const initialPlan = activatesSelectedPlan ? selectedPlanCode : 'trial';

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
        `INSERT INTO businesses (id, name, owner_name, owner_email, country_code, currency, selling_mode, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8)`,
        [
          businessId,
          businessName,
          ownerName,
          ownerEmail,
          countryCode,
          currency,
          sellingMode,
          now.toISOString(),
        ],
      );

      const subscriptionDays =
        initialPlan === 'trial'
          ? subscriptionSettings.trialDays
          : billingPeriodDays(selectedPrice.billingPeriod);
      const expiresAt = addDays(now, subscriptionDays);
      const graceUntil = addDays(expiresAt, subscriptionSettings.graceDays);
      await client.query(
        `INSERT INTO subscriptions (
           business_id, plan, status, expires_at, grace_until,
           last_verified_at, created_at, updated_at
         ) VALUES ($1, $2, 'active', $3, $4, $5, $5, $5)`,
        [
          businessId,
          initialPlan,
          expiresAt.toISOString(),
          graceUntil.toISOString(),
          now.toISOString(),
        ],
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
        [
          userId,
          businessId,
          ownerName,
          ownerEmail.toLowerCase(),
          phone,
          passwordForStorage,
          now.toISOString(),
        ],
      );

      // Load context for license
      const contextResult = await client.query(
        `SELECT b.id AS business_id, b.name AS business_name, b.country_code, b.currency, b.selling_mode,
                s.plan, s.status, s.expires_at, s.grace_until, s.last_verified_at
         FROM businesses b
         JOIN subscriptions s ON s.business_id = b.id
         WHERE b.id = $1`,
        [businessId],
      );
      const businessContext = contextResult.rows[0];
      const entitlements = applySellingModeToEntitlements(
        await loadEntitlementsForPlan(businessContext.plan, client),
        sellingMode,
      );

      const license = issueLicense({
        businessId,
        businessName,
        countryCode,
        sellingMode,
        deviceId,
        subscription: businessContext,
        entitlements,
        issuedAt: now,
      });

      return {
        business: { id: businessId, name: businessName, countryCode, currency, sellingMode },
        accessToken,
        subscription: {
          plan: initialPlan,
          status: 'active',
          expiresAt: expiresAt.toISOString(),
          graceUntil: graceUntil.toISOString(),
          lastVerifiedAt: now.toISOString(),
          entitlements,
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
        selectedPlan: {
          code: selectedPlanCode,
          entitlements: selectedEntitlements,
          price: selectedPrice,
        },
        selectedMarket: market,
        checkoutRequired: !activatesSelectedPlan,
        checkoutContext: !activatesSelectedPlan
          ? {
              planCode: selectedPlanCode,
              countryCode,
              provider,
              price: selectedPrice,
              market,
            }
          : null,
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
        `SELECT u.*, b.name AS business_name, b.country_code, b.currency, b.selling_mode
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

      if (!verifyPassword(user.password, password)) {
        throw createHttpError(401, 'Invalid email or password');
      }

      const businessId = user.business_id;
      const now = new Date();
      const passwordNeedsRehash = needsPasswordRehash(user.password);

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

      // Update last seen and migrate older client-side hashes after a valid
      // plaintext login.
      await client.query(
        passwordNeedsRehash
          ? `UPDATE users
             SET last_seen_at = $2,
                 password = $3,
                 server_revision = nextval('sync_revision_seq')
             WHERE id = $1`
          : `UPDATE users SET last_seen_at = $2 WHERE id = $1`,
        passwordNeedsRehash
          ? [user.id, now.toISOString(), hashPassword(password)]
          : [user.id, now.toISOString()],
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
      const entitlements = applySellingModeToEntitlements(
        await loadEntitlementsForPlan(subscription.plan, client),
        user.selling_mode,
      );

      const license = issueLicense({
        businessId,
        businessName: user.business_name,
        countryCode: user.country_code,
        sellingMode: user.selling_mode,
        deviceId,
        subscription,
        entitlements,
        issuedAt: now,
      });

      const subState = resolveSubscriptionState(subscription, now);

      return {
        business: {
          id: businessId,
          name: user.business_name,
          countryCode: normalizeCountryCode(user.country_code || 'GLOBAL'),
          currency: normalizeBusinessCurrency(user.currency) || displayCurrencyForCountry(user.country_code),
          sellingMode: normalizeSellingMode(user.selling_mode) || 'combo',
        },
        accessToken,
        subscription: {
          plan: String(subscription.plan || 'trial'),
          status: subState.status,
          expiresAt: toIsoString(subscription.expires_at),
          graceUntil: toIsoString(subscription.grace_until),
          lastVerifiedAt: now.toISOString(),
          entitlements,
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

    const userRecord = normalizeUserRecordForStorage(prepared.record);

    const result = await withTransaction(async (client) => {
      const validation = await validatePlanWrite(
        client,
        'users',
        userRecord,
        businessContext,
      );
      if (!validation.ok) {
        return { status: 'invalid', error: validation.error };
      }
      return upsertRow(client, 'users', userRecord, businessContext.businessId);
    });

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
        result.row ?? userRecord,
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

          const storageRecord = table.name === 'users'
            ? normalizeUserRecordForStorage(prepared.record)
            : prepared.record;

          const validation = await validatePlanWrite(
            client,
            table.name,
            storageRecord,
            businessContext,
          );
          if (!validation.ok) {
            invalid[table.name] += 1;
            tableInvalidRows.push({
              id: prepared.record.id,
              ...validation.error,
            });
            continue;
          }

          const result = await upsertRow(
            client,
            table.name,
            storageRecord,
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
      const subRes = await client.query(`
        SELECT COUNT(*)
        FROM subscriptions
        WHERE status = 'active'
          AND expires_at >= NOW()
      `);
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
    await ensureSubscriptionSchema();
    const result = await query(`
      SELECT b.id, b.name, b.owner_name, b.owner_email, b.country_code, b.currency, b.selling_mode, b.created_at,
             s.plan,
             CASE
               WHEN s.status NOT IN ('active', 'grace') THEN s.status
               WHEN NOW() > s.grace_until THEN 'expired'
               WHEN NOW() > s.expires_at THEN 'grace'
               ELSE 'active'
             END AS status,
             s.expires_at, s.grace_until
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

app.get('/api/platform/plans', requirePlatformAdmin, async (req, res, next) => {
  try {
    const plans = await listPlans({ includeInactive: true });
    res.json({ ok: true, data: plans, features: Object.values(FEATURE_KEYS) });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/subscription-settings', requirePlatformAdmin, async (req, res, next) => {
  try {
    const settings = await loadPlatformSubscriptionSettings();
    res.json({ ok: true, data: settings });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/readiness', requirePlatformAdmin, async (req, res, next) => {
  try {
    const readiness = await loadPlatformReadiness();
    res.json({ ok: true, data: readiness });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/app/version', async (req, res, next) => {
  try {
    const version = await loadAppVersionConfig();
    res.json({ ok: true, data: version });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/platform/subscription-settings', requirePlatformAdmin, async (req, res, next) => {
  try {
    const settings = await savePlatformSubscriptionSettings(req.body || {});
    res.json({ ok: true, data: settings });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/platform/plans', requirePlatformAdmin, async (req, res, next) => {
  try {
    const plan = await saveSubscriptionPlan(req.body || {});
    res.status(201).json({ ok: true, data: plan });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/platform/plans/:code', requirePlatformAdmin, async (req, res, next) => {
  try {
    const plan = await saveSubscriptionPlan({
      ...(req.body || {}),
      code: req.params.code,
    });
    res.json({ ok: true, data: plan });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/payment-gateways', requirePlatformAdmin, async (req, res, next) => {
  try {
    const gateways = await listPaymentGateways({ includeSecrets: false });
    res.json({ ok: true, data: gateways });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/platform/payment-gateways/:provider', requirePlatformAdmin, async (req, res, next) => {
  try {
    const gateway = await savePaymentGateway(req.params.provider, req.body || {});
    res.json({ ok: true, data: gateway });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/message-gateways', requirePlatformAdmin, async (req, res, next) => {
  try {
    const gateways = await listMessageGateways({ includeSecrets: false });
    res.json({ ok: true, data: gateways });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/platform/message-gateways/:provider', requirePlatformAdmin, async (req, res, next) => {
  try {
    const gateway = await saveMessageGateway(req.params.provider, req.body || {});
    res.json({ ok: true, data: gateway });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/etims-config', requirePlatformAdmin, async (req, res, next) => {
  try {
    const config = await loadPlatformEtimsConfig({ includeSecrets: false });
    res.json({ ok: true, data: config });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/platform/etims-config', requirePlatformAdmin, async (req, res, next) => {
  try {
    const config = await savePlatformEtimsConfig(req.body || {});
    res.json({ ok: true, data: config });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/app-version', requirePlatformAdmin, async (req, res, next) => {
  try {
    const version = await loadAppVersionConfig();
    res.json({ ok: true, data: version });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/platform/app-version', requirePlatformAdmin, async (req, res, next) => {
  try {
    const version = await saveAppVersionConfig(req.body || {});
    res.json({ ok: true, data: version });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/platform/businesses/:businessId/subscription', requirePlatformAdmin, async (req, res, next) => {
  try {
    await ensureSubscriptionSchema();
    const businessId = normalizeOptionalText(req.params.businessId);
    const plan = normalizeOptionalText(req.body?.plan || req.body?.planCode);
    const status = normalizeOptionalText(req.body?.status) || 'active';
    if (!businessId || !plan) {
      throw createHttpError(400, 'businessId and plan are required');
    }

    const businessResult = await query(
      'SELECT id, selling_mode FROM businesses WHERE id = $1 LIMIT 1',
      [businessId],
    );
    if (!businessResult.rows.length) {
      throw createHttpError(404, 'Business not found');
    }

    const planResult = await query(
      'SELECT code FROM subscription_plans WHERE code = $1 LIMIT 1',
      [plan],
    );
    if (!planResult.rows.length) {
      throw createHttpError(404, 'Subscription plan not found');
    }
    const planEntitlements = await loadEntitlementsForPlan(plan);
    const hasExplicitSellingMode =
      req.body?.sellingMode != null || req.body?.selling_mode != null;
    const requestedSellingMode = normalizeSellingMode(
      req.body?.sellingMode ?? req.body?.selling_mode,
    );
    if (hasExplicitSellingMode && !requestedSellingMode) {
      throw createHttpError(400, 'Choose products, services, or combo for the business type.');
    }
    const currentSellingMode = normalizeSellingMode(businessResult.rows[0].selling_mode);
    const sellingMode = selectSellingModeForPlan(
      planEntitlements,
      hasExplicitSellingMode ? requestedSellingMode : null,
      hasExplicitSellingMode ? null : currentSellingMode,
    );

    const now = new Date();
    const subscriptionSettings = await loadPlatformSubscriptionSettings();
    const expiresAt =
      parseOptionalDate(req.body?.expiresAt || req.body?.expires_at) ||
      addDays(now, plan === 'trial' ? subscriptionSettings.trialDays : 30);
    const graceUntil =
      parseOptionalDate(req.body?.graceUntil || req.body?.grace_until) ||
      addDays(expiresAt, subscriptionSettings.graceDays);

    const result = await withTransaction(async (client) => {
      await client.query(
        `
        UPDATE businesses
        SET selling_mode = $2, updated_at = $3
        WHERE id = $1
        `,
        [businessId, sellingMode, now.toISOString()],
      );
      return client.query(
        `
        INSERT INTO subscriptions (
          business_id,
          plan,
          status,
          expires_at,
          grace_until,
          last_verified_at,
          created_at,
          updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $6, $6)
        ON CONFLICT (business_id) DO UPDATE
        SET plan = EXCLUDED.plan,
            status = EXCLUDED.status,
            expires_at = EXCLUDED.expires_at,
            grace_until = EXCLUDED.grace_until,
            last_verified_at = EXCLUDED.last_verified_at,
            updated_at = EXCLUDED.updated_at
        RETURNING *
        `,
        [
          businessId,
          plan,
          status,
          expiresAt.toISOString(),
          graceUntil.toISOString(),
          now.toISOString(),
        ],
      );
    });

    const entitlements = applySellingModeToEntitlements(planEntitlements, sellingMode);
    res.json({
      ok: true,
      data: { ...result.rows[0], selling_mode: sellingMode, entitlements },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/ai-config', requirePlatformAdmin, async (req, res, next) => {
  try {
    await ensureAiVoiceColumns();
    const result = await query(
      `SELECT api_key, serp_api_key, model, image_model, stt_model, tts_model, tts_voice, enabled, updated_at
       FROM platform_ai_config
       WHERE id = 1`
    );
    const row = result.rows[0] || {
      api_key: '',
      serp_api_key: '',
      model: 'openai/gpt-4o-mini',
      image_model: DEFAULT_IMAGE_MODEL,
      stt_model: DEFAULT_STT_MODEL,
      tts_model: DEFAULT_TTS_MODEL,
      tts_voice: DEFAULT_TTS_VOICE,
      enabled: false,
    };
    const hasKey = Boolean(row.api_key && row.api_key.length > 0);
    const effectiveSerpApiKey = row.serp_api_key || config.serpApiKey || '';
    const hasSerpApiKey = Boolean(effectiveSerpApiKey);
    // Mask the API key for security — only show last 4 chars
    const maskedKey = row.api_key
      ? `${'•'.repeat(Math.max(0, row.api_key.length - 4))}${row.api_key.slice(-4)}`
      : '';
    res.json({
      ok: true,
      data: {
        apiKey: maskedKey,
        hasKey,
        serpApiKey: maskSecret(effectiveSerpApiKey),
        hasSerpApiKey,
        serpApiKeySource: row.serp_api_key
          ? 'database'
          : (config.serpApiKey ? 'environment' : 'none'),
        model: row.model,
        imageModel: row.image_model || DEFAULT_IMAGE_MODEL,
        sttModel: row.stt_model || DEFAULT_STT_MODEL,
        ttsModel: row.tts_model || DEFAULT_TTS_MODEL,
        ttsVoice: row.tts_voice || DEFAULT_TTS_VOICE,
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
    await ensureAiVoiceColumns();
    const model = normalizeOptionalText(req.body?.model) || 'openai/gpt-4o-mini';
    const imageModel = normalizeOptionalText(req.body?.imageModel) || DEFAULT_IMAGE_MODEL;
    const sttModel = normalizeOptionalText(req.body?.sttModel) || DEFAULT_STT_MODEL;
    const ttsModel = normalizeOptionalText(req.body?.ttsModel) || DEFAULT_TTS_MODEL;
    const ttsVoice = normalizeOptionalText(req.body?.ttsVoice) || DEFAULT_TTS_VOICE;
    const enabled = Boolean(req.body?.enabled);
    const rawApiKey = typeof req.body?.apiKey === 'string' ? req.body.apiKey.trim() : '';
    const rawSerpApiKey = typeof req.body?.serpApiKey === 'string' ? req.body.serpApiKey.trim() : '';
    const currentResult = await query(
      'SELECT api_key, serp_api_key FROM platform_ai_config WHERE id = 1'
    );
    const currentApiKey = currentResult.rows[0]?.api_key || '';
    const currentSerpApiKey = currentResult.rows[0]?.serp_api_key || '';

    // Only update the API key if a new one was explicitly provided
    // (not the masked version echoed back)
    const hasNewKey = rawApiKey.length > 0 && !rawApiKey.startsWith('•');
    const nextApiKey = hasNewKey ? rawApiKey : currentApiKey;
    const hasNewSerpApiKey =
      rawSerpApiKey.length > 0 &&
      !rawSerpApiKey.startsWith('â€¢') &&
      !rawSerpApiKey.startsWith('*');
    const nextSerpApiKey = hasNewSerpApiKey ? rawSerpApiKey : currentSerpApiKey;

    if (enabled && !nextApiKey) {
      throw createHttpError(400, 'Add a valid OpenRouter API key before enabling AI');
    }

    if (hasNewKey) {
      await query(
        `INSERT INTO platform_ai_config (id, api_key, serp_api_key, model, image_model, stt_model, tts_model, tts_voice, enabled, updated_at)
         VALUES (1, $1, $2, $3, $4, $5, $6, $7, $8, NOW())
         ON CONFLICT (id) DO UPDATE
         SET api_key = $1,
             serp_api_key = $2,
             model = $3,
             image_model = $4,
             stt_model = $5,
             tts_model = $6,
             tts_voice = $7,
             enabled = $8,
             updated_at = NOW()`,
        [rawApiKey, nextSerpApiKey, model, imageModel, sttModel, ttsModel, ttsVoice, enabled]
      );
    } else {
      await query(
        `INSERT INTO platform_ai_config (id, serp_api_key, model, image_model, stt_model, tts_model, tts_voice, enabled, updated_at)
         VALUES (1, $1, $2, $3, $4, $5, $6, $7, NOW())
         ON CONFLICT (id) DO UPDATE
         SET serp_api_key = $1,
             model = $2,
             image_model = $3,
             stt_model = $4,
             tts_model = $5,
             tts_voice = $6,
             enabled = $7,
             updated_at = NOW()`,
        [nextSerpApiKey, model, imageModel, sttModel, ttsModel, ttsVoice, enabled]
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
        'HTTP-Referer': 'https://pikipos.com',
        'X-Title': 'Piki POS AI',
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

// Platform web search diagnostics
app.post('/api/platform/web-search-test', requirePlatformAdmin, async (req, res, next) => {
  try {
    await ensureAiVoiceColumns();
    const result = await query(
      'SELECT serp_api_key FROM platform_ai_config WHERE id = 1',
    );
    const row = result.rows[0] || {};
    const serpApiKey = row.serp_api_key || config.serpApiKey;
    if (!serpApiKey) {
      throw createHttpError(400, 'No SerpAPI key configured');
    }

    const fetch = (await import('node-fetch')).default;
    const searchResult = await searchWithSerpApi({
      apiKey: serpApiKey,
      fetchImpl: fetch,
      baseUrl: config.serpApiBaseUrl,
      input: {
        query: 'Piki POS web search test',
        limit: 1,
      },
    });

    res.json({
      ok: true,
      query: searchResult.query,
      resultCount: searchResult.results.length,
      topResult: searchResult.results[0] || null,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

// Subscription catalog and checkout routes
app.get('/api/subscription/plans', async (req, res, next) => {
  try {
    const requestedCountry = normalizeOptionalText(req.query?.countryCode);
    const requestedProvider = normalizeOptionalText(req.query?.provider);
    const markets = await listPublicMarkets();
    const selectedMarket = selectSubscriptionMarket(markets, {
      countryCode: requestedCountry,
      provider: requestedProvider,
    });
    const countryCode = selectedMarket?.countryCode || requestedCountry || null;
    const plans = selectedMarket
      ? await listPublicPlans({ countryCode })
      : [];
    const gateway = selectedMarket
      ? await loadPaymentGateway(selectedMarket.provider)
      : null;
    res.json({
      ok: true,
      countryCode: countryCode ? normalizeCountryCode(countryCode) : null,
      provider: selectedMarket?.provider || null,
      selectedMarket,
      markets,
      plans,
      googlePayConfig:
        selectedMarket?.provider === 'google_pay' && gateway?.isActive
          ? buildGooglePayConfig(countryCode, null, gateway)
          : null,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/subscription/current', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      allowExpired: true,
    });
    const countryCode =
      normalizeOptionalText(req.query?.countryCode) ||
      businessContext.countryCode ||
      'GLOBAL';
    const overview = await loadSubscriptionOverview(
      businessContext.businessId,
      businessContext.plan,
      countryCode,
      businessContext.sellingMode,
    );
    res.json({ ok: true, data: overview });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/subscription/payments/:paymentId', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      allowExpired: true,
    });
    const payment = await loadSubscriptionPayment(
      businessContext.businessId,
      req.params.paymentId,
    );
    if (!payment) {
      throw createHttpError(404, 'Subscription payment was not found');
    }
    res.json({ ok: true, data: payment });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/subscription/checkout', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      allowExpired: true,
    });
    const planCode = normalizeOptionalText(req.body?.planCode || req.body?.plan);
    const billingPeriod = normalizeOptionalText(req.body?.billingPeriod) || 'monthly';
    const requestedSellingMode = normalizeSellingMode(
      req.body?.sellingMode || req.body?.businessType || req.body?.saleMode,
    );
    const requestedCountry =
      normalizeOptionalText(req.body?.countryCode) ||
      businessContext.countryCode ||
      'GLOBAL';
    const requestedProvider = normalizeOptionalText(req.body?.provider);
    const markets = await listPublicMarkets();
    const market = selectSubscriptionMarket(markets, {
      countryCode: requestedCountry,
      provider: requestedProvider,
    });
    const countryCode = normalizeCountryCode(market?.countryCode || requestedCountry);
    const provider = normalizeProvider(market?.provider || requestedProvider);
    const phoneNumber = normalizeOptionalText(req.body?.phoneNumber);
    if (!planCode) {
      throw createHttpError(400, 'planCode is required');
    }
    if (planCode.toLowerCase() === 'trial') {
      throw createHttpError(
        400,
        'Trial plans are assigned during registration and cannot be renewed through checkout',
      );
    }
    if (!market) {
      throw createHttpError(400, 'No active subscription payment gateway is configured for this market');
    }
    const price = await resolvePlanPrice({
      planCode,
      countryCode,
      provider,
      billingPeriod,
    });
    if (!price) {
      throw createHttpError(404, 'No active price is configured for this plan');
    }
    const planEntitlements = await loadEntitlementsForPlan(planCode);
    const sellingMode = selectSellingModeForPlan(
      planEntitlements,
      requestedSellingMode,
      businessContext.sellingMode,
    );

    const gateway = await loadPaymentGateway(provider);
    const isFreePlan = Number(price.amountMinor || 0) === 0;
    if (!isFreePlan && (!gateway || !gateway.isActive)) {
      throw createHttpError(400, 'This payment gateway is not active');
    }
    if (!isFreePlan && provider === 'mpesa' && !phoneNumber) {
      throw createHttpError(400, 'phoneNumber is required for M-Pesa checkout');
    }

    const checkout = await withTransaction(async (client) => {
      const payment = await createSubscriptionPayment(client, {
        businessId: businessContext.businessId,
        planCode,
        price,
        provider,
        countryCode,
        sellingMode,
        phoneNumber,
        googlePayToken: req.body?.googlePayToken || req.body?.paymentData,
      });

      if (price.amountMinor === 0) {
        await activateSubscriptionFromPayment(client, payment.id);
        return { ...payment, status: 'paid', activated: true };
      }

      return payment;
    });

    if (checkout.activated || isFreePlan) {
      return res.json({
        ok: true,
        data: {
          ...checkout,
          message: 'Subscription activated.',
        },
      });
    }

    if (provider === 'mpesa') {
      const mpesa = await initiateMpesaCheckout(checkout, gateway);
      return res.json({ ok: true, data: { ...checkout, mpesa } });
    }

    res.json({
      ok: true,
      data: {
        ...checkout,
        googlePayConfig: buildGooglePayConfig(countryCode, price, gateway),
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/subscription/google-pay/confirm', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      allowExpired: true,
    });
    const paymentId = normalizeOptionalText(req.body?.paymentId);
    const paymentData = req.body?.paymentData || req.body?.googlePayToken;
    if (!paymentId || !paymentData) {
      throw createHttpError(400, 'paymentId and paymentData are required');
    }

    const result = await processGooglePayConfirmation({
      businessId: businessContext.businessId,
      paymentId,
      paymentData,
    });
    res.json({ ok: true, data: result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/subscription/mpesa/callback', async (req, res, next) => {
  try {
    const callback = req.body?.Body?.stkCallback || req.body?.stkCallback || {};
    const checkoutRequestId = normalizeOptionalText(callback.CheckoutRequestID);
    const resultCode = Number(callback.ResultCode);
    const metadataItems = Array.isArray(callback.CallbackMetadata?.Item)
      ? callback.CallbackMetadata.Item
      : [];
    const metadata = {};
    for (const item of metadataItems) {
      if (item?.Name) {
        metadata[item.Name] = item.Value;
      }
    }

    if (checkoutRequestId) {
      await handleMpesaCallback({
        checkoutRequestId,
        resultCode,
        resultDescription: callback.ResultDesc,
        metadata,
      });
      await handlePosMpesaCallback({
        checkoutRequestId,
        resultCode,
        resultDescription: callback.ResultDesc,
        metadata,
      });
    }

    res.json({ ok: true });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/business/payment-gateways/:provider', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const gateway = await loadBusinessPaymentGateway(
      businessContext.businessId,
      req.params.provider,
      { includeSecrets: false },
    );
    res.json({ ok: true, data: gateway });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/business/payment-gateways/:provider', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const gateway = await saveBusinessPaymentGateway(
      businessContext.businessId,
      req.params.provider,
      req.body || {},
    );
    res.json({ ok: true, data: gateway });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/business/etims-settings', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const settings = await getBusinessEtimsSettings(
      businessContext.businessId,
      { includeSecrets: false },
    );
    const platformConfig = await loadPlatformEtimsConfig({
      includeSecrets: false,
    });
    res.json({
      ok: true,
      data: {
        ...settings,
        platformActive: platformConfig.isActive === true,
        providerName: platformConfig.providerName,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/business/etims-settings', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const settings = await saveBusinessEtimsSettings(
      businessContext.businessId,
      req.body || {},
    );
    const platformConfig = await loadPlatformEtimsConfig({
      includeSecrets: false,
    });
    res.json({
      ok: true,
      data: {
        ...settings,
        platformActive: platformConfig.isActive === true,
        providerName: platformConfig.providerName,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/etims/submit-sale', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const sale =
      req.body && typeof req.body === 'object' ? req.body.sale : null;
    if (!sale || typeof sale !== 'object' || Array.isArray(sale)) {
      throw createHttpError(400, 'sale payload is required');
    }
    const items = Array.isArray(req.body?.items) ? req.body.items : [];
    const submission = await submitEtimsSale({
      businessContext,
      sale,
      items,
      userId: req.body?.userId,
    });
    res.json({ ok: true, data: submission });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/etims/submissions', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const submissions = await listEtimsSubmissions(businessContext.businessId, {
      limit: req.query?.limit,
    });
    res.json({ ok: true, data: submissions });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/payments/mpesa/pos-config', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const data = await loadPosMpesaConfig(businessContext);
    res.json({ ok: true, data });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/payments/mpesa/pos-checkout', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const amountMinor =
      req.body?.amountMinor != null
        ? Number(req.body.amountMinor)
        : Math.round(Number(req.body?.amount || 0) * 100);
    const payment = await createMpesaPosCheckout({
      businessContext,
      amountMinor,
      phoneNumber: req.body?.phoneNumber,
      saleId: req.body?.saleId,
      metadata: req.body?.metadata || {},
    });
    res.json({ ok: true, data: payment });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/payments/:paymentId', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const payment = await loadPosPayment({
      businessId: businessContext.businessId,
      paymentId: req.params.paymentId,
    });
    if (!payment) {
      throw createHttpError(404, 'Payment was not found');
    }
    res.json({ ok: true, data: payment });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/payments/:paymentId/link-sale', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const saleId = normalizeOptionalText(req.body?.saleId);
    if (!saleId) {
      throw createHttpError(400, 'saleId is required');
    }
    const payment = await linkPosPaymentToSale({
      businessId: businessContext.businessId,
      paymentId: req.params.paymentId,
      saleId,
    });
    res.json({ ok: true, data: payment });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/business/communication-settings', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const settings = await getBusinessCommunicationSettings(
      businessContext.businessId,
    );
    res.json({ ok: true, data: settings });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/business/communication-settings', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const settings = await saveBusinessCommunicationSettings(
      businessContext.businessId,
      req.body || {},
    );
    res.json({ ok: true, data: settings });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/messages/send', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const log = await sendBusinessMessage({
      businessContext,
      userId: req.body?.userId,
      channel: req.body?.channel,
      recipient: req.body?.recipient,
      body: req.body?.body || req.body?.message,
      metadata: req.body?.metadata || {},
    });
    res.json({ ok: true, data: log });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/messages/logs', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const logs = await listMessageLogs(businessContext.businessId, {
      limit: req.query?.limit,
    });
    res.json({ ok: true, data: logs });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

const AI_RATE_LIMIT = 30; // legacy fallback, replaced by plan counters below
const AI_RATE_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const OPENROUTER_BASE_URL =
  process.env.OPENROUTER_BASE_URL || 'https://openrouter.ai/api/v1';
const DEFAULT_STT_MODEL = 'openai/whisper-1';
const DEFAULT_TTS_MODEL = 'openai/tts-1';
const DEFAULT_TTS_VOICE = 'alloy';
const DEFAULT_IMAGE_MODEL = 'google/gemini-2.5-flash-image';

async function checkAiRateLimit(businessContext, { consumeQuota = true } = {}) {
  await ensureSubscriptionSchema();
  const entitlements =
    businessContext.entitlements ||
    (await loadEntitlementsForPlan(businessContext.plan));
  const limits = entitlements.aiRateLimits || {};
  const periods = [
    { key: 'hourly', limit: Number(limits.hourly ?? AI_RATE_LIMIT), ms: AI_RATE_WINDOW_MS },
    { key: 'weekly', limit: Number(limits.weekly ?? AI_RATE_LIMIT * 24 * 7), ms: 7 * 24 * 60 * 60 * 1000 },
    { key: 'monthly', limit: Number(limits.monthly ?? AI_RATE_LIMIT * 24 * 30), ms: 30 * 24 * 60 * 60 * 1000 },
  ];

  return withTransaction(async (client) => {
    const now = new Date();
    const checks = [];

    for (const period of periods) {
      if (period.limit <= 0) {
        return {
          allowed: false,
          remaining: 0,
          resetInMinutes: 60,
          period: period.key,
        };
      }

      const result = await client.query(
        `
        SELECT request_count, window_start
        FROM ai_rate_limit_counters
        WHERE business_id = $1 AND period = $2
        FOR UPDATE
        `,
        [businessContext.businessId, period.key],
      );

      if (!result.rows.length) {
        checks.push({ ...period, requestCount: 0, windowStart: now, isNew: true });
        continue;
      }

      const row = result.rows[0];
      const windowStart = new Date(row.window_start);
      const elapsed = now.getTime() - windowStart.getTime();
      if (elapsed >= period.ms) {
        checks.push({ ...period, requestCount: 0, windowStart: now, reset: true });
        continue;
      }

      const requestCount = Number(row.request_count || 0);
      if (requestCount >= period.limit) {
        return {
          allowed: false,
          remaining: 0,
          resetInMinutes: Math.max(1, Math.ceil((period.ms - elapsed) / 60000)),
          period: period.key,
        };
      }

      checks.push({ ...period, requestCount, windowStart });
    }

    if (consumeQuota) {
      for (const check of checks) {
        await client.query(
          `
          INSERT INTO ai_rate_limit_counters (
            business_id,
            period,
            request_count,
            window_start,
            updated_at
          )
          VALUES ($1, $2, 1, $3, $4)
          ON CONFLICT (business_id, period) DO UPDATE
          SET request_count = $5,
              window_start = $3,
              updated_at = $4
          `,
          [
            businessContext.businessId,
            check.key,
            check.windowStart.toISOString(),
            now.toISOString(),
            check.requestCount + 1,
          ],
        );
      }
    }

    const remaining = Math.min(
      ...checks.map((check) => Math.max(0, check.limit - check.requestCount - (consumeQuota ? 1 : 0))),
    );
    return { allowed: true, remaining };
  });
}

async function ensureAiVoiceColumns() {
  await query(
    `ALTER TABLE platform_ai_config
     ADD COLUMN IF NOT EXISTS stt_model text NOT NULL DEFAULT '${DEFAULT_STT_MODEL}'`,
  );
  await query(
    `ALTER TABLE platform_ai_config
     ADD COLUMN IF NOT EXISTS tts_model text NOT NULL DEFAULT '${DEFAULT_TTS_MODEL}'`,
  );
  await query(
    `ALTER TABLE platform_ai_config
     ADD COLUMN IF NOT EXISTS tts_voice text NOT NULL DEFAULT '${DEFAULT_TTS_VOICE}'`,
  );
  await query(
    `ALTER TABLE platform_ai_config
     ADD COLUMN IF NOT EXISTS serp_api_key text NOT NULL DEFAULT ''`,
  );
  await query(
    `ALTER TABLE platform_ai_config
     ADD COLUMN IF NOT EXISTS image_model text NOT NULL DEFAULT '${DEFAULT_IMAGE_MODEL}'`,
  );
}

async function loadPlatformAiConfig() {
  await ensureAiVoiceColumns();
  const result = await query(
    `SELECT api_key, serp_api_key, model, image_model, stt_model, tts_model, tts_voice, enabled
     FROM platform_ai_config
     WHERE id = 1`,
  );
  return (
    result.rows[0] || {
      api_key: '',
      serp_api_key: '',
      model: 'openai/gpt-4o-mini',
      image_model: DEFAULT_IMAGE_MODEL,
      stt_model: DEFAULT_STT_MODEL,
      tts_model: DEFAULT_TTS_MODEL,
      tts_voice: DEFAULT_TTS_VOICE,
      enabled: false,
    }
  );
}

// Business-authenticated AI routes
app.get('/api/ai/config', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const row = await loadPlatformAiConfig();
    const hasAiEntitlement = hasPlanFeature(businessContext, FEATURE_KEYS.agent);
    res.json({
      ok: true,
      aiEnabled: Boolean(row.enabled && row.api_key && hasAiEntitlement),
      webSearchEnabled: Boolean(
        (row.serp_api_key || config.serpApiKey) && hasAiEntitlement,
      ),
      aiModel: row.model,
      imageModel: row.image_model || DEFAULT_IMAGE_MODEL,
      sttModel: row.stt_model || DEFAULT_STT_MODEL,
      ttsModel: row.tts_model || DEFAULT_TTS_MODEL,
      entitlementEnabled: hasAiEntitlement,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

function extractOpenRouterImageUrl(body) {
  const message = body?.choices?.[0]?.message || {};
  const images = Array.isArray(message.images) ? message.images : [];
  for (const image of images) {
    const url =
      image?.image_url?.url ||
      image?.imageUrl?.url ||
      image?.url ||
      image?.image_url;
    if (typeof url === 'string' && url.trim()) {
      return url.trim();
    }
  }

  const content = message.content;
  if (Array.isArray(content)) {
    for (const part of content) {
      const url =
        part?.image_url?.url ||
        part?.imageUrl?.url ||
        part?.url;
      if (typeof url === 'string' && url.trim()) {
        return url.trim();
      }
    }
  }

  if (typeof content === 'string') {
    const dataUrl = content.match(/data:image\/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+/);
    if (dataUrl) {
      return dataUrl[0];
    }
    const httpUrl = content.match(/https?:\/\/\S+/);
    if (httpUrl) {
      return httpUrl[0].replace(/[)\].,]+$/, '');
    }
  }

  return null;
}

async function requestOpenRouterProductImage({ fetchImpl, aiConfig, imageDataUrl, productName, prompt }) {
  const productLabel = normalizeOptionalText(productName) || 'the product';
  const instruction = normalizeOptionalText(prompt) ||
    `Enhance this POS product photo of ${productLabel}. Keep the same real product and packaging, improve lighting, sharpness, color balance, and crop for a clean square catalog thumbnail. Use a simple neutral background. Do not invent a different product, logo, label, or brand text.`;

  const messages = [
    {
      role: 'user',
      content: [
        {
          type: 'text',
          text: instruction,
        },
        {
          type: 'image_url',
          image_url: { url: imageDataUrl },
        },
      ],
    },
  ];

  const attempts = [
    ['image', 'text'],
    ['image'],
  ];
  let lastError = 'OpenRouter image request failed';

  for (const modalities of attempts) {
    const response = await fetchImpl(`${OPENROUTER_BASE_URL}/chat/completions`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${aiConfig.api_key}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://pikipos.com',
        'X-Title': 'Piki POS Product Images',
      },
      body: JSON.stringify({
        model: aiConfig.image_model || DEFAULT_IMAGE_MODEL,
        messages,
        modalities,
        stream: false,
        image_config: {
          aspect_ratio: '1:1',
        },
      }),
    });

    let body = {};
    try {
      body = await response.json();
    } catch (_) {
      body = {};
    }

    if (!response.ok) {
      lastError = body?.error?.message || `OpenRouter image request failed (${response.status})`;
      continue;
    }

    const imageUrl = extractOpenRouterImageUrl(body);
    if (imageUrl) {
      return {
        imageUrl,
        model: aiConfig.image_model || DEFAULT_IMAGE_MODEL,
        content: body?.choices?.[0]?.message?.content || '',
        usage: body?.usage || {},
      };
    }

    lastError = 'OpenRouter did not return an image. Check that the selected image model supports image output.';
  }

  throw createHttpError(502, lastError);
}

app.post('/api/ai/product-image/enhance', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }

    const imageDataUrl = normalizeOptionalText(req.body?.imageDataUrl);
    if (!imageDataUrl || !imageDataUrl.startsWith('data:image/')) {
      throw createHttpError(400, 'A base64 product image is required');
    }

    const consumeQuota = req.body?.consumeQuota !== false;
    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`
      );
    }

    const fetch = (await import('node-fetch')).default;
    const result = await requestOpenRouterProductImage({
      fetchImpl: fetch,
      aiConfig,
      imageDataUrl,
      productName: req.body?.productName,
      prompt: req.body?.prompt,
    });

    res.json({
      ok: true,
      imageDataUrl: result.imageUrl,
      model: result.model,
      usage: {
        promptTokens: result.usage.prompt_tokens || 0,
        completionTokens: result.usage.completion_tokens || 0,
      },
      remaining: rateCheck.remaining,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/chat', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }
    ensureAiFeatureAllowed(businessContext);

    const consumeQuota = req.body?.consumeQuota !== false;

    // Rate limiting
    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
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
        'HTTP-Referer': 'https://pikipos.com',
        'X-Title': 'Piki POS AI',
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

app.post('/api/ai/web-search', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);

    const aiConfig = await loadPlatformAiConfig();
    const serpApiKey = aiConfig.serp_api_key || config.serpApiKey;
    if (!serpApiKey) {
      throw createHttpError(403, 'Web search is not configured by the platform administrator');
    }
    if (!normalizeOptionalText(req.body?.query || req.body?.q)) {
      throw createHttpError(400, 'Search query is required');
    }

    const consumeQuota = req.body?.consumeQuota !== false;

    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const fetch = (await import('node-fetch')).default;
    let result;
    try {
      result = await searchWithSerpApi({
        apiKey: serpApiKey,
        fetchImpl: fetch,
        baseUrl: config.serpApiBaseUrl,
        input: req.body || {},
      });
    } catch (error) {
      throw createHttpError(502, error.message || 'Web search failed');
    }

    res.json({
      ok: true,
      data: result,
      remaining: rateCheck.remaining,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/transcribe', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }
    ensureAiFeatureAllowed(businessContext);

    const consumeQuota = req.body?.consumeQuota !== false;

    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const audioBase64 = normalizeOptionalText(req.body?.audioBase64);
    if (!audioBase64) {
      throw createHttpError(400, 'audioBase64 is required');
    }

    const text = await transcribeAudio(aiConfig, {
      audioBase64,
      mimeType: normalizeOptionalText(req.body?.mimeType) || 'audio/mp4',
      filename: normalizeOptionalText(req.body?.filename) || 'piki.m4a',
    });

    res.json({
      ok: true,
      text,
      model: aiConfig.stt_model || DEFAULT_STT_MODEL,
      remaining: rateCheck.remaining,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/tts', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }
    ensureAiFeatureAllowed(businessContext);

    const consumeQuota = req.body?.consumeQuota !== false;

    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const text = normalizeOptionalText(req.body?.text);
    if (!text) {
      throw createHttpError(400, 'text is required');
    }

    const audio = await synthesizeSpeech(aiConfig, {
      text: text.slice(0, 2000),
      voice: normalizeOptionalText(req.body?.voice),
    });

    res.json({
      ok: true,
      audioBase64: audio.audioBase64,
      mimeType: audio.mimeType,
      model: aiConfig.tts_model || DEFAULT_TTS_MODEL,
      remaining: rateCheck.remaining,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/proactive-insights', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.proactivePiki);
    const branchId = normalizeOptionalText(req.query?.branchId);
    await ensurePikiProactiveSchema(query);

    let result = await query(
      `
      SELECT *
      FROM piki_proactive_insights
      WHERE business_id = $1
        AND status = 'active'
        AND generated_at >= NOW() - INTERVAL '30 minutes'
        AND (
          $2::text IS NULL
          OR COALESCE(branch_id, 'main_branch') = COALESCE($2, 'main_branch')
        )
      ORDER BY
        CASE severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
        generated_at DESC
      LIMIT 20
      `,
      [businessContext.businessId, branchId],
    );

    if (result.rows.length === 0) {
      await withTransaction((client) =>
        refreshBusinessInsights(client, businessContext.businessId, {
          branchId,
        }),
      );
      result = await query(
        `
        SELECT *
        FROM piki_proactive_insights
        WHERE business_id = $1
          AND status = 'active'
          AND (
            $2::text IS NULL
            OR COALESCE(branch_id, 'main_branch') = COALESCE($2, 'main_branch')
          )
        ORDER BY
          CASE severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
          generated_at DESC
        LIMIT 20
        `,
        [businessContext.businessId, branchId],
      );
    }

    res.json({ ok: true, insights: result.rows.map(normalizeInsightRow) });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/proactive-run', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.proactivePiki);
    const branchId = normalizeOptionalText(req.body?.branchId);
    await withTransaction((client) =>
      refreshBusinessInsights(client, businessContext.businessId, {
        branchId,
      }),
    );
    const result = await query(
      `
      SELECT *
      FROM piki_proactive_insights
      WHERE business_id = $1
        AND status = 'active'
        AND (
          $2::text IS NULL
          OR COALESCE(branch_id, 'main_branch') = COALESCE($2, 'main_branch')
        )
      ORDER BY
        CASE severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
        generated_at DESC
      LIMIT 20
      `,
      [businessContext.businessId, branchId],
    );
    res.json({ ok: true, insights: result.rows.map(normalizeInsightRow) });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/learning', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const kind = normalizeOptionalText(req.body?.kind) || 'alias';
    const phrase = normalizeOptionalText(req.body?.phrase ?? req.body?.alias);
    const target = normalizeOptionalText(req.body?.target);
    const branchId = normalizeOptionalText(req.body?.branchId);
    const metadata =
      req.body?.metadata && typeof req.body.metadata === 'object'
        ? req.body.metadata
        : {};

    if (!phrase) {
      throw createHttpError(400, 'Learning phrase is required');
    }
    if (!target) {
      throw createHttpError(400, 'Learning target is required');
    }

    await ensurePikiProactiveSchema(query);
    const now = new Date().toISOString();
    const updateResult = await query(
      `
      UPDATE piki_learning
      SET target = $5,
          weight = weight + 1,
          metadata_json = $6::jsonb,
          updated_at = $7
      WHERE business_id = $1
        AND kind = $2
        AND COALESCE(branch_id, '') = COALESCE($3, '')
        AND LOWER(phrase) = LOWER($4)
        AND deleted_at IS NULL
      RETURNING *
      `,
      [
        businessContext.businessId,
        kind,
        branchId,
        phrase,
        target,
        JSON.stringify(metadata),
        now,
      ],
    );

    let row = updateResult.rows[0];
    if (!row) {
      const insertResult = await query(
        `
        INSERT INTO piki_learning (
          id, business_id, branch_id, kind, phrase, target,
          metadata_json, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $8)
        RETURNING *
        `,
        [
          crypto.randomUUID(),
          businessContext.businessId,
          branchId,
          kind,
          phrase,
          target,
          JSON.stringify(metadata),
          now,
        ],
      );
      row = insertResult.rows[0];
    }

    res.json({ ok: true, learning: normalizeLearningRow(row) });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/learning', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const kind = normalizeOptionalText(req.query?.kind);
    const branchId = normalizeOptionalText(req.query?.branchId);
    await ensurePikiProactiveSchema(query);

    const params = [businessContext.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    if (kind) {
      params.push(kind);
      where.push(`kind = $${params.length}`);
    }
    if (branchId) {
      params.push(branchId);
      where.push(
        `COALESCE(branch_id, 'main_branch') = COALESCE($${params.length}, 'main_branch')`,
      );
    }

    const result = await query(
      `
      SELECT *
      FROM piki_learning
      WHERE ${where.join(' AND ')}
      ORDER BY updated_at DESC
      LIMIT 100
      `,
      params,
    );
    res.json({ ok: true, learning: result.rows.map(normalizeLearningRow) });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/public/catalog/:businessId', async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.params.businessId);
    if (!businessId) {
      throw createHttpError(400, 'Business catalog link is invalid');
    }

    const catalog = await loadPublicCatalog(businessId, {
      currencyOverride: req.query?.currency,
    });
    res.json({ ok: true, data: catalog });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/catalog/orders', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const status = normalizeCatalogOrderStatus(req.query?.status, {
      allowAll: true,
      fallback: 'pending',
    });
    const orders = await listPublicCatalogOrders(businessContext.businessId, {
      status,
    });
    res.json({ ok: true, data: orders });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/catalog/orders/:orderId/status', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const orderId = normalizeOptionalText(req.params.orderId);
    const status = normalizeCatalogOrderStatus(req.body?.status);
    if (!orderId) {
      throw createHttpError(400, 'Order id is required');
    }
    const order = await updatePublicCatalogOrderStatus({
      businessId: businessContext.businessId,
      orderId,
      status,
    });
    res.json({ ok: true, data: order });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/catalog/orders/:orderId/payment-request', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const orderId = normalizeOptionalText(req.params.orderId);
    if (!orderId) {
      throw createHttpError(400, 'Order id is required');
    }
    const result = await requestPublicCatalogOrderPayment({
      businessContext,
      orderId,
      channel: req.body?.channel,
      recipient: req.body?.recipient,
      body: req.body?.body || req.body?.message,
      userId: req.body?.userId,
      sendViaApi: req.body?.sendViaApi === true || req.body?.send_via_api === true,
    });
    res.json({ ok: true, data: result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/public/catalog/:businessId/orders', async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.params.businessId);
    if (!businessId) {
      throw createHttpError(400, 'Business catalog link is invalid');
    }

    const order = await createPublicCatalogOrder(businessId, req.body || {});
    res.status(201).json({ ok: true, data: order });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/public/catalog/:businessId/orders/:orderNumber', async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.params.businessId);
    const orderNumber = normalizeOptionalText(req.params.orderNumber);
    const phone = normalizeOptionalText(req.query?.phone);
    if (!businessId || !orderNumber) {
      throw createHttpError(400, 'Order tracking link is invalid');
    }
    if (!phone) {
      throw createHttpError(400, 'Phone number is required to track an order');
    }

    const order = await loadPublicCatalogOrderForCustomer({
      businessId,
      orderNumber,
      phone,
    });
    res.json({ ok: true, data: order });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/catalog/:businessId', async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.params.businessId);
    if (!businessId) {
      throw createHttpError(400, 'Business catalog link is invalid');
    }

    const catalog = await loadPublicCatalog(businessId, {
      currencyOverride: req.query?.currency,
    });
    res
      .status(200)
      .type('html')
      .send(renderPublicCatalogPage(catalog));
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
    `Piki POS sync backend listening on port ${config.port} (${config.nodeEnv})`,
  );
});

Promise.all([ensureSubscriptionSchema(), ensureEtimsSchema()])
  .then(() =>
    startPikiProactiveWorker({
      query,
      withTransaction,
      intervalMs: Number(process.env.PIKI_PROACTIVE_INTERVAL_MS || 15 * 60 * 1000),
      initialDelayMs: Number(process.env.PIKI_PROACTIVE_INITIAL_DELAY_MS || 10 * 1000),
    }),
  )
  .catch((error) => {
    console.error('Could not initialize backend schema:', error.message);
  });

async function requireBusinessContext(req, { allowExpired = false } = {}) {
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
  if (!businessContext.usable && !allowExpired) {
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

async function saveSubscriptionPlan(rawInput) {
  return withTransaction(async (client) => {
    await ensureSubscriptionSchema(client);
    const plan = normalizePlanInput(rawInput);
    if (!plan.code) {
      throw createHttpError(400, 'Plan code is required');
    }
    await client.query(
      `
      INSERT INTO subscription_plans (
        code,
        name,
        description,
        is_active,
        features_json,
        allowed_selling_modes_json,
        max_branches,
        max_employees,
        max_ai_agents,
        ai_rate_hourly,
        ai_rate_weekly,
        ai_rate_monthly,
        sort_order,
        created_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())
      ON CONFLICT (code) DO UPDATE
      SET name = EXCLUDED.name,
          description = EXCLUDED.description,
          is_active = EXCLUDED.is_active,
          features_json = EXCLUDED.features_json,
          allowed_selling_modes_json = EXCLUDED.allowed_selling_modes_json,
          max_branches = EXCLUDED.max_branches,
          max_employees = EXCLUDED.max_employees,
          max_ai_agents = EXCLUDED.max_ai_agents,
          ai_rate_hourly = EXCLUDED.ai_rate_hourly,
          ai_rate_weekly = EXCLUDED.ai_rate_weekly,
          ai_rate_monthly = EXCLUDED.ai_rate_monthly,
          sort_order = EXCLUDED.sort_order,
          updated_at = NOW()
      `,
      [
        plan.code,
        plan.name,
        plan.description,
        plan.isActive,
        JSON.stringify(plan.features),
        JSON.stringify(plan.sellingModes),
        plan.maxBranches,
        plan.maxEmployees,
        plan.maxAiAgents,
        plan.aiRateHourly,
        plan.aiRateWeekly,
        plan.aiRateMonthly,
        plan.sortOrder,
      ],
    );

    if (Array.isArray(rawInput?.prices)) {
      await client.query('DELETE FROM subscription_plan_prices WHERE plan_code = $1', [
        plan.code,
      ]);
      for (const rawPrice of rawInput.prices) {
        const price = normalizePriceInput(rawPrice, plan.code);
        await client.query(
          `
          INSERT INTO subscription_plan_prices (
            id,
            plan_code,
            country_code,
            currency,
            amount_minor,
            billing_period,
            provider,
            is_active,
            created_at,
            updated_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
          `,
          [
            price.id,
            plan.code,
            price.countryCode,
            price.currency,
            price.amountMinor,
            price.billingPeriod,
            price.provider,
            price.isActive,
          ],
        );
      }
    }

    const plans = await listPlans({ includeInactive: true }, client);
    return plans.find((item) => item.code === plan.code);
  });
}

async function loadSubscriptionOverview(businessId, planCode, countryCode, sellingMode) {
  await ensureSubscriptionSchema();
  const subscriptionResult = await query(
    'SELECT * FROM subscriptions WHERE business_id = $1 LIMIT 1',
    [businessId],
  );
  const subscription = subscriptionResult.rows[0] || {
    plan: planCode || 'trial',
    status: 'active',
  };
  const entitlements = applySellingModeToEntitlements(
    await loadEntitlementsForPlan(subscription.plan),
    sellingMode,
  );
  const usage = await getBusinessUsage(businessId);
  const markets = await listPublicMarkets();
  const selectedMarket = selectSubscriptionMarket(markets, { countryCode });
  const effectiveCountryCode = selectedMarket?.countryCode || countryCode;
  const plans = selectedMarket
    ? await listPublicPlans({ countryCode: effectiveCountryCode })
    : [];
  const gateway = selectedMarket
    ? await loadPaymentGateway(selectedMarket.provider)
    : null;
  return {
    subscription: {
      plan: String(subscription.plan || 'trial'),
      status: String(subscription.status || 'active'),
      expiresAt: toIsoString(subscription.expires_at),
      graceUntil: toIsoString(subscription.grace_until),
      lastVerifiedAt: toIsoString(subscription.last_verified_at),
      entitlements,
    },
    usage,
    markets,
    selectedMarket,
    plans,
    googlePayConfig:
      selectedMarket?.provider === 'google_pay' && gateway?.isActive
        ? buildGooglePayConfig(effectiveCountryCode, null, gateway)
        : null,
  };
}

async function getBusinessUsage(businessId, target = query) {
  const branchResult = await runDbQuery(
    target,
    `
    SELECT COUNT(*)::int AS count
    FROM branches
    WHERE business_id = $1
      AND deleted_at IS NULL
      AND COALESCE(is_active, 1) <> 0
    `,
    [businessId],
  );
  const userResult = await runDbQuery(
    target,
    `
    SELECT id, role, feature_access_json
    FROM users
    WHERE business_id = $1
      AND deleted_at IS NULL
    `,
    [businessId],
  );
  const users = userResult.rows || [];
  return {
    branches: Number(branchResult.rows[0]?.count || 0),
    employees: users.length,
    aiAgents: users.filter(isAiEnabledUserRecord).length,
  };
}

async function createSubscriptionPayment(
  client,
  {
    businessId,
    planCode,
    price,
    provider,
    countryCode,
    sellingMode,
    phoneNumber,
    googlePayToken,
  },
) {
  await ensureSubscriptionSchema(client);
  const paymentId = crypto.randomUUID();
  const now = new Date().toISOString();
  const externalReference = `sub_${paymentId.slice(0, 12)}`;
  const result = await client.query(
    `
    INSERT INTO subscription_payments (
      id,
      business_id,
      plan_code,
      price_id,
      provider,
      country_code,
      currency,
      amount_minor,
      billing_period,
      selling_mode,
      status,
      phone_number,
      external_reference,
      google_pay_token_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'pending', $11, $12, $13::jsonb, $14, $14)
    RETURNING *
    `,
    [
      paymentId,
      businessId,
      planCode,
      price.id,
      provider,
      countryCode,
      price.currency,
      price.amountMinor,
      price.billingPeriod,
      normalizeSellingMode(sellingMode) || 'products',
      phoneNumber,
      externalReference,
      googlePayToken ? JSON.stringify(googlePayToken) : null,
      now,
    ],
  );
  return normalizePaymentRow(result.rows[0]);
}

async function loadSubscriptionPayment(businessId, paymentId, target = query) {
  const cleanBusinessId = normalizeOptionalText(businessId);
  const cleanPaymentId = normalizeOptionalText(paymentId);
  if (!cleanBusinessId || !cleanPaymentId) {
    return null;
  }
  const result = await runDbQuery(
    target,
    `
    SELECT *
    FROM subscription_payments
    WHERE id = $1 AND business_id = $2
    LIMIT 1
    `,
    [cleanPaymentId, cleanBusinessId],
  );
  return result.rows[0] ? normalizePaymentRow(result.rows[0]) : null;
}

async function activateSubscriptionFromPayment(client, paymentId) {
  const paymentResult = await client.query(
    'SELECT * FROM subscription_payments WHERE id = $1 FOR UPDATE',
    [paymentId],
  );
  const payment = paymentResult.rows[0];
  if (!payment) {
    throw createHttpError(404, 'Subscription payment was not found');
  }
  if (payment.status === 'paid' && payment.completed_at) {
    return false;
  }

  const now = new Date();
  const subscriptionResult = await client.query(
    'SELECT expires_at FROM subscriptions WHERE business_id = $1 FOR UPDATE',
    [payment.business_id],
  );
  const renewalStartsAt = renewalBaseDate(
    subscriptionResult.rows[0]?.expires_at,
    now,
  );
  const planEntitlements = await loadEntitlementsForPlan(payment.plan_code, client);
  const sellingMode = selectSellingModeForPlan(
    planEntitlements,
    normalizeSellingMode(payment.selling_mode),
  );
  const expiresAt = addDays(
    renewalStartsAt,
    billingPeriodDays(payment.billing_period),
  );
  const subscriptionSettings = await loadPlatformSubscriptionSettings(client);
  const graceUntil = addDays(expiresAt, subscriptionSettings.graceDays);
  await client.query(
    `
    UPDATE businesses
    SET selling_mode = $2,
        updated_at = $3
    WHERE id = $1
    `,
    [payment.business_id, sellingMode, now.toISOString()],
  );
  await client.query(
    `
    INSERT INTO subscriptions (
      business_id,
      plan,
      status,
      expires_at,
      grace_until,
      last_verified_at,
      created_at,
      updated_at
    )
    VALUES ($1, $2, 'active', $3, $4, $5, $5, $5)
    ON CONFLICT (business_id) DO UPDATE
    SET plan = EXCLUDED.plan,
        status = EXCLUDED.status,
        expires_at = EXCLUDED.expires_at,
        grace_until = EXCLUDED.grace_until,
        last_verified_at = EXCLUDED.last_verified_at,
        updated_at = EXCLUDED.updated_at
    `,
    [
      payment.business_id,
      payment.plan_code,
      expiresAt.toISOString(),
      graceUntil.toISOString(),
      now.toISOString(),
    ],
  );
  await client.query(
    `
    UPDATE subscription_payments
    SET status = 'paid',
        completed_at = $2,
        updated_at = $2
    WHERE id = $1
    `,
    [paymentId, now.toISOString()],
  );
  return true;
}

async function initiateMpesaCheckout(payment, gateway) {
  if (!payment.phoneNumber) {
    throw createHttpError(400, 'phoneNumber is required for M-Pesa checkout');
  }
  const mpesaConfig = resolveMpesaGatewayConfig(gateway);
  if (
    !mpesaConfig.consumerKey ||
    !mpesaConfig.consumerSecret ||
    !mpesaConfig.shortcode ||
    !mpesaConfig.passkey ||
    !isHttpsUrl(mpesaConfig.baseUrl) ||
    !isHttpsUrl(mpesaConfig.callbackUrl)
  ) {
    await query(
      `
      UPDATE subscription_payments
      SET status = 'pending_configuration',
          updated_at = NOW()
      WHERE id = $1
      `,
      [payment.id],
    );
    return {
      status: 'configuration_required',
      message: 'M-Pesa credentials are not configured in the admin panel.',
    };
  }

  const token = await getMpesaAccessToken(mpesaConfig);
  const timestamp = formatMpesaTimestamp(new Date());
  const password = Buffer.from(
    `${mpesaConfig.shortcode}${mpesaConfig.passkey}${timestamp}`,
  ).toString('base64');
  const phoneNumber = normalizeMpesaPhone(payment.phoneNumber);
  const amount = Math.max(1, Math.ceil(payment.amountMinor / 100));
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(
    `${mpesaConfig.baseUrl.replace(/\/$/, '')}/mpesa/stkpush/v1/processrequest`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        BusinessShortCode: mpesaConfig.shortcode,
        Password: password,
        Timestamp: timestamp,
        TransactionType: 'CustomerPayBillOnline',
        Amount: amount,
        PartyA: phoneNumber,
        PartyB: mpesaConfig.shortcode,
        PhoneNumber: phoneNumber,
        CallBackURL: mpesaConfig.callbackUrl,
        AccountReference: payment.externalReference,
        TransactionDesc: `Piki ${payment.planCode} subscription`,
      }),
    },
  );
  const body = await readMaybeJson(response);
  if (!response.ok || body.ResponseCode !== '0') {
    await query(
      `
      UPDATE subscription_payments
      SET status = 'failed',
          metadata_json = $2::jsonb,
          updated_at = NOW()
      WHERE id = $1
      `,
      [payment.id, JSON.stringify(body)],
    );
    throw createHttpError(
      response.ok ? 502 : response.status,
      body.errorMessage || body.ResponseDescription || 'M-Pesa checkout failed',
    );
  }

  await query(
    `
    UPDATE subscription_payments
    SET checkout_request_id = $2,
        metadata_json = $3::jsonb,
        updated_at = NOW()
    WHERE id = $1
    `,
    [
      payment.id,
      body.CheckoutRequestID || null,
      JSON.stringify(body),
    ],
  );

  return {
    status: 'stk_sent',
    merchantRequestId: body.MerchantRequestID || null,
    checkoutRequestId: body.CheckoutRequestID || null,
    responseDescription: body.ResponseDescription || '',
  };
}

async function getMpesaAccessToken(mpesaConfig) {
  const fetch = (await import('node-fetch')).default;
  const credentials = Buffer.from(
    `${mpesaConfig.consumerKey}:${mpesaConfig.consumerSecret}`,
  ).toString('base64');
  const response = await fetch(
    `${mpesaConfig.baseUrl.replace(/\/$/, '')}/oauth/v1/generate?grant_type=client_credentials`,
    {
      headers: {
        Authorization: `Basic ${credentials}`,
      },
    },
  );
  const body = await readMaybeJson(response);
  if (!response.ok || !body.access_token) {
    throw createHttpError(response.ok ? 502 : response.status, 'M-Pesa auth failed');
  }
  return body.access_token;
}

async function processGooglePayConfirmation({ businessId, paymentId, paymentData }) {
  return withTransaction(async (client) => {
    const result = await client.query(
      `
      SELECT *
      FROM subscription_payments
      WHERE id = $1 AND business_id = $2
      FOR UPDATE
      `,
      [paymentId, businessId],
    );
    const payment = result.rows[0];
    if (!payment) {
      throw createHttpError(404, 'Subscription payment was not found');
    }
    if (payment.provider !== 'google_pay') {
      throw createHttpError(400, 'Payment is not a Google Pay checkout');
    }
    if (payment.status === 'paid' && payment.completed_at) {
      return {
        status: 'paid',
        activated: true,
      };
    }
    const gateway = await loadPaymentGateway(payment.provider, client);
    if (!gateway || !gateway.isActive) {
      throw createHttpError(400, 'Google Pay is not active in the admin panel');
    }
    const googleConfig = resolveGoogleGatewayConfig(gateway);

    await client.query(
      `
      UPDATE subscription_payments
      SET google_pay_token_json = $2::jsonb,
          updated_at = NOW()
      WHERE id = $1
      `,
      [paymentId, JSON.stringify(paymentData)],
    );

    if (!googleConfig.gatewayChargeUrl) {
      await client.query(
        `
        UPDATE subscription_payments
        SET status = 'pending_gateway',
            updated_at = NOW()
        WHERE id = $1
        `,
        [paymentId],
      );
      return {
        status: 'pending_gateway',
        message:
          'Google Pay token received. Configure the gateway capture URL in the admin panel to capture automatically.',
      };
    }

    const charged = await chargeGooglePayGateway(payment, paymentData, gateway);
    if (!charged.ok) {
      await client.query(
        `
        UPDATE subscription_payments
        SET status = 'failed',
            metadata_json = $2::jsonb,
            updated_at = NOW()
        WHERE id = $1
        `,
        [paymentId, JSON.stringify(charged.body || {})],
      );
      throw createHttpError(charged.status || 502, charged.message || 'Google Pay charge failed');
    }

    await activateSubscriptionFromPayment(client, paymentId);
    return {
      status: 'paid',
      activated: true,
      gateway: charged.body || {},
    };
  });
}

async function chargeGooglePayGateway(payment, paymentData, gateway) {
  const googleConfig = resolveGoogleGatewayConfig(gateway);
  const fetch = (await import('node-fetch')).default;
  const headers = { 'Content-Type': 'application/json' };
  if (googleConfig.gatewayApiKey) {
    headers.Authorization = `Bearer ${googleConfig.gatewayApiKey}`;
  }
  const response = await fetch(googleConfig.gatewayChargeUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      paymentId: payment.id,
      externalReference: payment.external_reference,
      amountMinor: Number(payment.amount_minor || 0),
      currency: payment.currency,
      sellingMode: payment.selling_mode,
      paymentData,
    }),
  });
  const body = await readMaybeJson(response);
  return {
    ok: response.ok && body.success !== false,
    status: response.status,
    message: body.error || body.message,
    body,
  };
}

async function handleMpesaCallback({
  checkoutRequestId,
  resultCode,
  resultDescription,
  metadata,
}) {
  await withTransaction(async (client) => {
    const paymentResult = await client.query(
      `
      SELECT id, status, completed_at
      FROM subscription_payments
      WHERE checkout_request_id = $1
      FOR UPDATE
      `,
      [checkoutRequestId],
    );
    const payment = paymentResult.rows[0];
    if (!payment) {
      return;
    }
    const callbackMetadata = JSON.stringify({
      resultCode,
      resultDescription,
      metadata,
    });
    if (resultCode === 0) {
      await client.query(
        `
        UPDATE subscription_payments
        SET metadata_json = metadata_json || $2::jsonb,
            updated_at = NOW()
        WHERE id = $1
        `,
        [payment.id, callbackMetadata],
      );
      if (payment.status !== 'paid' || !payment.completed_at) {
        await activateSubscriptionFromPayment(client, payment.id);
      }
      return;
    }
    await client.query(
      `
      UPDATE subscription_payments
      SET status = 'failed',
          metadata_json = metadata_json || $2::jsonb,
          updated_at = NOW()
      WHERE id = $1
      `,
      [payment.id, callbackMetadata],
    );
  });
}

async function validatePlanWrite(client, tableName, record, businessContext) {
  const feature = featureRequiredForTable(tableName);
  if (feature && !record.deleted_at && !hasPlanFeature(businessContext, feature)) {
    return {
      ok: false,
      error: {
        code: 'feature_not_in_plan',
        message: `The current subscription plan does not include ${feature}.`,
      },
    };
  }

  if (tableName === 'branches') {
    return validateBranchLimit(client, record, businessContext);
  }
  if (tableName === 'users') {
    return validateUserLimits(client, record, businessContext);
  }
  return { ok: true };
}

async function validateBranchLimit(client, record, businessContext) {
  if (record.deleted_at || Number(record.is_active ?? 1) === 0) {
    return { ok: true };
  }
  const existing = await client.query(
    'SELECT id FROM branches WHERE business_id = $1 AND id = $2 LIMIT 1',
    [businessContext.businessId, record.id],
  );
  if (existing.rows.length) {
    return { ok: true };
  }
  const usage = await getBusinessUsage(businessContext.businessId, client);
  const maxBranches = Number(businessContext.entitlements?.maxBranches || 0);
  if (maxBranches > 0 && usage.branches >= maxBranches) {
    return {
      ok: false,
      error: {
        code: 'branch_limit_reached',
        message: `This plan allows ${maxBranches} active branch(es).`,
      },
    };
  }
  return { ok: true };
}

async function validateUserLimits(client, record, businessContext) {
  if (record.deleted_at) {
    return { ok: true };
  }
  const existing = await client.query(
    'SELECT id, role, feature_access_json FROM users WHERE business_id = $1 AND id = $2 LIMIT 1',
    [businessContext.businessId, record.id],
  );
  const isNew = existing.rows.length === 0;
  const usage = await getBusinessUsage(businessContext.businessId, client);
  const maxEmployees = Number(businessContext.entitlements?.maxEmployees || 0);
  if (isNew && maxEmployees > 0 && usage.employees >= maxEmployees) {
    return {
      ok: false,
      error: {
        code: 'employee_limit_reached',
        message: `This plan allows ${maxEmployees} employee account(s).`,
      },
    };
  }

  const nextAiEnabled = isAiEnabledUserRecord(record);
  if (nextAiEnabled) {
    const previousAiEnabled = existing.rows[0]
      ? isAiEnabledUserRecord(existing.rows[0])
      : false;
    const maxAiAgents = Number(businessContext.entitlements?.maxAiAgents || 0);
    if (!previousAiEnabled && maxAiAgents > 0 && usage.aiAgents >= maxAiAgents) {
      return {
        ok: false,
        error: {
          code: 'ai_agent_limit_reached',
          message: `This plan allows ${maxAiAgents} Piki AI-enabled employee(s).`,
        },
      };
    }
  }

  return { ok: true };
}

function hasPlanFeature(businessContext, feature) {
  const features = businessContext?.entitlements?.features;
  return Array.isArray(features) && features.includes(feature);
}

function ensurePlanFeatureAllowed(businessContext, feature) {
  if (!hasPlanFeature(businessContext, feature)) {
    throw createHttpError(403, `This subscription plan does not include ${feature}.`);
  }
}

function ensureAiFeatureAllowed(businessContext) {
  ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.agent);
}

function featureRequiredForTable(tableName) {
  switch (tableName) {
    case 'branches':
      return FEATURE_KEYS.branches;
    case 'stock_transfers':
      return FEATURE_KEYS.transfers;
    case 'categories':
      return FEATURE_KEYS.categories;
    case 'purchase_invoices':
    case 'suppliers':
    case 'stock_batches':
      return FEATURE_KEYS.purchases;
    case 'services':
    case 'service_orders':
    case 'service_fields':
      return FEATURE_KEYS.services;
    case 'products':
    case 'product_variants':
      return FEATURE_KEYS.products;
    case 'sales':
    case 'sale_items':
      return FEATURE_KEYS.sales;
    case 'shifts':
      return FEATURE_KEYS.shifts;
    default:
      return null;
  }
}

function isAiEnabledUserRecord(record) {
  if (!record || record.deleted_at) {
    return false;
  }
  const role = String(record.role || '').trim().toUpperCase();
  if (role === 'ADMIN') {
    return true;
  }
  const raw = record.feature_access_json;
  if (!raw) {
    return false;
  }
  try {
    const features = Array.isArray(raw) ? raw : JSON.parse(String(raw));
    return Array.isArray(features) && features.includes(FEATURE_KEYS.agent);
  } catch (_) {
    return false;
  }
}

function selectSubscriptionMarket(markets, { countryCode, provider } = {}) {
  const cleanCountry = normalizeOptionalText(countryCode)
    ? normalizeCountryCode(countryCode)
    : null;
  const cleanProvider = normalizeOptionalText(provider)
    ? normalizeProvider(provider)
    : null;
  const matchesProvider = (market) =>
    !cleanProvider || market.provider === cleanProvider;

  if (cleanCountry) {
    const exact = markets.find(
      (market) =>
        market.countryCode === cleanCountry &&
        matchesProvider(market),
    );
    if (exact) return exact;

    const global = markets.find(
      (market) =>
        market.countryCode === 'GLOBAL' &&
        matchesProvider(market),
    );
    if (global) return global;
  }

  if (cleanProvider) {
    const byProvider = markets.find(matchesProvider);
    if (byProvider) return byProvider;
  }

  return markets[0] || null;
}

async function resolveRegistrationPlanSelection({
  requestedPlanCode,
  countryCode,
  provider,
}) {
  if (requestedPlanCode) {
    const price = await resolvePlanPrice({
      planCode: requestedPlanCode,
      countryCode,
      provider,
    });
    return price ? { planCode: requestedPlanCode, price } : null;
  }

  const trialPrice = await resolvePlanPrice({
    planCode: 'trial',
    countryCode,
    provider,
  });
  if (trialPrice && Number(trialPrice.amountMinor || 0) === 0) {
    return { planCode: 'trial', price: trialPrice };
  }

  const syntheticTrialPrice = {
    id: null,
    planCode: 'trial',
    countryCode: normalizeCountryCode(countryCode),
    currency: normalizeCountryCode(countryCode) === 'KE' ? 'KES' : 'USD',
    amountMinor: 0,
    billingPeriod: 'monthly',
    provider: normalizeProvider(provider),
  };

  const cleanCountry = normalizeCountryCode(countryCode);
  const cleanProvider = normalizeProvider(provider);
  const plans = await listPublicPlans({ countryCode: cleanCountry });
  for (const plan of plans) {
    const freePrice =
      (plan.prices || []).find((price) => {
        return (
          price.provider === cleanProvider &&
          Number(price.amountMinor || 0) === 0 &&
          (price.countryCode === cleanCountry || price.countryCode === 'GLOBAL')
        );
      }) ||
      (plan.price &&
      plan.price.provider === cleanProvider &&
      Number(plan.price.amountMinor || 0) === 0
        ? plan.price
        : null);
    if (freePrice) {
      return { planCode: plan.code, price: freePrice };
    }
  }

  return { planCode: 'trial', price: syntheticTrialPrice };
}

function selectSellingModeForPlan(entitlements, requestedMode, fallbackMode = null) {
  const requested = normalizeSellingMode(requestedMode);
  if (requested) {
    const validation = validateSellingModeEntitlement(entitlements, requested);
    if (!validation.ok) {
      throw createHttpError(400, validation.message);
    }
    return validation.mode;
  }

  const fallback = normalizeSellingMode(fallbackMode);
  if (fallback) {
    const validation = validateSellingModeEntitlement(entitlements, fallback);
    if (validation.ok) {
      return validation.mode;
    }
  }

  for (const mode of ['products', 'services', 'combo']) {
    const validation = validateSellingModeEntitlement(entitlements, mode);
    if (validation.ok) {
      return validation.mode;
    }
  }

  throw createHttpError(
    400,
    'This plan is not available for product or service selling yet.',
  );
}

function resolveMpesaGatewayConfig(gateway) {
  const publicConfig = gateway?.publicConfig || {};
  const secretConfig = gateway?.secretConfig || {};
  return {
    baseUrl: publicConfig.baseUrl || config.mpesaBaseUrl,
    shortcode: publicConfig.shortcode || config.mpesaShortcode,
    callbackUrl: publicConfig.callbackUrl || config.mpesaCallbackUrl,
    consumerKey: secretConfig.consumerKey || config.mpesaConsumerKey,
    consumerSecret: secretConfig.consumerSecret || config.mpesaConsumerSecret,
    passkey: secretConfig.passkey || config.mpesaPasskey,
  };
}

function resolveGoogleGatewayConfig(gateway) {
  const publicConfig = gateway?.publicConfig || {};
  const secretConfig = gateway?.secretConfig || {};
  return {
    environment: publicConfig.environment || config.googlePayEnvironment,
    merchantId: publicConfig.merchantId || config.googlePayMerchantId,
    merchantName: publicConfig.merchantName || 'Piki POS',
    gateway: publicConfig.gateway || config.googlePayGateway,
    gatewayMerchantId:
      publicConfig.gatewayMerchantId || config.googlePayGatewayMerchantId,
    gatewayChargeUrl:
      secretConfig.gatewayChargeUrl || config.googlePayGatewayChargeUrl,
    gatewayApiKey: secretConfig.gatewayApiKey || config.googlePayGatewayApiKey,
  };
}

function buildGooglePayConfig(countryCode, price = null, gateway = null) {
  const googleConfig = resolveGoogleGatewayConfig(gateway);
  const cleanCountry = normalizeCountryCode(countryCode);
  const transactionCountry = cleanCountry === 'GLOBAL' ? 'US' : cleanCountry;
  const currency = price?.currency || (cleanCountry === 'KE' ? 'KES' : 'USD');
  return {
    environment: googleConfig.environment,
    merchantId: googleConfig.merchantId,
    merchantName: googleConfig.merchantName,
    gateway: googleConfig.gateway,
    gatewayMerchantId: googleConfig.gatewayMerchantId,
    paymentConfiguration: {
      provider: 'google_pay',
      data: {
        environment: googleConfig.environment,
        apiVersion: 2,
        apiVersionMinor: 0,
        allowedPaymentMethods: [
          {
            type: 'CARD',
            parameters: {
              allowedAuthMethods: ['PAN_ONLY', 'CRYPTOGRAM_3DS'],
              allowedCardNetworks: ['AMEX', 'DISCOVER', 'MASTERCARD', 'VISA'],
            },
            tokenizationSpecification: {
              type: 'PAYMENT_GATEWAY',
              parameters: {
                gateway: googleConfig.gateway,
                gatewayMerchantId: googleConfig.gatewayMerchantId,
              },
            },
          },
        ],
        merchantInfo: {
          merchantId: googleConfig.merchantId,
          merchantName: googleConfig.merchantName,
        },
        transactionInfo: {
          totalPriceStatus: 'FINAL',
          totalPrice: price ? (Number(price.amountMinor || 0) / 100).toFixed(2) : '0.00',
          currencyCode: currency,
          countryCode: transactionCountry,
        },
      },
    },
  };
}

function normalizePaymentRow(row) {
  return {
    id: row.id,
    businessId: row.business_id,
    planCode: row.plan_code,
    priceId: row.price_id,
    provider: row.provider,
    countryCode: row.country_code,
    currency: row.currency,
    amountMinor: Number(row.amount_minor || 0),
    billingPeriod: row.billing_period || 'monthly',
    sellingMode: row.selling_mode || 'products',
    status: row.status,
    phoneNumber: row.phone_number,
    externalReference: row.external_reference,
    checkoutRequestId: row.checkout_request_id,
    createdAt: toIsoString(row.created_at),
  };
}

async function loadPublicCatalog(businessId, { currencyOverride } = {}) {
  const businessResult = await query(
    `
    SELECT b.id, b.name, b.country_code, b.currency, b.updated_at,
           cs.whatsapp_number
    FROM businesses b
    LEFT JOIN business_communication_settings cs
      ON cs.business_id = b.id
    WHERE b.id = $1
    LIMIT 1
    `,
    [businessId],
  );
  const business = businessResult.rows[0];
  if (!business) {
    throw createHttpError(404, 'Catalog not found');
  }

  const productsResult = await query(
    `
    SELECT
      p.id,
      p.name,
      p.price,
      p.stock,
      p.unit,
      p.sale_unit,
      p.stock_unit,
      p.image_url,
      p.brand,
      p.track_stock,
      p.has_variants,
      p.updated_at,
      c.name AS category_name,
      COALESCE(
        json_agg(
          json_build_object(
            'id', pv.id,
            'name', pv.name,
            'price', pv.price,
            'stock', pv.stock
          )
          ORDER BY pv.sort_order ASC, pv.name ASC
        ) FILTER (WHERE pv.id IS NOT NULL),
        '[]'::json
      ) AS variants
    FROM products p
    LEFT JOIN categories c
      ON c.id = p.category_id
     AND c.business_id = p.business_id
     AND c.deleted_at IS NULL
    LEFT JOIN product_variants pv
      ON pv.product_id = p.id
     AND pv.business_id = p.business_id
     AND pv.deleted_at IS NULL
    WHERE p.business_id = $1
      AND p.deleted_at IS NULL
    GROUP BY
      p.id,
      p.name,
      p.price,
      p.stock,
      p.unit,
      p.sale_unit,
      p.stock_unit,
      p.image_url,
      p.brand,
      p.track_stock,
      p.has_variants,
      p.updated_at,
      c.name
    ORDER BY c.name ASC NULLS LAST, p.name ASC
    LIMIT 500
    `,
    [businessId],
  );

  const products = productsResult.rows.map((row) =>
    normalizePublicCatalogProduct(row),
  );
  const categories = [
    ...new Set(
      products
        .map((product) => product.category)
        .filter((category) => category && category.trim()),
    ),
  ].sort((a, b) => a.localeCompare(b));

  const currencyInfo = publicCatalogCurrencyInfo(
    currencyOverride || business.currency,
    business.country_code,
  );

  return {
    business: {
      id: business.id,
      name: business.name,
      countryCode: business.country_code || 'GLOBAL',
      whatsappNumber: normalizeOptionalText(business.whatsapp_number),
    },
    currency: currencyInfo.code,
    currencyCode: currencyInfo.code,
    currencySymbol: currencyInfo.symbol,
    currencyLabel: currencyInfo.label,
    categories,
    products,
    updatedAt: products.reduce((latest, product) => {
      if (!product.updatedAt) return latest;
      if (!latest || product.updatedAt > latest) return product.updatedAt;
      return latest;
    }, toIsoString(business.updated_at)),
  };
}

async function createPublicCatalogOrder(businessId, payload) {
  await ensurePublicCatalogOrderSchema(query);

  const customerName = normalizeOptionalText(payload.customerName || payload.customer_name);
  const phone = normalizeOptionalText(payload.phone || payload.phoneNumber || payload.phone_number);
  const deliveryAddress = normalizeOptionalText(payload.deliveryAddress || payload.delivery_address);
  const fulfillmentMethod = normalizeFulfillmentMethod(
    payload.fulfillmentMethod ||
      payload.fulfillment_method ||
      payload.deliveryMethod ||
      payload.delivery_method,
  );
  const note = normalizeOptionalText(payload.note);
  const rawItems = Array.isArray(payload.items) ? payload.items : [];

  if (!customerName) {
    throw createHttpError(400, 'Customer name is required');
  }
  if (!phone) {
    throw createHttpError(400, 'Phone number is required');
  }
  if (rawItems.length === 0) {
    throw createHttpError(400, 'Add at least one item to the order');
  }
  if (rawItems.length > 100) {
    throw createHttpError(400, 'Order has too many items');
  }

  const businessResult = await query(
    'SELECT id, name FROM businesses WHERE id = $1 LIMIT 1',
    [businessId],
  );
  const business = businessResult.rows[0];
  if (!business) {
    throw createHttpError(404, 'Catalog not found');
  }

  const preparedItems = [];
  for (const rawItem of rawItems) {
    const productId = normalizeOptionalText(rawItem?.productId || rawItem?.product_id);
    const variantId = normalizeOptionalText(rawItem?.variantId || rawItem?.variant_id);
    const quantity = Number(rawItem?.quantity);
    if (!productId || !Number.isFinite(quantity) || quantity <= 0) {
      throw createHttpError(400, 'Each order item needs a product and quantity');
    }
    if (quantity > 9999) {
      throw createHttpError(400, 'Order quantity is too high');
    }

    const item = await resolvePublicCatalogOrderItem({
      businessId,
      productId,
      variantId,
      quantity,
    });
    preparedItems.push(item);
  }

  const subtotal = preparedItems.reduce((sum, item) => sum + item.lineTotal, 0);
  const orderId = crypto.randomUUID();
  const now = new Date().toISOString();
  const itemCount = preparedItems.reduce((sum, item) => sum + item.quantity, 0);

  await withTransaction(async (client) => {
    await ensurePublicCatalogOrderSchema(client);
    await client.query(
      `
      INSERT INTO public_catalog_orders (
        id,
        business_id,
        customer_name,
        phone,
        fulfillment_method,
        delivery_address,
        note,
        status,
        subtotal,
        item_count,
        source,
        created_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending', $8, $9, 'catalog_link', $10, $11)
      `,
      [
        orderId,
        businessId,
        customerName,
        phone,
        fulfillmentMethod,
        deliveryAddress,
        note,
        subtotal,
        itemCount,
        now,
        now,
      ],
    );

    for (const item of preparedItems) {
      await client.query(
        `
        INSERT INTO public_catalog_order_items (
          id,
          order_id,
          business_id,
          product_id,
          variant_id,
          product_name,
          variant_name,
          quantity,
          unit_price,
          line_total,
          created_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        `,
        [
          crypto.randomUUID(),
          orderId,
          businessId,
          item.productId,
          item.variantId,
          item.productName,
          item.variantName,
          item.quantity,
          item.unitPrice,
          item.lineTotal,
          now,
        ],
      );
    }
  });

  return {
    id: orderId,
    orderNumber: shortOrderNumber(orderId),
    businessName: business.name,
    customerName,
    phone,
    fulfillmentMethod,
    deliveryAddress,
    note,
    status: 'pending',
    subtotal,
    itemCount,
    items: preparedItems.map((item) => ({
      productId: item.productId,
      variantId: item.variantId,
      productName: item.productName,
      variantName: item.variantName,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      lineTotal: item.lineTotal,
    })),
    createdAt: now,
  };
}

async function listPublicCatalogOrders(businessId, { status = 'pending' } = {}) {
  await ensurePublicCatalogOrderSchema(query);

  const params = [businessId];
  const where = ['business_id = $1'];
  if (status && status !== 'all') {
    params.push(status);
    where.push(`status = $${params.length}`);
  }

  const ordersResult = await query(
    `
    SELECT *
    FROM public_catalog_orders
    WHERE ${where.join(' AND ')}
    ORDER BY created_at DESC
    LIMIT 200
    `,
    params,
  );
  return attachPublicCatalogOrderItems(ordersResult.rows);
}

async function loadPublicCatalogOrderForCustomer({
  businessId,
  orderNumber,
  phone,
}) {
  await ensurePublicCatalogOrderSchema(query);
  const cleanOrderNumber = normalizeOptionalText(orderNumber)
    ?.replace(/[^a-zA-Z0-9-]/g, '')
    .replace(/^#/, '')
    .toLowerCase();
  const cleanPhone = normalizePhoneForMatch(phone);
  if (!cleanOrderNumber || cleanOrderNumber.length < 4 || !cleanPhone) {
    throw createHttpError(400, 'Order number and phone are required');
  }
  const phoneCandidates = phoneMatchCandidates(phone);

  const result = await query(
    `
    SELECT *
    FROM public_catalog_orders
    WHERE business_id = $1
      AND LOWER(SUBSTRING(id FROM 1 FOR 8)) = $2
      AND regexp_replace(COALESCE(phone, ''), '[^0-9]', '', 'g') = ANY($3::text[])
    LIMIT 1
    `,
    [businessId, cleanOrderNumber.slice(0, 8), phoneCandidates],
  );
  if (result.rows.length === 0) {
    throw createHttpError(404, 'Order not found. Check the order number and phone.');
  }
  const orders = await attachPublicCatalogOrderItems(result.rows);
  return orders[0];
}

async function updatePublicCatalogOrderStatus({ businessId, orderId, status }) {
  await ensurePublicCatalogOrderSchema(query);
  const result = await query(
    `
    UPDATE public_catalog_orders
    SET status = $3,
        payment_requested_at = CASE
          WHEN $3 = 'payment_requested' THEN NOW()
          ELSE payment_requested_at
        END,
        fulfilled_at = CASE
          WHEN $3 = 'fulfilled' THEN NOW()
          ELSE fulfilled_at
        END,
        updated_at = NOW()
    WHERE business_id = $1
      AND id = $2
    RETURNING *
    `,
    [businessId, orderId, status],
  );
  if (result.rows.length === 0) {
    throw createHttpError(404, 'Catalog order not found');
  }
  const orders = await attachPublicCatalogOrderItems(result.rows);
  return orders[0];
}

async function requestPublicCatalogOrderPayment({
  businessContext,
  orderId,
  channel,
  recipient,
  body,
  userId,
  sendViaApi,
}) {
  const order = await updatePublicCatalogOrderStatus({
    businessId: businessContext.businessId,
    orderId,
    status: 'payment_requested',
  });
  const cleanRecipient = normalizeOptionalText(recipient) || order.phone;
  const cleanBody = normalizeOptionalText(body) || buildCatalogPaymentMessage(order);
  let messageLog = null;
  let messageError = null;

  if (sendViaApi) {
    try {
      messageLog = await sendBusinessMessage({
        businessContext,
        userId,
        channel: normalizeOptionalText(channel) || 'whatsapp',
        recipient: cleanRecipient,
        body: cleanBody,
        metadata: {
          source: 'catalog_payment_request',
          orderId: order.id,
          orderNumber: order.orderNumber,
        },
      });
    } catch (error) {
      messageError = error.message || 'Payment request message could not be sent.';
    }
  }

  return {
    order,
    message: cleanBody,
    recipient: cleanRecipient,
    messageLog,
    messageError,
  };
}

function buildCatalogPaymentMessage(order) {
  return [
    `Hello ${order.customerName || 'Customer'}, your order #${order.orderNumber} has been accepted.`,
    `Amount: ${Number(order.subtotal || 0).toFixed(2)}`,
    'Please complete payment so the shop can prepare your order.',
  ].join('\n');
}

async function attachPublicCatalogOrderItems(orderRows) {
  if (!orderRows.length) {
    return [];
  }

  const orderIds = orderRows.map((row) => row.id);
  const itemsResult = await query(
    `
    SELECT *
    FROM public_catalog_order_items
    WHERE order_id = ANY($1::text[])
    ORDER BY created_at ASC, id ASC
    `,
    [orderIds],
  );
  const itemsByOrder = new Map();
  for (const item of itemsResult.rows) {
    const list = itemsByOrder.get(item.order_id) || [];
    list.push(normalizePublicCatalogOrderItem(item));
    itemsByOrder.set(item.order_id, list);
  }

  return orderRows.map((row) => normalizePublicCatalogOrder(row, itemsByOrder.get(row.id) || []));
}

function normalizePublicCatalogOrder(row, items) {
  return {
    id: row.id,
    orderNumber: shortOrderNumber(row.id),
    customerName: row.customer_name,
    phone: row.phone,
    fulfillmentMethod: row.fulfillment_method || 'delivery',
    deliveryAddress: row.delivery_address || '',
    note: row.note || '',
    status: row.status,
    subtotal: Number(row.subtotal || 0),
    itemCount: Number(row.item_count || 0),
    source: row.source || 'catalog_link',
    paymentRequestedAt: toIsoString(row.payment_requested_at),
    fulfilledAt: toIsoString(row.fulfilled_at),
    createdAt: toIsoString(row.created_at),
    updatedAt: toIsoString(row.updated_at),
    items,
  };
}

function normalizePublicCatalogOrderItem(row) {
  return {
    id: row.id,
    productId: row.product_id,
    variantId: row.variant_id,
    productName: row.product_name,
    variantName: row.variant_name || '',
    quantity: Number(row.quantity || 0),
    unitPrice: Number(row.unit_price || 0),
    lineTotal: Number(row.line_total || 0),
    createdAt: toIsoString(row.created_at),
  };
}

function normalizeCatalogOrderStatus(value, { allowAll = false, fallback = null } = {}) {
  const status = normalizeOptionalText(value);
  if (!status && fallback) {
    return fallback;
  }
  const clean = String(status || '').toLowerCase();
  const allowed = [
    'pending',
    'accepted',
    'payment_requested',
    'fulfilled',
    'rejected',
    'cancelled',
  ];
  if (allowAll && clean === 'all') {
    return 'all';
  }
  if (clean === 'completed') {
    return 'fulfilled';
  }
  if (allowed.includes(clean)) {
    return clean;
  }
  throw createHttpError(400, 'Invalid catalog order status');
}

function normalizeFulfillmentMethod(value) {
  const clean = normalizeOptionalText(value)
    ?.toLowerCase()
    .replace(/[^a-z0-9_]+/g, '_');
  if (clean === 'pickup' || clean === 'collection') {
    return 'pickup';
  }
  return 'delivery';
}

async function resolvePublicCatalogOrderItem({
  businessId,
  productId,
  variantId,
  quantity,
}) {
  const result = await query(
    `
    SELECT
      p.id AS product_id,
      p.name AS product_name,
      p.price AS product_price,
      p.track_stock,
      p.stock AS product_stock,
      pv.id AS variant_id,
      pv.name AS variant_name,
      pv.price AS variant_price,
      pv.stock AS variant_stock
    FROM products p
    LEFT JOIN product_variants pv
      ON pv.product_id = p.id
     AND pv.business_id = p.business_id
     AND pv.deleted_at IS NULL
     AND ($3::text IS NOT NULL AND pv.id = $3)
    WHERE p.business_id = $1
      AND p.id = $2
      AND p.deleted_at IS NULL
    LIMIT 1
    `,
    [businessId, productId, variantId],
  );
  const row = result.rows[0];
  if (!row) {
    throw createHttpError(400, 'One of the selected products is no longer available');
  }
  if (variantId && !row.variant_id) {
    throw createHttpError(400, 'One of the selected product options is no longer available');
  }

  const trackStock = Number(row.track_stock ?? 1) !== 0;
  const stock = variantId
    ? Number(row.variant_stock || 0)
    : Number(row.product_stock || 0);
  if (trackStock && stock <= 0) {
    throw createHttpError(400, `${row.product_name} is not available right now`);
  }
  if (trackStock && quantity > stock) {
    throw createHttpError(
      400,
      `Only ${stock} ${row.product_name} available right now`,
    );
  }

  const unitPrice = Number(variantId ? row.variant_price : row.product_price) || 0;
  const cleanQuantity = Math.round(quantity * 1000) / 1000;
  return {
    productId: row.product_id,
    variantId: row.variant_id || null,
    productName: String(row.product_name || '').trim(),
    variantName: row.variant_name ? String(row.variant_name).trim() : null,
    quantity: cleanQuantity,
    unitPrice,
    lineTotal: Math.round(cleanQuantity * unitPrice * 100) / 100,
  };
}

async function ensurePublicCatalogOrderSchema(target = query) {
  await runDbQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS public_catalog_orders (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      customer_name text NOT NULL,
      phone text NOT NULL,
      fulfillment_method text NOT NULL DEFAULT 'delivery',
      delivery_address text,
      note text,
      status text NOT NULL DEFAULT 'pending',
      subtotal double precision NOT NULL DEFAULT 0,
      item_count double precision NOT NULL DEFAULT 0,
      source text NOT NULL DEFAULT 'catalog_link',
      payment_requested_at timestamptz,
      fulfilled_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );
  await runDbQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS public_catalog_order_items (
      id text PRIMARY KEY,
      order_id text NOT NULL REFERENCES public_catalog_orders(id) ON DELETE CASCADE,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      product_id text NOT NULL,
      variant_id text,
      product_name text NOT NULL,
      variant_name text,
      quantity double precision NOT NULL DEFAULT 1,
      unit_price double precision NOT NULL DEFAULT 0,
      line_total double precision NOT NULL DEFAULT 0,
      created_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );
  await runDbQuery(
    target,
    `ALTER TABLE public_catalog_orders
     ADD COLUMN IF NOT EXISTS fulfillment_method text NOT NULL DEFAULT 'delivery'`,
  );
  await runDbQuery(
    target,
    `ALTER TABLE public_catalog_orders
     ADD COLUMN IF NOT EXISTS payment_requested_at timestamptz`,
  );
  await runDbQuery(
    target,
    `ALTER TABLE public_catalog_orders
     ADD COLUMN IF NOT EXISTS fulfilled_at timestamptz`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_public_catalog_orders_business_status
     ON public_catalog_orders(business_id, status, created_at DESC)`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_public_catalog_order_items_order
     ON public_catalog_order_items(order_id)`,
  );
}

function shortOrderNumber(orderId) {
  const clean = String(orderId || '').replace(/-/g, '').toUpperCase();
  return clean ? clean.slice(0, 8) : 'ORDER';
}

function normalizePublicCatalogProduct(row) {
  const trackStock = Number(row.track_stock ?? 1) !== 0;
  const variants = Array.isArray(row.variants)
    ? row.variants
        .filter((variant) => variant && variant.id)
        .map((variant) => ({
          id: variant.id,
          name: String(variant.name || '').trim(),
          price: Number(variant.price || 0),
          available: !trackStock || Number(variant.stock || 0) > 0,
        }))
    : [];
  const hasVariants = Number(row.has_variants || 0) === 1 && variants.length > 0;
  const stock = Number(row.stock || 0);
  const available = hasVariants
    ? variants.some((variant) => variant.available)
    : !trackStock || stock > 0;

  return {
    id: row.id,
    name: String(row.name || '').trim(),
    price: Number(row.price || 0),
    brand: normalizeOptionalText(row.brand),
    category: normalizeOptionalText(row.category_name),
    unit: normalizeOptionalText(row.sale_unit) || normalizeOptionalText(row.unit) || 'pcs',
    imageUrl: safePublicImageUrl(row.image_url),
    hasVariants,
    variants,
    availability: available ? 'Available' : 'Ask for availability',
    updatedAt: toIsoString(row.updated_at),
  };
}

function renderPublicCatalogPage(catalog) {
  const businessName = catalog.business.name || 'Catalog';
  const productCount = catalog.products.length;
  const safeCatalogJson = JSON.stringify(catalog).replace(/</g, '\\u003c');
  const whatsappNumber = normalizePublicPhone(catalog.business.whatsappNumber || '');
  const updated = catalog.updatedAt
    ? new Date(catalog.updatedAt).toLocaleDateString('en', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      })
    : '';

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(businessName)} Catalog</title>
  <meta name="description" content="Browse ${escapeHtml(businessName)} products and prices." />
  <meta property="og:title" content="${escapeHtml(businessName)} Catalog" />
  <meta property="og:description" content="${productCount} product${productCount === 1 ? '' : 's'} available." />
  <style>
    :root {
      color-scheme: light;
      --bg: #f7f7fb;
      --surface: #ffffff;
      --ink: #17151f;
      --muted: #666173;
      --line: #e5e2ec;
      --primary: #ec2257;
      --primary-dark: #ba1641;
      --success: #087f5b;
      --danger: #c92a2a;
      --shadow: 0 16px 40px rgba(23, 21, 31, 0.09);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding-bottom: 92px;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
    }
    header {
      background: var(--surface);
      border-bottom: 1px solid var(--line);
    }
    .wrap {
      width: min(1120px, calc(100% - 32px));
      margin: 0 auto;
    }
    .hero {
      min-height: 220px;
      display: grid;
      align-items: end;
      padding: 44px 0 28px;
      gap: 18px;
    }
    .store {
      display: grid;
      gap: 8px;
    }
    h1 {
      margin: 0;
      font-size: clamp(32px, 5vw, 58px);
      line-height: 1;
      letter-spacing: 0;
    }
    .meta {
      margin: 0;
      color: var(--muted);
      font-size: 15px;
    }
    .toolbar {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 12px;
      align-items: center;
      padding: 18px 0;
    }
    input,
    select {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px 14px;
      font: inherit;
      background: var(--surface);
      color: var(--ink);
    }
    select { min-width: 190px; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 16px;
      padding: 22px 0 48px;
    }
    .card {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      overflow: hidden;
      box-shadow: var(--shadow);
      display: flex;
      flex-direction: column;
      min-height: 100%;
      cursor: pointer;
      transition: border-color 160ms ease, transform 160ms ease;
    }
    .card:hover {
      border-color: rgba(236, 34, 87, 0.42);
      transform: translateY(-1px);
    }
    .photo {
      aspect-ratio: 4 / 3;
      background: linear-gradient(135deg, #fff0f4, #f4f1ff);
      display: grid;
      place-items: center;
      color: var(--muted);
      font-size: 13px;
      overflow: hidden;
    }
    .photo img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }
    .body {
      padding: 14px;
      display: grid;
      gap: 10px;
      flex: 1;
    }
    .name {
      margin: 0;
      font-size: 17px;
      line-height: 1.25;
      overflow-wrap: anywhere;
    }
    .brand,
    .category,
    .variants {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.35;
    }
    .price-row {
      display: flex;
      gap: 10px;
      justify-content: space-between;
      align-items: center;
      margin-top: auto;
    }
    .price {
      font-weight: 800;
      font-size: 18px;
    }
    .badge {
      border-radius: 999px;
      padding: 6px 9px;
      background: rgba(8, 127, 91, 0.1);
      color: var(--success);
      font-size: 12px;
      font-weight: 700;
      white-space: nowrap;
    }
    .order-actions {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 8px;
      align-items: center;
    }
    .variant-select {
      min-width: 0;
      padding: 9px 10px;
      font-size: 13px;
    }
    .add-button,
    .cart-toggle,
    .submit-order,
    .whatsapp-order {
      border: 0;
      cursor: pointer;
      font: inherit;
      font-weight: 800;
      border-radius: 8px;
    }
    .add-button {
      background: var(--ink);
      color: white;
      padding: 10px 12px;
      white-space: nowrap;
    }
    .add-button:disabled,
    .submit-order:disabled {
      cursor: not-allowed;
      opacity: 0.55;
    }
    .empty {
      padding: 56px 0;
      color: var(--muted);
      text-align: center;
      display: none;
    }
    .cart-toggle {
      position: fixed;
      right: 18px;
      bottom: 18px;
      z-index: 5;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 48px;
      padding: 0 18px;
      border-radius: 999px;
      background: var(--primary);
      color: white;
      text-decoration: none;
      font-weight: 800;
      box-shadow: 0 12px 28px rgba(236, 34, 87, 0.3);
    }
    .cart-panel {
      position: fixed;
      right: 18px;
      bottom: 82px;
      z-index: 6;
      width: min(420px, calc(100vw - 32px));
      max-height: min(680px, calc(100vh - 118px));
      overflow: auto;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
      display: none;
    }
    .cart-panel.open {
      display: block;
    }
    .cart-head,
    .cart-foot {
      padding: 14px;
      border-bottom: 1px solid var(--line);
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
    }
    .cart-foot {
      border-top: 1px solid var(--line);
      border-bottom: 0;
      font-weight: 800;
    }
    .cart-head h2 {
      margin: 0;
      font-size: 18px;
    }
    .icon-button {
      border: 0;
      background: transparent;
      cursor: pointer;
      font: inherit;
      color: var(--muted);
      padding: 6px;
    }
    .cart-lines,
    .order-form {
      padding: 14px;
      display: grid;
      gap: 12px;
    }
    .cart-line {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 84px 28px;
      gap: 8px;
      align-items: center;
    }
    .cart-line strong,
    .cart-line span {
      overflow-wrap: anywhere;
    }
    .cart-line small {
      color: var(--muted);
    }
    .qty-input {
      padding: 8px 9px;
    }
    .remove-button {
      border: 0;
      background: transparent;
      color: var(--danger);
      cursor: pointer;
      font-size: 20px;
      line-height: 1;
    }
    .order-form label {
      display: grid;
      gap: 6px;
      font-size: 13px;
      font-weight: 700;
    }
    .choice-row {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
    }
    .choice-row label {
      display: flex;
      align-items: center;
      gap: 8px;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 10px 12px;
      font-weight: 800;
    }
    .order-form textarea {
      width: 100%;
      min-height: 74px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px 14px;
      font: inherit;
      color: var(--ink);
    }
    .submit-order {
      width: 100%;
      min-height: 46px;
      background: var(--primary);
      color: white;
    }
    .whatsapp-order {
      display: none;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      background: #25d366;
      color: #092113;
      text-decoration: none;
    }
    .notice {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.4;
    }
    .tracking-panel {
      margin: 0 0 48px;
      padding: 18px;
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      box-shadow: var(--shadow);
    }
    .tracking-panel h2 {
      margin: 0 0 8px;
      font-size: 20px;
    }
    .tracking-form {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) auto;
      gap: 10px;
      align-items: end;
      margin-top: 14px;
    }
    .tracking-form label {
      display: grid;
      gap: 6px;
      color: var(--muted);
      font-size: 13px;
      font-weight: 700;
    }
    .track-order {
      min-height: 46px;
      border: 0;
      cursor: pointer;
      font: inherit;
      font-weight: 800;
      border-radius: 8px;
      background: var(--ink);
      color: white;
      padding: 0 16px;
    }
    .tracking-result {
      display: none;
      margin-top: 14px;
      padding: 12px;
      border-radius: 8px;
      background: rgba(236, 34, 87, 0.08);
      border: 1px solid rgba(236, 34, 87, 0.18);
      line-height: 1.45;
    }
    .success {
      display: none;
      margin: 0 14px 14px;
      padding: 12px;
      border-radius: 8px;
      background: rgba(8, 127, 91, 0.1);
      color: var(--success);
      font-weight: 700;
      line-height: 1.4;
    }
    .error {
      display: none;
      margin: 0 14px 14px;
      padding: 12px;
      border-radius: 8px;
      background: rgba(201, 42, 42, 0.1);
      color: var(--danger);
      font-weight: 700;
      line-height: 1.4;
    }
    footer {
      border-top: 1px solid var(--line);
      padding: 20px 0 72px;
      color: var(--muted);
      font-size: 13px;
      background: var(--surface);
    }
    @media (max-width: 720px) {
      .toolbar {
        grid-template-columns: 1fr;
      }
      .hero {
        min-height: 190px;
        padding-top: 32px;
      }
      .grid {
        grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
        gap: 12px;
      }
      .body { padding: 12px; }
      .cart-panel {
        right: 16px;
        left: 16px;
        width: auto;
      }
      .tracking-form {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <header>
    <div class="wrap hero">
      <div class="store">
        <h1>${escapeHtml(businessName)}</h1>
        <p class="meta">${productCount} product${productCount === 1 ? '' : 's'}${updated ? ` - Updated ${escapeHtml(updated)}` : ''}</p>
      </div>
      <div class="toolbar">
        <input id="search" type="search" placeholder="Search products" autocomplete="off" />
        <select id="category">
          <option value="">All categories</option>
          ${catalog.categories
            .map((category) => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`)
            .join('')}
        </select>
      </div>
    </div>
  </header>
  <main class="wrap">
    <section id="grid" class="grid"></section>
    <p id="empty" class="empty">No products match your search.</p>
    <section class="tracking-panel" aria-label="Track order">
      <h2>Track your order</h2>
      <p class="notice">Enter the order number and phone number you used at checkout.</p>
      <form id="tracking-form" class="tracking-form">
        <label>
          Order number
          <input id="tracking-order-number" maxlength="12" placeholder="e.g. A1B2C3D4" />
        </label>
        <label>
          Phone number
          <input id="tracking-phone" maxlength="40" autocomplete="tel" />
        </label>
        <button id="track-order" class="track-order" type="submit">Track</button>
      </form>
      <div id="tracking-result" class="tracking-result"></div>
    </section>
  </main>
  <aside id="cart-panel" class="cart-panel" aria-label="Order cart">
    <div class="cart-head">
      <h2>Your order</h2>
      <button id="close-cart" class="icon-button" type="button" aria-label="Close cart">Close</button>
    </div>
    <div id="cart-lines" class="cart-lines"></div>
    <div class="cart-foot">
      <span>Total</span>
      <span id="cart-total">0.00</span>
    </div>
    <form id="order-form" class="order-form">
      <label>
        Name
        <input id="customer-name" name="customerName" required maxlength="120" autocomplete="name" />
      </label>
      <label>
        Phone number
        <input id="customer-phone" name="phone" required maxlength="40" autocomplete="tel" />
      </label>
      <div class="choice-row" role="radiogroup" aria-label="Delivery method">
        <label><input type="radio" name="fulfillmentMethod" value="delivery" checked /> Delivery</label>
        <label><input type="radio" name="fulfillmentMethod" value="pickup" /> Pickup</label>
      </div>
      <label>
        Delivery address or pickup note
        <input id="delivery-address" name="deliveryAddress" maxlength="240" autocomplete="street-address" />
      </label>
      <label>
        Extra note
        <textarea id="order-note" name="note" maxlength="500"></textarea>
      </label>
      <p class="notice">Submit your order and the shop will confirm availability and payment.</p>
      <button id="submit-order" class="submit-order" type="submit">Submit Order</button>
      <a id="whatsapp-order" class="whatsapp-order" target="_blank" rel="noopener">Send order on WhatsApp</a>
    </form>
    <p id="order-success" class="success"></p>
    <p id="order-error" class="error"></p>
  </aside>
  <button id="cart-toggle" class="cart-toggle" type="button">Order (0)</button>
  <footer>
    <div class="wrap">Powered by Piki POS</div>
  </footer>
  <script id="catalog-data" type="application/json">${safeCatalogJson}</script>
  <script>
    const catalog = JSON.parse(document.getElementById('catalog-data').textContent);
    const shopWhatsApp = '${escapeHtml(whatsappNumber)}';
    const cart = new Map();
    const grid = document.getElementById('grid');
    const empty = document.getElementById('empty');
    const search = document.getElementById('search');
    const category = document.getElementById('category');
    const cartPanel = document.getElementById('cart-panel');
    const cartToggle = document.getElementById('cart-toggle');
    const closeCart = document.getElementById('close-cart');
    const cartLines = document.getElementById('cart-lines');
    const cartTotal = document.getElementById('cart-total');
    const orderForm = document.getElementById('order-form');
    const submitOrder = document.getElementById('submit-order');
    const successBox = document.getElementById('order-success');
    const errorBox = document.getElementById('order-error');
    const whatsappOrder = document.getElementById('whatsapp-order');
    const trackingForm = document.getElementById('tracking-form');
    const trackingOrderNumber = document.getElementById('tracking-order-number');
    const trackingPhone = document.getElementById('tracking-phone');
    const trackingResult = document.getElementById('tracking-result');
    const currencyCode = catalog.currencyCode || catalog.currency || 'KES';
    const currencySymbol = String(catalog.currencySymbol || '').trim();
    let formatter = null;
    try {
      formatter = new Intl.NumberFormat('en', {
        style: 'currency',
        currency: currencyCode,
        minimumFractionDigits: 2,
      });
    } catch (_) {
      formatter = null;
    }

    function formatMoney(value) {
      const amount = Number(value || 0);
      if (currencySymbol) {
        return currencySymbol + amount.toLocaleString('en', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        });
      }
      if (formatter) {
        return formatter.format(amount);
      }
      return String(catalog.currencyLabel || currencyCode) + ' ' + amount.toFixed(2);
    }

    function escapeText(value) {
      return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;',
      })[char]);
    }

    function productById(id) {
      return catalog.products.find((product) => product.id === id);
    }

    function variantById(product, id) {
      return (product.variants || []).find((variant) => variant.id === id) || null;
    }

    function cartKey(productId, variantId) {
      return productId + ':' + (variantId || '');
    }

    function optionLabel(product, variant) {
      return variant ? product.name + ' - ' + variant.name : product.name;
    }

    function optionPrice(product, variant) {
      return Number((variant ? variant.price : product.price) || 0);
    }

    function cartTotalValue() {
      let total = 0;
      for (const item of cart.values()) {
        total += item.quantity * optionPrice(item.product, item.variant);
      }
      return Math.round(total * 100) / 100;
    }

    function renderCart() {
      const items = Array.from(cart.values());
      const count = items.reduce((sum, item) => sum + item.quantity, 0);
      cartToggle.textContent = 'Order (' + count + ')';
      cartTotal.textContent = formatMoney(cartTotalValue());
      submitOrder.disabled = items.length === 0;

      if (!items.length) {
        cartLines.innerHTML = '<p class="notice">Your order is empty. Add products from the catalog.</p>';
        return;
      }

      cartLines.innerHTML = items.map((item) => {
        const key = cartKey(item.product.id, item.variant ? item.variant.id : '');
        const price = optionPrice(item.product, item.variant);
        return '<div class="cart-line">' +
          '<span><strong>' + escapeText(optionLabel(item.product, item.variant)) + '</strong><br><small>' + formatMoney(price) + ' each</small></span>' +
          '<input class="qty-input" data-cart-key="' + escapeText(key) + '" type="number" min="1" step="1" value="' + item.quantity + '" aria-label="Quantity" />' +
          '<button class="remove-button" data-remove-key="' + escapeText(key) + '" type="button" aria-label="Remove item">x</button>' +
        '</div>';
      }).join('');
    }

    function addToCart(productId, variantId) {
      const product = productById(productId);
      if (!product) return;
      const variant = variantId ? variantById(product, variantId) : null;
      if (variantId && !variant) return;
      const key = cartKey(product.id, variant ? variant.id : '');
      const existing = cart.get(key);
      cart.set(key, {
        product,
        variant,
        quantity: existing ? existing.quantity + 1 : 1,
      });
      successBox.style.display = 'none';
      errorBox.style.display = 'none';
      whatsappOrder.style.display = 'none';
      cartPanel.classList.add('open');
      renderCart();
    }

    function productMatches(product, q, cat) {
      const haystack = [product.name, product.brand, product.category]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return (!q || haystack.includes(q)) && (!cat || product.category === cat);
    }

    function render() {
      const q = search.value.trim().toLowerCase();
      const cat = category.value;
      const products = catalog.products.filter((product) => productMatches(product, q, cat));
      grid.innerHTML = products.map((product) => {
        const variants = product.variants && product.variants.length
          ? '<div class="variants">' + product.variants.map((variant) => {
              const name = escapeText(variant.name);
              const variantPrice = Number(variant.price || 0);
              return variantPrice && variantPrice !== Number(product.price || 0)
                ? name + ' - ' + formatMoney(variantPrice)
                : name;
            }).join(', ') + '</div>'
          : '';
        const variantSelect = product.variants && product.variants.length
          ? '<select class="variant-select" data-variant-for="' + escapeText(product.id) + '">' +
              product.variants.map((variant) => {
                const variantPrice = Number(variant.price || 0);
                const label = variantPrice && variantPrice !== Number(product.price || 0)
                  ? variant.name + ' - ' + formatMoney(variantPrice)
                  : variant.name;
                const unavailableLabel = variant.available ? '' : ' (unavailable)';
                return '<option value="' + escapeText(variant.id) + '" ' + (variant.available ? '' : 'disabled') + '>' + escapeText(label + unavailableLabel) + '</option>';
              }).join('') +
            '</select>'
          : '<span></span>';
        const isAvailable = product.availability === 'Available';
        return '<article class="card" data-card-product-id="' + escapeText(product.id) + '" data-available="' + (isAvailable ? 'true' : 'false') + '">' +
          '<div class="photo">' +
            (product.imageUrl
              ? '<img src="' + escapeText(product.imageUrl) + '" alt="' + escapeText(product.name) + '" loading="lazy" />'
              : '<span>No image</span>') +
          '</div>' +
          '<div class="body">' +
            '<h2 class="name">' + escapeText(product.name) + '</h2>' +
            (product.brand ? '<div class="brand">' + escapeText(product.brand) + '</div>' : '') +
            (product.category ? '<div class="category">' + escapeText(product.category) + '</div>' : '') +
            variants +
            '<div class="price-row">' +
              '<div class="price">' + formatMoney(Number(product.price || 0)) + '</div>' +
              '<span class="badge">' + escapeText(product.availability) + '</span>' +
            '</div>' +
            '<div class="order-actions">' +
              variantSelect +
              '<button class="add-button" data-product-id="' + escapeText(product.id) + '" type="button" ' + (isAvailable ? '' : 'disabled') + '>Add</button>' +
            '</div>' +
          '</div>' +
        '</article>';
      }).join('');
      empty.style.display = products.length ? 'none' : 'block';
    }

    function buildOrderPayload() {
      return {
        customerName: document.getElementById('customer-name').value.trim(),
        phone: document.getElementById('customer-phone').value.trim(),
        fulfillmentMethod: (new FormData(orderForm).get('fulfillmentMethod') || 'delivery'),
        deliveryAddress: document.getElementById('delivery-address').value.trim(),
        note: document.getElementById('order-note').value.trim(),
        items: Array.from(cart.values()).map((item) => ({
          productId: item.product.id,
          variantId: item.variant ? item.variant.id : null,
          quantity: item.quantity,
        })),
      };
    }

    function buildOrderMessage(order) {
      const lines = [
        'New catalog order #' + order.orderNumber,
        'Shop: ' + catalog.business.name,
        'Customer: ' + order.customerName,
        'Phone: ' + order.phone,
      ];
      lines.push('Method: ' + (order.fulfillmentMethod === 'pickup' ? 'Pickup' : 'Delivery'));
      if (order.deliveryAddress) lines.push('Address: ' + order.deliveryAddress);
      lines.push('', 'Items:');
      for (const item of order.items) {
        const label = item.variantName ? item.productName + ' - ' + item.variantName : item.productName;
        lines.push('- ' + item.quantity + ' x ' + label + ' @ ' + formatMoney(item.unitPrice) + ' = ' + formatMoney(item.lineTotal));
      }
      lines.push('', 'Total: ' + formatMoney(order.subtotal));
      if (order.note) lines.push('Note: ' + order.note);
      return lines.join('\\n');
    }

    function statusLabel(status) {
      return ({
        pending: 'Waiting for shop confirmation',
        accepted: 'Accepted by shop',
        payment_requested: 'Payment requested',
        fulfilled: 'Fulfilled',
        rejected: 'Rejected',
        cancelled: 'Cancelled',
      })[status] || status;
    }

    function renderTrackedOrder(order) {
      const method = order.fulfillmentMethod === 'pickup' ? 'Pickup' : 'Delivery';
      const items = (order.items || []).map((item) => {
        const label = item.variantName ? item.productName + ' - ' + item.variantName : item.productName;
        return '<li>' + escapeText(item.quantity + ' x ' + label) + '</li>';
      }).join('');
      trackingResult.innerHTML =
        '<strong>Order #' + escapeText(order.orderNumber) + '</strong><br>' +
        'Status: <strong>' + escapeText(statusLabel(order.status)) + '</strong><br>' +
        'Method: ' + escapeText(method) + '<br>' +
        'Total: ' + escapeText(formatMoney(order.subtotal)) +
        (items ? '<ul>' + items + '</ul>' : '');
      trackingResult.style.display = 'block';
    }

    async function submitTracking(event) {
      event.preventDefault();
      const orderNumber = trackingOrderNumber.value.trim().replace(/^#/, '');
      const phone = trackingPhone.value.trim();
      if (!orderNumber || !phone) {
        trackingResult.textContent = 'Enter both order number and phone number.';
        trackingResult.style.display = 'block';
        return;
      }
      trackingResult.textContent = 'Checking order...';
      trackingResult.style.display = 'block';
      try {
        const response = await fetch(
          '/api/public/catalog/' + encodeURIComponent(catalog.business.id) +
            '/orders/' + encodeURIComponent(orderNumber) +
            '?phone=' + encodeURIComponent(phone)
        );
        const body = await response.json().catch(() => ({}));
        if (!response.ok || body.ok !== true) {
          throw new Error(body.error || 'Order could not be found.');
        }
        renderTrackedOrder(body.data);
      } catch (error) {
        trackingResult.textContent = error.message || 'Order could not be found.';
      }
    }

    async function submitCatalogOrder(event) {
      event.preventDefault();
      errorBox.style.display = 'none';
      successBox.style.display = 'none';
      whatsappOrder.style.display = 'none';
      const payload = buildOrderPayload();
      if (!payload.items.length) {
        errorBox.textContent = 'Add at least one product first.';
        errorBox.style.display = 'block';
        return;
      }

      submitOrder.disabled = true;
      submitOrder.textContent = 'Submitting...';
      try {
        const response = await fetch('/api/public/catalog/' + encodeURIComponent(catalog.business.id) + '/orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        const body = await response.json().catch(() => ({}));
        if (!response.ok || body.ok !== true) {
          throw new Error(body.error || 'Order could not be submitted.');
        }

        const order = body.data;
        successBox.textContent = 'Order #' + order.orderNumber + ' received. The shop will confirm availability and payment.';
        successBox.style.display = 'block';
        trackingOrderNumber.value = order.orderNumber || '';
        trackingPhone.value = order.phone || payload.phone || '';
        if (shopWhatsApp) {
          whatsappOrder.href = 'https://wa.me/' + shopWhatsApp + '?text=' + encodeURIComponent(buildOrderMessage(order));
          whatsappOrder.style.display = 'flex';
        }
        cart.clear();
        renderCart();
        orderForm.reset();
      } catch (error) {
        errorBox.textContent = error.message || 'Order could not be submitted.';
        errorBox.style.display = 'block';
      } finally {
        submitOrder.textContent = 'Submit Order';
        renderCart();
      }
    }

    search.addEventListener('input', render);
    category.addEventListener('change', render);
    trackingForm.addEventListener('submit', submitTracking);
    grid.addEventListener('click', (event) => {
      const button = event.target.closest('[data-product-id]');
      const interactive = event.target.closest('select, option, input, textarea, a');
      const card = event.target.closest('[data-card-product-id]');
      if (!button && interactive) return;
      if (!button && (!card || card.getAttribute('data-available') !== 'true')) return;
      const productId = button
        ? button.getAttribute('data-product-id')
        : card.getAttribute('data-card-product-id');
      const select = Array.from(grid.querySelectorAll('[data-variant-for]'))
        .find((item) => item.getAttribute('data-variant-for') === productId);
      addToCart(productId, select ? select.value : '');
    });
    cartToggle.addEventListener('click', () => cartPanel.classList.toggle('open'));
    closeCart.addEventListener('click', () => cartPanel.classList.remove('open'));
    cartLines.addEventListener('input', (event) => {
      const input = event.target.closest('[data-cart-key]');
      if (!input) return;
      const item = cart.get(input.getAttribute('data-cart-key'));
      if (!item) return;
      item.quantity = Math.max(1, Number(input.value || 1));
      renderCart();
    });
    cartLines.addEventListener('click', (event) => {
      const button = event.target.closest('[data-remove-key]');
      if (!button) return;
      cart.delete(button.getAttribute('data-remove-key'));
      renderCart();
    });
    orderForm.addEventListener('submit', submitCatalogOrder);
    render();
    renderCart();
  </script>
</body>
</html>`;
}

function safePublicImageUrl(value) {
  const text = normalizeOptionalText(value);
  if (!text) {
    return null;
  }
  try {
    const url = new URL(text);
    return ['http:', 'https:'].includes(url.protocol) ? url.toString() : null;
  } catch (_) {
    return null;
  }
}

function currencyForCountry(countryCode) {
  const clean = String(countryCode || '').trim().toUpperCase();
  if (clean === 'KE') return 'KES';
  if (clean === 'TZ') return 'TZS';
  if (clean === 'UG') return 'UGX';
  if (clean === 'RW') return 'RWF';
  return 'KES';
}

function displayCurrencyForCountry(countryCode) {
  const clean = String(countryCode || '').trim().toUpperCase();
  if (clean === 'KE') return 'KSh';
  if (clean === 'TZ') return 'TSh';
  if (clean === 'UG') return 'USh';
  if (clean === 'RW') return 'FRw';
  if (clean === 'ZA') return 'R';
  if (clean === 'GB') return '\u00A3';
  return '$';
}

function normalizeBusinessCurrency(value) {
  const currency = normalizeOptionalText(value);
  if (!currency) {
    return null;
  }
  if (currency.length > 12 || /[<>{}"'`\\]/.test(currency)) {
    throw createHttpError(400, 'Choose a valid currency');
  }
  return currency;
}

function publicCatalogCurrencyInfo(currencyOverride, countryCode) {
  const fallbackCode = currencyForCountry(countryCode);
  const raw = normalizeOptionalText(currencyOverride);
  if (!raw) {
    return {
      code: fallbackCode,
      symbol: null,
      label: fallbackCode,
    };
  }

  const upper = raw.toUpperCase();
  if (/^[A-Z]{3}$/.test(upper)) {
    return {
      code: upper,
      symbol: null,
      label: upper,
    };
  }

  return {
    code: fallbackCode,
    symbol: raw,
    label: raw,
  };
}

function normalizePublicPhone(value) {
  const digits = String(value || '').replace(/\D/g, '');
  if (digits.startsWith('0') && digits.length === 10) {
    return `254${digits.slice(1)}`;
  }
  return digits;
}

function normalizePhoneForMatch(value) {
  return normalizePublicPhone(value);
}

function phoneMatchCandidates(value) {
  const raw = String(value || '').replace(/\D/g, '');
  const normalized = normalizePhoneForMatch(value);
  const candidates = new Set([raw, normalized].filter(Boolean));
  if (normalized.startsWith('254') && normalized.length === 12) {
    candidates.add(`0${normalized.slice(3)}`);
  }
  if (raw.startsWith('0') && raw.length === 10) {
    candidates.add(`254${raw.slice(1)}`);
  }
  return [...candidates];
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[char]));
}

function parseOptionalDate(value) {
  const raw = normalizeOptionalText(value);
  if (!raw) {
    return null;
  }
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    throw createHttpError(400, 'Invalid date');
  }
  return parsed;
}

function normalizeMpesaPhone(value) {
  const digits = String(value || '').replace(/\D/g, '');
  if (digits.startsWith('254') && digits.length === 12) {
    return digits;
  }
  if (digits.startsWith('0') && digits.length === 10) {
    return `254${digits.slice(1)}`;
  }
  if (digits.length === 9) {
    return `254${digits}`;
  }
  throw createHttpError(400, 'Enter a valid Kenyan M-Pesa phone number');
}

function formatMpesaTimestamp(date) {
  const pad = (value) => String(value).padStart(2, '0');
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join('');
}

function billingPeriodDays(period) {
  switch (String(period || '').toLowerCase()) {
    case 'yearly':
    case 'annual':
      return 365;
    case 'weekly':
      return 7;
    default:
      return 30;
  }
}

async function runDbQuery(target, sql, params = []) {
  if (typeof target === 'function') {
    return target(sql, params);
  }
  return target.query(sql, params);
}

function normalizeOptionalText(value) {
  if (value == null) {
    return null;
  }

  const normalized = String(value).trim();
  return normalized === '' ? null : normalized;
}

function maskSecret(value) {
  const normalized = normalizeOptionalText(value);
  if (!normalized) {
    return '';
  }
  return `${'*'.repeat(Math.max(0, normalized.length - 4))}${normalized.slice(-4)}`;
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

async function transcribeAudio(aiConfig, { audioBase64, mimeType, filename }) {
  const fetchModule = await import('node-fetch');
  const fetch = fetchModule.default;
  const FormDataCtor = globalThis.FormData || fetchModule.FormData;
  const BlobCtor = globalThis.Blob || fetchModule.Blob;
  const audioBuffer = Buffer.from(audioBase64, 'base64');
  if (audioBuffer.length === 0) {
    throw createHttpError(400, 'Audio payload is empty');
  }

  const formData = new FormDataCtor();
  formData.append(
    'file',
    new BlobCtor([audioBuffer], { type: mimeType || 'audio/mp4' }),
    filename || 'piki.m4a',
  );
  formData.append('model', aiConfig.stt_model || DEFAULT_STT_MODEL);
  formData.append('response_format', 'json');

  const response = await fetch(`${OPENROUTER_BASE_URL}/audio/transcriptions`, {
    method: 'POST',
    headers: openRouterHeaders(aiConfig.api_key),
    body: formData,
  });

  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'Whisper transcription failed',
    );
  }

  const text = body?.text || body?.transcript || '';
  return String(text).trim();
}

async function synthesizeSpeech(aiConfig, { text, voice }) {
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(`${OPENROUTER_BASE_URL}/audio/speech`, {
    method: 'POST',
    headers: {
      ...openRouterHeaders(aiConfig.api_key),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: aiConfig.tts_model || DEFAULT_TTS_MODEL,
      input: text,
      voice: voice || aiConfig.tts_voice || DEFAULT_TTS_VOICE,
      response_format: 'mp3',
    }),
  });

  if (!response.ok) {
    const body = await readMaybeJson(response);
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'TTS generation failed',
    );
  }

  const contentType = response.headers.get('content-type') || 'audio/mpeg';
  if (contentType.includes('application/json')) {
    const body = await response.json();
    const audioBase64 = body.audioBase64 || body.audio || body.data;
    if (!audioBase64) {
      throw createHttpError(502, 'TTS response did not include audio');
    }
    return { audioBase64, mimeType: body.mimeType || 'audio/mpeg' };
  }

  const arrayBuffer = await response.arrayBuffer();
  return {
    audioBase64: Buffer.from(arrayBuffer).toString('base64'),
    mimeType: contentType,
  };
}

function openRouterHeaders(apiKey) {
  return {
    Authorization: `Bearer ${apiKey}`,
    'HTTP-Referer': 'https://pikipos.com',
    'X-Title': 'Piki POS AI',
  };
}

async function readMaybeJson(response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    return { message: text };
  }
}

function normalizeInsightRow(row) {
  return {
    id: row.id,
    branchId: row.branch_id,
    severity: row.severity,
    kind: row.kind,
    title: row.title,
    body: row.body,
    action: row.action_json || {},
    dedupeKey: row.dedupe_key,
    status: row.status,
    generatedAt: toIsoString(row.generated_at),
  };
}

function normalizeLearningRow(row) {
  return {
    id: row.id,
    branchId: row.branch_id,
    kind: row.kind,
    phrase: row.phrase,
    target: row.target,
    weight: Number(row.weight || 0),
    metadata: row.metadata_json || {},
    updatedAt: toIsoString(row.updated_at),
  };
}

async function ensureAppVersionSchema(target = query) {
  await runDbQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS platform_app_version (
      id integer PRIMARY KEY DEFAULT 1,
      latest_version text NOT NULL DEFAULT '',
      minimum_version text NOT NULL DEFAULT '',
      apk_url text NOT NULL DEFAULT '',
      release_notes text NOT NULL DEFAULT '',
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      CONSTRAINT platform_app_version_single_row CHECK (id = 1)
    )
    `,
  );
  await runDbQuery(
    target,
    `
    INSERT INTO platform_app_version (
      id,
      latest_version,
      minimum_version,
      apk_url,
      release_notes
    )
    VALUES ($1, $2, $3, $4, $5)
    ON CONFLICT (id) DO NOTHING
    `,
    [
      1,
      process.env.APP_LATEST_VERSION || '',
      process.env.APP_MINIMUM_VERSION || '',
      process.env.APP_APK_URL || '',
      process.env.APP_RELEASE_NOTES || '',
    ],
  );
}

async function loadAppVersionConfig(target = query) {
  await ensureAppVersionSchema(target);
  const result = await runDbQuery(
    target,
    `
    SELECT latest_version, minimum_version, apk_url, release_notes, updated_at
    FROM platform_app_version
    WHERE id = 1
    LIMIT 1
    `,
  );
  return normalizeAppVersionRow(result.rows[0] || {});
}

async function saveAppVersionConfig(input = {}, target = query) {
  await ensureAppVersionSchema(target);
  const latestVersion = normalizeOptionalText(input.latestVersion || input.latest_version) || '';
  const minimumVersion = normalizeOptionalText(input.minimumVersion || input.minimum_version) || '';
  const apkUrl = normalizeOptionalText(input.apkUrl || input.apk_url) || '';
  const releaseNotes = normalizeOptionalText(input.releaseNotes || input.release_notes) || '';
  if (apkUrl && !isHttpsUrl(apkUrl)) {
    throw createHttpError(400, 'APK URL must be a valid HTTPS URL.');
  }
  const result = await runDbQuery(
    target,
    `
    INSERT INTO platform_app_version (
      id,
      latest_version,
      minimum_version,
      apk_url,
      release_notes,
      updated_at
    )
    VALUES (1, $1, $2, $3, $4, NOW())
    ON CONFLICT (id) DO UPDATE
    SET latest_version = EXCLUDED.latest_version,
        minimum_version = EXCLUDED.minimum_version,
        apk_url = EXCLUDED.apk_url,
        release_notes = EXCLUDED.release_notes,
        updated_at = NOW()
    RETURNING latest_version, minimum_version, apk_url, release_notes, updated_at
    `,
    [latestVersion, minimumVersion, apkUrl, releaseNotes],
  );
  return normalizeAppVersionRow(result.rows[0]);
}

function normalizeAppVersionRow(row) {
  return {
    latestVersion: row.latest_version || '',
    minimumVersion: row.minimum_version || '',
    apkUrl: row.apk_url || '',
    releaseNotes: row.release_notes || '',
    updatedAt: toIsoString(row.updated_at),
  };
}

async function loadPlatformReadiness() {
  const checks = [];
  const pushCheck = ({ key, label, status, severity = 'warning', message }) => {
    checks.push({ key, label, status, severity, message });
  };

  pushCheck({
    key: 'environment',
    label: 'Production Environment',
    status: config.nodeEnv === 'production' ? 'pass' : 'warning',
    severity: config.nodeEnv === 'production' ? 'info' : 'warning',
    message:
      config.nodeEnv === 'production'
        ? 'Backend is running in production mode.'
        : `Backend is running in ${config.nodeEnv}. Set NODE_ENV=production for launch.`,
  });

  pushCheck({
    key: 'platform_admin',
    label: 'Platform Admin Account',
    status:
      config.platformAdminEmail === 'superadmin@velora.pos'
        ? 'warning'
        : 'pass',
    severity: 'warning',
    message:
      config.platformAdminEmail === 'superadmin@velora.pos'
        ? 'Replace the default platform admin email before production.'
        : 'Platform admin email is customized.',
  });

  const paymentGateways = await listPaymentGateways({ includeSecrets: true });
  const activePaymentGateways = paymentGateways.filter(
    (gateway) => gateway.isActive === true,
  );
  if (activePaymentGateways.length === 0) {
    pushCheck({
      key: 'payment_gateways',
      label: 'Payment Gateways',
      status: 'warning',
      severity: 'warning',
      message:
        'No platform payment gateway is active. Shops can still use offline/manual payments, but subscription checkout will be limited.',
    });
  }
  for (const gateway of activePaymentGateways) {
    const errors = paymentGatewayReadinessErrors(gateway);
    pushCheck({
      key: `payment_${gateway.provider}`,
      label: `${gateway.displayName || gateway.provider} Gateway`,
      status: errors.length === 0 ? 'pass' : 'fail',
      severity: errors.length === 0 ? 'info' : 'critical',
      message:
        errors.length === 0
          ? 'Gateway is active and has required production fields.'
          : `Complete gateway setup: ${errors.join(', ')}.`,
    });
  }

  const messageGateways = await listMessageGateways({ includeSecrets: true });
  const activeMessageGateways = messageGateways.filter(
    (gateway) => gateway.isActive === true,
  );
  if (activeMessageGateways.length === 0) {
    pushCheck({
      key: 'message_gateways',
      label: 'WhatsApp/SMS API Sending',
      status: 'warning',
      severity: 'warning',
      message:
        'No WhatsApp or SMS API gateway is active. The app can still open WhatsApp/SMS manually.',
    });
  }
  for (const gateway of activeMessageGateways) {
    const errors = messageGatewayReadinessErrors(gateway);
    pushCheck({
      key: `message_${gateway.provider}`,
      label: `${gateway.displayName || gateway.provider} Messaging`,
      status: errors.length === 0 ? 'pass' : 'fail',
      severity: errors.length === 0 ? 'info' : 'critical',
      message:
        errors.length === 0
          ? 'Message gateway is active and configured.'
          : `Complete message gateway setup: ${errors.join(', ')}.`,
    });
  }

  const etimsConfig = await loadPlatformEtimsConfig({ includeSecrets: true });
  const etimsErrors = platformEtimsReadinessErrors(etimsConfig);
  pushCheck({
    key: 'kra_etims',
    label: 'KRA eTIMS Connector',
    status: etimsErrors.length === 0 ? 'pass' : 'warning',
    severity: 'warning',
    message:
      etimsErrors.length === 0
        ? 'KRA/eTIMS provider connector is active.'
        : `Complete KRA/eTIMS setup: ${etimsErrors.join(' ')}`,
  });

  const appVersion = await loadAppVersionConfig();
  pushCheck({
    key: 'app_version',
    label: 'App Version Rollout',
    status: appVersion.latestVersion && appVersion.apkUrl ? 'pass' : 'warning',
    severity: 'warning',
    message:
      appVersion.latestVersion && appVersion.apkUrl
        ? `Latest app version is ${appVersion.latestVersion}.`
        : 'Add latest version and HTTPS APK URL before shop rollout.',
  });

  const monitoringConfigured =
    Boolean(process.env.SENTRY_DSN?.trim()) ||
    Boolean(process.env.BACKEND_MONITORING_URL?.trim()) ||
    Boolean(process.env.UPTIME_MONITOR_URL?.trim());
  pushCheck({
    key: 'monitoring',
    label: 'Monitoring & Alerts',
    status: monitoringConfigured ? 'pass' : 'warning',
    severity: 'warning',
    message: monitoringConfigured
      ? 'Monitoring environment configuration is present.'
      : 'Add SENTRY_DSN, BACKEND_MONITORING_URL, or UPTIME_MONITOR_URL for production alerting.',
  });

  const criticalCount = checks.filter(
    (check) => check.status === 'fail' || check.severity === 'critical',
  ).length;
  const warningCount = checks.filter((check) => check.status === 'warning').length;
  return {
    status:
      criticalCount > 0 ? 'blocked' : warningCount > 0 ? 'needs_attention' : 'ready',
    criticalCount,
    warningCount,
    checks,
  };
}

function messageGatewayReadinessErrors(gateway) {
  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const errors = [];
  if (gateway.provider === 'whatsapp') {
    if (!publicConfig.baseUrl || !isHttpsUrl(publicConfig.baseUrl)) {
      errors.push('valid Graph API base URL');
    }
    if (!publicConfig.phoneNumberId) errors.push('phone number ID');
    if (!secretConfig.accessToken) errors.push('access token');
  } else if (gateway.provider === 'africas_talking') {
    if (!publicConfig.baseUrl || !isHttpsUrl(publicConfig.baseUrl)) {
      errors.push('valid messaging URL');
    }
    if (!publicConfig.username) errors.push('username');
    if (!secretConfig.apiKey) errors.push('API key');
  }
  return errors;
}

function paymentGatewayReadinessErrors(gateway) {
  try {
    validatePaymentGatewayConfiguration(gateway);
    return [];
  } catch (error) {
    const message = error.message || 'Payment gateway is incomplete.';
    return [message.replace(/^Complete [^:]+:\s*/i, '')];
  }
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

function normalizeUserRecordForStorage(record) {
  const normalized = { ...record };
  if (Object.prototype.hasOwnProperty.call(normalized, 'password')) {
    normalized.password = normalizePasswordForStorage(normalized.password);
  }
  return normalized;
}
