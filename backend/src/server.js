const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');

const { config } = require('./config');
const { query, withTransaction, withReadTransaction } = require('./db');
const {
  cacheGetJson,
  cacheGetText,
  cacheIncrement,
  cacheSetJson,
  cacheStatus,
} = require('./redisCache');
const { syncTables } = require('./syncTables');
const {
  buildRejectedWriteResult,
  canonicalizeRecord,
  prepareIncomingRecord,
} = require('./syncHelpers');
const { maxCursor, normalizeCursor } = require('./syncCursor');
const {
  activateBusinessAccess,
  ensureDeviceUserSchema,
  parseBearerToken,
  refreshBusinessAccess,
  resolveBusinessAccess,
} = require('./businessAccess');
const { deleteBusinessAccount } = require('./businessDeletion');
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
  consumeEmailOtpVerification,
  ensureEmailOtpSchema,
  requestEmailOtp,
  resetPasswordWithVerifiedOtp,
  verifyEmailOtp,
} = require('./authOtp');
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
  isPlausibleMpesaPasskey,
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
  handleMpesaC2BCallback,
  matchManualPayment,
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
const {
  buildCatalogStorefrontUrl,
  ensureBusinessCatalogSubdomain,
  ensureCatalogSubdomainSchema,
  extractCatalogSubdomain,
  findBusinessIdByCatalogSubdomain,
  initializeCatalogSubdomainSchema,
} = require('./catalogSubdomains');
const { normalizePublicCatalogBranches } = require('./catalogBranches');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: buildCorsOptions(),
});
const landingPageDir = path.resolve(__dirname, '..', '..', 'landing-page');
const landingIndexPath = path.join(landingPageDir, 'index.html');
const authRateLimit = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 20,
  keyPrefix: 'auth',
});
const platformLoginRateLimit = createRateLimiter({
  windowMs: 15 * 60 * 1000,
  max: 8,
  keyPrefix: 'platform-login',
});
const publicWriteRateLimit = createRateLimiter({
  windowMs: 60 * 1000,
  max: 30,
  keyPrefix: 'public-write',
});

// Serialize write transactions so revision cursors stay in commit order.
const PUSH_LOCK_CLASS_ID = 41831;
const PUSH_LOCK_OBJECT_ID = 1;
const CATALOG_CACHE_TABLES = new Set([
  'branches',
  'categories',
  'products',
  'product_variants',
  'services',
  'stock_batches',
  'sale_items',
  'sales',
  'purchase_invoices',
  'stock_transfers',
]);

app.disable('x-powered-by');
app.use(applySecurityHeaders);
app.use(cors(buildCorsOptions()));
app.use(express.json({ limit: '10mb' }));

io.use(async (socket, next) => {
  try {
    const accessToken =
      parseBearerToken(socket.handshake.headers?.authorization) ||
      normalizeOptionalText(socket.handshake.auth?.accessToken) ||
      normalizeOptionalText(socket.handshake.query?.accessToken);
    const deviceId =
      normalizeOptionalText(socket.handshake.auth?.deviceId) ||
      normalizeOptionalText(socket.handshake.query?.deviceId);
    const businessContext = await resolveBusinessAccess({
      accessToken,
      deviceId,
    });

    if (!businessContext) {
      next(createHttpError(401, 'Invalid realtime sync credentials'));
      return;
    }

    socket.data.businessId = businessContext.businessId;
    socket.data.deviceId = deviceId;
    socket.join(realtimeBusinessRoom(businessContext.businessId));
    next();
  } catch (error) {
    next(error);
  }
});

io.on('connection', (socket) => {
  socket.emit('sync:connected', {
    businessId: socket.data.businessId,
    deviceId: socket.data.deviceId,
    serverTime: new Date().toISOString(),
  });
});

app.get('/api/health', async (req, res) => {
  try {
    await query('SELECT 1');
    const cache = await cacheStatus();
    res.json({
      ok: true,
      service: 'velora-pos-sync-backend',
      database: 'postgresql',
      cache,
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

app.put('/api/business/profile', async (req, res, next) => {
  try {
    const accessToken = parseBearerToken(req.headers.authorization);
    if (!accessToken) {
      throw createHttpError(401, 'Authorization token is required');
    }

    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);

    const businessName = normalizeOptionalText(
      req.body?.businessName ?? req.body?.name,
    );
    const hasCurrency = Object.prototype.hasOwnProperty.call(
      req.body || {},
      'currency',
    );
    const currency = hasCurrency
      ? normalizeBusinessCurrency(req.body?.currency)
      : null;

    if (!businessName && !currency) {
      throw createHttpError(400, 'Business name or currency is required');
    }

    await query(
      `
      UPDATE businesses
      SET
        name = COALESCE($2, name),
        currency = COALESCE($3, currency),
        updated_at = NOW()
      WHERE id = $1
        AND deleted_at IS NULL
      `,
      [businessContext.businessId, businessName, currency],
    );

    await invalidateCatalogCache(businessContext.businessId);
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'business_profile',
      tables: ['businesses'],
    });

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

app.post('/api/auth/email-otp/request', authRateLimit, async (req, res, next) => {
  try {
    const result = await requestEmailOtp({
      email: req.body?.email,
      purpose: req.body?.purpose || 'signup',
    });
    res.json({ ok: true, ...result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/auth/email-otp/verify', authRateLimit, async (req, res, next) => {
  try {
    const result = await verifyEmailOtp({
      email: req.body?.email,
      code: req.body?.code,
      purpose: req.body?.purpose || 'signup',
    });
    res.json({ ok: true, ...result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/auth/password-reset/complete', authRateLimit, async (req, res, next) => {
  try {
    const result = await resetPasswordWithVerifiedOtp({
      email: req.body?.email,
      verificationToken:
        req.body?.emailVerificationToken || req.body?.verificationToken,
      newPassword: req.body?.newPassword || req.body?.password,
    });
    res.json({ ok: true, ...result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/auth/register', authRateLimit, async (req, res, next) => {
  try {
    const businessName = normalizeOptionalText(req.body?.businessName);
    const ownerName = normalizeOptionalText(req.body?.ownerName);
    const ownerEmail = normalizeOptionalText(req.body?.ownerEmail);
    const phone = normalizeOptionalText(req.body?.phone);
    const password = req.body?.password;
    const emailVerificationToken = normalizeOptionalText(
      req.body?.emailVerificationToken || req.body?.verificationToken,
    );
    const deviceId = normalizeOptionalText(req.body?.deviceId);
    const deviceName = normalizeOptionalText(req.body?.deviceName);
    const requestedCountry = normalizeOptionalText(req.body?.countryCode);
    const requestedCurrency = normalizeBusinessCurrency(req.body?.currency);
    const requestedProvider = normalizeOptionalText(req.body?.provider);
    const platform = normalizeSubscriptionPlatform(req.body?.platform);
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
    await ensureDeviceUserSchema();
    const countryCode = normalizeCountryCode(requestedCountry);
    const markets = subscriptionMarketsForPlatform(
      await listPublicMarkets(),
      platform,
      countryCode,
    );
    const market = selectSubscriptionMarket(markets, {
      countryCode: requestedCountry,
      provider: requestedProvider,
    });
    if (!market) {
      throw createHttpError(400, 'No active subscription market is configured for this country');
    }
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
      await ensureCatalogSubdomainSchema(client);

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

      await consumeEmailOtpVerification({
        email: ownerEmail,
        purpose: 'signup',
        verificationToken: emailVerificationToken,
        target: client,
      });

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
      const publicSubdomain = await ensureBusinessCatalogSubdomain(client, {
        businessId,
        businessName,
      });

      await client.query(
        `UPDATE devices
         SET user_id = $2, updated_at = $3
         WHERE id = $1 AND business_id = $4`,
        [deviceId, userId, now.toISOString(), businessId],
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
        business: {
          id: businessId,
          name: businessName,
          countryCode,
          currency,
          sellingMode,
          publicSubdomain,
        },
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

app.post('/api/auth/login', authRateLimit, async (req, res, next) => {
  try {
    await ensureDeviceUserSchema();
    await ensureCatalogSubdomainSchema(query);
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
           AND b.deleted_at IS NULL
         WHERE LOWER(TRIM(u.email)) = LOWER(TRIM($1))
           AND u.deleted_at IS NULL
         ORDER BY u.last_seen_at DESC NULLS LAST, u.created_at DESC`,
        [email],
      );

      if (!userResult.rows.length) {
        throw createHttpError(401, 'Invalid email or password');
      }

      const matchingUsers = userResult.rows.filter((candidate) =>
        verifyPassword(candidate.password, password),
      );
      if (!matchingUsers.length) {
        throw createHttpError(401, 'Invalid email or password');
      }
      const matchingBusinessIds = new Set(
        matchingUsers.map((candidate) => candidate.business_id),
      );
      if (matchingBusinessIds.size > 1) {
        throw createHttpError(
          409,
          'This staff email is used in more than one business. Ask an admin to give each staff account a unique email address before signing in.',
        );
      }

      const user = matchingUsers[0];

      const businessId = user.business_id;
      const now = new Date();
      const passwordNeedsRehash = needsPasswordRehash(user.password);

      // Ensure device is linked to this business
      await client.query(
        `INSERT INTO devices (id, business_id, user_id, name, last_seen_at, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $5, $5)
         ON CONFLICT (id) DO UPDATE
         SET business_id = EXCLUDED.business_id,
             user_id = EXCLUDED.user_id,
             name = COALESCE(EXCLUDED.name, devices.name),
             last_seen_at = EXCLUDED.last_seen_at,
             updated_at = EXCLUDED.updated_at`,
        [deviceId, businessId, user.id, deviceName, now.toISOString()],
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

app.delete('/api/business', deleteBusinessRoute);
app.post('/api/business/delete', deleteBusinessRoute);

app.post('/api/users/upsert', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireAdmin(businessContext);
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
    const requestedCashierId = normalizeOptionalText(req.query.cashierId);
    const userId = normalizeOptionalText(req.query.userId);
    const scope = resolveDataScope(businessContext, req.query.branchId);

    if (userId && userId !== businessContext.userId) {
      throw createHttpError(403, 'Employee identity does not match this device');
    }
    await updateLastSeen(businessContext.userId, businessContext.businessId);

    const cashierId = businessContext.role === 'CASHIER'
      ? businessContext.userId
      : requestedCashierId;

    const whereClauses = ['s.business_id = $1', 'DATE(s.created_at) = $2'];
    const params = [businessContext.businessId, date];
    if (cashierId) {
      whereClauses.push(`s.user_id = $${params.length + 1}`);
      params.push(cashierId);
    }
    if (scope.branchIds != null) {
      whereClauses.push(
        `COALESCE(s.branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`,
      );
      params.push(scope.branchIds);
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
    const businessContext = await requireBusinessContext(req, {
      allowReadOnlyExpired: true,
    });
    const syncWindow = parseSyncWindow(req.query);
    const userId = normalizeOptionalText(req.query.userId);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const scopeKey = dataScopeKey(businessContext, scope);
    if (normalizeOptionalText(req.query.scopeKey) !== scopeKey) {
      syncWindow.cursor = '0';
      syncWindow.since = null;
    }

    if (userId && userId !== businessContext.userId) {
      throw createHttpError(403, 'Employee identity does not match this device');
    }
    await updateLastSeen(businessContext.userId, businessContext.businessId);

    const summary = await withReadTransaction(async (client) => {
      const snapshotCursor = await getSnapshotCursor(
        client,
        businessContext.businessId,
        scope,
      );
      const tables = {};

      for (const table of syncTables) {
        const { sql, params } = buildStatusQuery(
          table.name,
          syncWindow,
          businessContext.businessId,
          scope,
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
      scopeKey,
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
    const businessContext = await requireBusinessContext(req, {
      allowReadOnlyExpired: true,
    });
    const syncWindow = parseSyncWindow(req.query);
    const userId = normalizeOptionalText(req.query.userId);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const scopeKey = dataScopeKey(businessContext, scope);
    if (normalizeOptionalText(req.query.scopeKey) !== scopeKey) {
      syncWindow.cursor = '0';
      syncWindow.since = null;
    }

    if (userId && userId !== businessContext.userId) {
      throw createHttpError(403, 'Employee identity does not match this device');
    }
    await updateLastSeen(businessContext.userId, businessContext.businessId);

    const summary = await withReadTransaction(async (client) => {
      const snapshotCursor = await getSnapshotCursor(
        client,
        businessContext.businessId,
        scope,
      );
      const data = {};

      for (const table of syncTables) {
        const { sql, params } = buildPullQuery(
          table.name,
          syncWindow,
          businessContext.businessId,
          scope,
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
      scopeKey,
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
    const scope = resolveDataScope(businessContext, branchId);

    if (!deviceId) {
      return res.status(400).json({ ok: false, error: 'deviceId is required' });
    }

    if (!changes || typeof changes !== 'object') {
      return res
        .status(400)
        .json({ ok: false, error: 'changes payload is required' });
    }

    if (userId && userId !== businessContext.userId) {
      throw createHttpError(403, 'Employee identity does not match this device');
    }
    await updateLastSeen(businessContext.userId, businessContext.businessId);

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
      const appliedProductIds = new Set();
      const appliedVariantIds = new Set();
      const appliedStockBatchProductIds = new Set();
      const appliedSaleIds = new Set();
      const affectedSaleIds = new Set();
      const affectedCustomerIds = new Set();
      const appliedRefundRows = [];
      const incomingCreditTotals = sumIncomingAmounts(
        changes.credit_payments,
        'sale_id',
        'amount',
      );
      const incomingRefundTotals = sumIncomingAmounts(
        changes.sales,
        'refund_for_sale_id',
        'total_amount',
        { absolute: true },
      );

      for (const saleId of new Set([
        ...incomingCreditTotals.keys(),
        ...incomingRefundTotals.keys(),
      ])) {
        await ensureSaleCreditBaselineFromServer(
          client,
          businessContext.businessId,
          saleId,
        );
      }

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
          const accessValidation = await validateSyncWriteAccess(
            client,
            table.name,
            prepared.record,
            scope,
            businessContext,
          );
          if (!accessValidation.ok) {
            invalid[table.name] += 1;
            tableInvalidRows.push({
              id: prepared.record.id,
              ...accessValidation.error,
            });
            continue;
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
            if (
              table.name === 'users' &&
              businessContext.bootstrapUser &&
              normalizeOptionalText(storageRecord.id) === businessContext.userId
            ) {
              await client.query(
                `UPDATE devices
                 SET user_id = $3, updated_at = NOW()
                 WHERE business_id = $1 AND id = $2`,
                [
                  businessContext.businessId,
                  businessContext.deviceId,
                  businessContext.userId,
                ],
              );
            }
            if (table.name === 'products') {
              appliedProductIds.add(normalizeOptionalText(storageRecord.id));
            }
            if (table.name === 'product_variants') {
              appliedVariantIds.add(normalizeOptionalText(storageRecord.id));
            }
            if (table.name === 'stock_batches') {
              appliedStockBatchProductIds.add(
                normalizeOptionalText(storageRecord.product_id),
              );
            }
            if (table.name === 'sales') {
              const saleId = normalizeOptionalText(storageRecord.id);
              appliedSaleIds.add(saleId);
              const customerId = normalizeOptionalText(storageRecord.customer_id);
              if (customerId) affectedCustomerIds.add(customerId);
              if (customerId) affectedSaleIds.add(saleId);
              await ensureSaleCreditBaselineFromIncoming(
                client,
                businessContext.businessId,
                storageRecord,
                incomingCreditTotals.get(saleId) || 0,
                incomingRefundTotals.get(saleId) || 0,
              );
              if (normalizeOptionalText(storageRecord.refund_for_sale_id)) {
                appliedRefundRows.push(storageRecord);
                affectedSaleIds.add(
                  normalizeOptionalText(storageRecord.refund_for_sale_id),
                );
              }
            }
            if (table.name === 'sale_items') {
              const productId = normalizeOptionalText(storageRecord.product_id);
              const variantId = normalizeOptionalText(storageRecord.variant_id);
              const stockRevision = await applySaleItemStockEffect(
                client,
                storageRecord,
                businessContext.businessId,
                {
                  applyProductStock:
                    !appliedProductIds.has(productId),
                  applyVariantStock:
                    !variantId || !appliedVariantIds.has(variantId),
                  applyBatchStock:
                    !variantId && !appliedStockBatchProductIds.has(productId),
                },
              );
              latestAppliedCursor = maxCursor(latestAppliedCursor, stockRevision);
            }
            if (table.name === 'credit_payments') {
              const customerId = normalizeOptionalText(storageRecord.customer_id);
              const saleId = normalizeOptionalText(storageRecord.sale_id);
              if (customerId) affectedCustomerIds.add(customerId);
              if (saleId) affectedSaleIds.add(saleId);
              if (!appliedSaleIds.has(saleId)) {
                const paymentRevision = await applyCreditPaymentEffect(
                  client,
                  storageRecord,
                  businessContext.businessId,
                );
                latestAppliedCursor = maxCursor(
                  latestAppliedCursor,
                  paymentRevision,
                );
              }
            }
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

      for (const refund of appliedRefundRows) {
        if (appliedSaleIds.has(normalizeOptionalText(refund.refund_for_sale_id))) {
          continue;
        }
        const refundRevision = await applyRefundBalanceEffect(
          client,
          refund,
          businessContext.businessId,
        );
        latestAppliedCursor = maxCursor(latestAppliedCursor, refundRevision);
      }

      for (const saleId of affectedSaleIds) {
        const rebuilt = await rebuildSaleCreditBalance(
          client,
          businessContext.businessId,
          saleId,
        );
        latestAppliedCursor = maxCursor(
          latestAppliedCursor,
          rebuilt?.serverRevision,
        );
        if (rebuilt?.customerId) {
          affectedCustomerIds.add(rebuilt.customerId);
        }
      }

      for (const customerId of affectedCustomerIds) {
        const customerRevision = await rebuildCustomerBalance(
          client,
          businessContext.businessId,
          customerId,
        );
        latestAppliedCursor = maxCursor(latestAppliedCursor, customerRevision);
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

    if (hasCatalogCacheChanges(summary)) {
      await invalidateCatalogCache(businessContext.businessId);
    }
    const changedTables = changedTablesFromPushSummary(summary);
    if (changedTables.length > 0) {
      notifyBusinessRealtimeChange({
        businessId: businessContext.businessId,
        sourceDeviceId: deviceId,
        reason: 'sync_push',
        tables: changedTables,
      });
    }

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
    const payload = jwt.verify(token, config.platformJwtSecret);
    if (payload?.role !== 'superadmin') {
      throw createHttpError(403, 'Insufficient platform admin privileges');
    }
    next();
  } catch (error) {
    const status = error?.statusCode || error?.status || 401;
    const message = error?.message || 'Invalid or expired admin token';
    next(createHttpError(status, message));
  }
}

app.post('/api/platform/login', platformLoginRateLimit, (req, res, next) => {
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
    await initializeCatalogSubdomainSchema(query);
    const result = await withReadTransaction(async (client) => {
      const bizRes = await client.query(
        'SELECT COUNT(*) FROM businesses WHERE deleted_at IS NULL',
      );
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
    await initializeCatalogSubdomainSchema(query);
    const result = await query(`
      SELECT b.id, b.name, b.owner_name, b.owner_email, b.public_subdomain,
             b.country_code, b.currency, b.selling_mode, b.created_at,
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
      WHERE b.deleted_at IS NULL
      ORDER BY b.created_at DESC
    `);
    res.json({ ok: true, data: result.rows });
  } catch (error) {
    next(error);
  }
});

app.get('/api/platform/users', requirePlatformAdmin, async (req, res, next) => {
  try {
    await initializeCatalogSubdomainSchema(query);
    const result = await query(`
      SELECT u.id, u.name, u.email, u.role, u.created_at, u.last_seen_at, b.name as business_name
      FROM users u
      LEFT JOIN businesses b ON b.id = u.business_id AND b.deleted_at IS NULL
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
    const plans = (await listPlans({ includeInactive: true })).map((plan) => ({
      ...plan,
      prices: (plan.prices || []).filter((price) => price.provider !== 'mpesa'),
    }));
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
    await initializeCatalogSubdomainSchema(query);
    const businessId = normalizeOptionalText(req.params.businessId);
    const plan = normalizeOptionalText(req.body?.plan || req.body?.planCode);
    const status = normalizeOptionalText(req.body?.status) || 'active';
    if (!businessId || !plan) {
      throw createHttpError(400, 'businessId and plan are required');
    }

    const businessResult = await query(
      'SELECT id, selling_mode FROM businesses WHERE id = $1 AND deleted_at IS NULL LIMIT 1',
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
    const requestedCountry = normalizeCountryCode(
      normalizeOptionalText(req.query?.countryCode) || 'KE',
    );
    const requestedProvider = normalizeOptionalText(req.query?.provider);
    const platform = normalizeSubscriptionPlatform(req.query?.platform);
    const markets = subscriptionMarketsForPlatform(
      await listPublicMarkets(),
      platform,
      requestedCountry,
    );
    const selectedMarket = selectSubscriptionMarket(markets, {
      countryCode: requestedCountry,
      provider: requestedProvider,
    });
    const countryCode = requestedCountry;
    const plans = selectedMarket
      ? await listPublicPlans({ countryCode })
      : [];
    res.json({
      ok: true,
      countryCode,
      platform,
      provider: selectedMarket?.provider || null,
      selectedMarket,
      markets,
      plans,
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
    const platform = normalizeSubscriptionPlatform(req.query?.platform);
    const overview = await loadSubscriptionOverview(
      businessContext.businessId,
      businessContext.plan,
      countryCode,
      businessContext.sellingMode,
      platform,
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
    const platform = normalizeSubscriptionPlatform(req.body?.platform);
    if (
      requestedProvider &&
      !subscriptionProviderAllowedForPlatform(requestedProvider, platform)
    ) {
      throw createHttpError(
        400,
        platform === 'android'
          ? 'Android subscriptions must use Google Play Billing.'
          : 'Windows subscriptions must use PayPal or Flutterwave.',
      );
    }
    const countryCode = normalizeCountryCode(requestedCountry);
    const markets = subscriptionMarketsForPlatform(
      await listPublicMarkets(),
      platform,
      countryCode,
    );
    const market = selectSubscriptionMarket(markets, {
      countryCode: requestedCountry,
      provider: requestedProvider,
    });
    const provider = normalizeProvider(market?.provider || requestedProvider);
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
    if (!subscriptionProviderAllowedForPlatform(market.provider, platform)) {
      throw createHttpError(400, 'This payment method is not available on this platform');
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
    if (!isFreePlan && provider === 'google_play' && !price.storeProductId) {
      throw createHttpError(400, 'Google Play product ID is not configured for this plan');
    }
    if (!isFreePlan && (provider === 'paypal' || provider === 'flutterwave')) {
      assertPublicPaymentReturnUrl();
    }
    const checkout = await withTransaction(async (client) => {
      const payment = await createSubscriptionPayment(client, {
        businessId: businessContext.businessId,
        planCode,
        price,
        provider,
        countryCode,
        sellingMode,
        phoneNumber: null,
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

    let providerCheckout = {};
    if (provider === 'paypal') {
      providerCheckout = await initiatePayPalCheckout(checkout, gateway);
    } else if (provider === 'flutterwave') {
      providerCheckout = await initiateFlutterwaveCheckout(checkout, gateway);
    } else if (provider === 'google_play') {
      providerCheckout = {
        storeProductId: price.storeProductId,
        message: 'Complete this purchase through Google Play.',
      };
    }

    res.json({
      ok: true,
      data: {
        ...checkout,
        ...providerCheckout,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/subscription/google-play/confirm', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      allowExpired: true,
    });
    const paymentId = normalizeOptionalText(req.body?.paymentId);
    const productId = normalizeOptionalText(req.body?.productId);
    const purchaseToken = normalizeOptionalText(req.body?.purchaseToken);
    if (!paymentId || !productId || !purchaseToken) {
      throw createHttpError(
        400,
        'paymentId, productId, and purchaseToken are required',
      );
    }

    const result = await processGooglePlayConfirmation({
      businessId: businessContext.businessId,
      paymentId,
      productId,
      purchaseToken,
    });
    res.json({ ok: true, data: result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/subscription/paypal/return', async (req, res) => {
  try {
    const paymentId = normalizeOptionalText(req.query?.paymentId);
    const orderId = normalizeOptionalText(req.query?.token);
    if (!paymentId || !orderId) {
      throw createHttpError(400, 'PayPal payment reference is missing');
    }
    await processPayPalReturn({ paymentId, orderId });
    sendPaymentReturnPage(res, {
      title: 'Payment completed',
      message: 'Your Piki subscription is active. You can return to the app.',
    });
  } catch (error) {
    sendPaymentReturnPage(res, {
      statusCode: error.statusCode || 400,
      title: 'Payment not completed',
      message: error.message || 'PayPal payment could not be confirmed.',
    });
  }
});

app.get('/api/subscription/paypal/cancel', async (req, res) => {
  try {
    const paymentId = normalizeOptionalText(req.query?.paymentId);
    if (paymentId) {
      await markSubscriptionPaymentStatus(paymentId, 'cancelled', {
        message: 'PayPal checkout was cancelled.',
      });
    }
    sendPaymentReturnPage(res, {
      title: 'Payment cancelled',
      message: 'No payment was taken. You can return to the app and try again.',
    });
  } catch (error) {
    sendPaymentReturnPage(res, {
      statusCode: 500,
      title: 'Payment cancelled',
      message: 'Return to the app to check your subscription status.',
    });
  }
});

app.get('/api/subscription/flutterwave/return', async (req, res) => {
  try {
    const paymentId = normalizeOptionalText(req.query?.paymentId);
    const transactionId = normalizeOptionalText(req.query?.transaction_id);
    const transactionReference = normalizeOptionalText(req.query?.tx_ref);
    const status = normalizeOptionalText(req.query?.status);
    if (status !== 'successful') {
      if (paymentId) {
        await markSubscriptionPaymentStatus(paymentId, 'cancelled', {
          message: 'Flutterwave checkout was not completed.',
          status,
        });
      }
      throw createHttpError(400, 'Flutterwave payment was not completed');
    }
    if (!paymentId || !transactionId || !transactionReference) {
      throw createHttpError(400, 'Flutterwave payment reference is missing');
    }
    await processFlutterwaveReturn({
      paymentId,
      transactionId,
      transactionReference,
    });
    sendPaymentReturnPage(res, {
      title: 'Payment completed',
      message: 'Your Piki subscription is active. You can return to the app.',
    });
  } catch (error) {
    sendPaymentReturnPage(res, {
      statusCode: error.statusCode || 400,
      title: 'Payment not completed',
      message: error.message || 'Flutterwave payment could not be confirmed.',
    });
  }
});

app.post('/api/payments/mpesa/stk-callback', handlePosMpesaStkCallback);

// Keep the old callback URL working for shops that have not updated Daraja yet.
app.post('/api/subscription/mpesa/callback', handlePosMpesaStkCallback);

async function handlePosMpesaStkCallback(req, res, next) {
  try {
    validateMpesaCallbackSecret(req);
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
      const paymentResult = await handlePosMpesaCallback({
        checkoutRequestId,
        resultCode,
        resultDescription: callback.ResultDesc,
        metadata,
      });
      if (paymentResult?.businessId) {
        notifyBusinessRealtimeChange({
          businessId: paymentResult.businessId,
          reason: 'payment',
          tables: paymentResult.saleId ? ['sales'] : [],
        });
      }
    }

    res.json({ ok: true });
  } catch (error) {
    next(normalizeRouteError(error));
  }
}

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

app.post(
  '/api/business/payment-gateways/:provider/test-connection',
  async (req, res, next) => {
    try {
      const businessContext = await requireBusinessContext(req);
      const gateway = await loadBusinessPaymentGateway(
        businessContext.businessId,
        req.params.provider,
        { includeSecrets: true },
      );
      if (!gateway?.isActive) {
        return res.json({
          ok: true,
          data: {
            success: false,
            message: 'M-Pesa is not configured or inactive.',
            gatewayActive: false,
          },
        });
      }
      const mpesaConfig = resolveMpesaGatewayConfig(gateway);
      if (!mpesaConfig.consumerKey || !mpesaConfig.consumerSecret) {
        return res.json({
          ok: true,
          data: {
            success: false,
            message: 'Consumer key and secret are required.',
            gatewayActive: true,
          },
        });
      }
      const start = Date.now();
      const token = await getMpesaAccessToken(mpesaConfig);
      const elapsed = Date.now() - start;
      res.json({
        ok: true,
        data: {
          success: true,
          message: `Connected to Safaricom Daraja API in ${elapsed}ms. Token obtained successfully.`,
          gatewayActive: true,
          latencyMs: elapsed,
        },
      });
    } catch (error) {
      const message =
        error?.message || 'Connection test failed. Check your credentials.';
      res.json({
        ok: true,
        data: {
          success: false,
          message,
          gatewayActive: true,
        },
      });
    }
  },
);

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
      userId: businessContext.userId,
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

app.post('/api/payments/mpesa/c2b-validation', async (req, res) => {
  try {
    validateMpesaCallbackSecret(req);
    await handleMpesaC2BCallback({ payload: req.body, persist: false });
    res.json({ ResultCode: 0, ResultDesc: 'Accepted' });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      ResultCode: 1,
      ResultDesc: error.message || 'Rejected',
    });
  }
});

app.post('/api/payments/mpesa/c2b-confirmation', async (req, res) => {
  try {
    validateMpesaCallbackSecret(req);
    await handleMpesaC2BCallback({ payload: req.body, persist: true });
    res.json({ ResultCode: 0, ResultDesc: 'Accepted' });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      ResultCode: 1,
      ResultDesc: error.message || 'Rejected',
    });
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

app.post('/api/payments/mpesa/claim-c2b', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const amount =
      req.body?.amount != null
        ? Number(req.body.amount)
        : req.body?.amountMinor != null
          ? Number(req.body.amountMinor) / 100
          : null;
    const payment = await matchManualPayment({
      businessId: businessContext.businessId,
      referenceCode: req.body?.referenceCode,
      phoneNumber: req.body?.phoneNumber,
      amount,
      checkoutCode: req.body?.checkoutCode,
      saleId: req.body?.saleId,
    });
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'payment',
      tables: ['sales'],
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
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'payment',
      tables: ['sales'],
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
    await invalidateCatalogCache(businessContext.businessId);
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
      userId: businessContext.userId,
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

function extractOpenRouterTextContent(body) {
  const message = body?.choices?.[0]?.message || {};
  const content = message.content;
  if (typeof content === 'string') {
    return content.trim();
  }
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === 'string') return part;
        if (typeof part?.text === 'string') return part.text;
        if (typeof part?.content === 'string') return part.content;
        return '';
      })
      .join('\n')
      .trim();
  }
  return '';
}

function parseJsonObjectFromText(text) {
  const normalized = normalizeOptionalText(text);
  if (!normalized) {
    return null;
  }
  try {
    return JSON.parse(normalized);
  } catch (_) {
    const fenced = normalized.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    if (fenced) {
      try {
        return JSON.parse(fenced[1]);
      } catch (_) {
        // Continue to object slicing below.
      }
    }
    const start = normalized.indexOf('{');
    const end = normalized.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(normalized.slice(start, end + 1));
      } catch (_) {
        return null;
      }
    }
  }
  return null;
}

function normalizeImageAnalysisItems(items) {
  if (!Array.isArray(items)) {
    return [];
  }
  return items
    .filter((item) => item && typeof item === 'object')
    .slice(0, 20)
    .map((item) => {
      const quantity = Number(item.quantity ?? item.qty ?? 1);
      const unitPrice = Number(
        item.unit_price ??
        item.unitPrice ??
        item.price ??
        item.selling_price ??
        item.sellingPrice ??
        0,
      );
      const cost = Number(item.cost ?? item.unit_cost ?? item.unitCost ?? 0);
      const stock = Number(item.stock ?? item.initial_stock ?? item.initialStock ?? 0);
      return {
        name: normalizeOptionalText(item.name || item.product_name || item.productName) || 'Item',
        quantity: Number.isFinite(quantity) && quantity > 0 ? quantity : 1,
        unit: normalizeOptionalText(item.unit || item.sale_unit || item.saleUnit) || 'pcs',
        unit_price: Number.isFinite(unitPrice) && unitPrice > 0 ? unitPrice : null,
        price: Number.isFinite(unitPrice) && unitPrice > 0 ? unitPrice : null,
        cost: Number.isFinite(cost) && cost >= 0 ? cost : null,
        stock: Number.isFinite(stock) && stock >= 0 ? stock : null,
        sku: normalizeOptionalText(item.sku),
        barcode: normalizeOptionalText(item.barcode),
        brand: normalizeOptionalText(item.brand),
        category: normalizeOptionalText(item.category),
        notes: normalizeOptionalText(item.notes || item.note),
        confidence: item.confidence,
      };
    })
    .filter((item) => item.name && item.name !== 'Item');
}

async function requestOpenRouterOrderImageAnalysis({
  fetchImpl,
  aiConfig,
  imageDataUrl,
  note,
}) {
  const userNote = normalizeOptionalText(note);
  const prompt = `You are helping a Kenyan POS owner use Piki POS from a camera photo.

Read the image and extract product or sale lines that can become POS records.

Return JSON only, no markdown, with this shape:
{
  "summary": "short practical summary",
  "intent": "product" | "sale" | "mixed" | "unknown",
  "confidence": 0.0,
  "items": [
    {
      "name": "product name",
      "quantity": 1,
      "unit": "pcs",
      "unit_price": 0,
      "cost": 0,
      "stock": 0,
      "sku": "",
      "barcode": "",
      "brand": "",
      "category": "",
      "notes": ""
    }
  ]
}

Rules:
- If it is a product/package photo, infer only visible product identity and any visible price/barcode. Do not invent prices.
- If it is a receipt, handwritten order, shelf label, or invoice, extract line items, quantities, and prices only when visible.
- Use null or omit unknown numbers. Keep names short and clean.
- If the image is unclear, return intent "unknown", confidence below 0.4, and no items.
${userNote ? `Owner note: ${userNote}` : ''}`;

  const response = await fetchImpl(`${OPENROUTER_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${aiConfig.api_key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://pikipos.com',
      'X-Title': 'Piki POS Image Analysis',
    },
    body: JSON.stringify({
      model: aiConfig.model || 'openai/gpt-4o-mini',
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: imageDataUrl } },
          ],
        },
      ],
      max_tokens: 900,
      temperature: 0.1,
    }),
  });

  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'OpenRouter image analysis failed',
    );
  }

  const content = extractOpenRouterTextContent(body);
  const parsed = parseJsonObjectFromText(content);
  const items = normalizeImageAnalysisItems(parsed?.items);
  return {
    summary:
      normalizeOptionalText(parsed?.summary) ||
      (items.length
        ? `Detected ${items.length} item line${items.length === 1 ? '' : 's'} from the image.`
        : 'No clear product or sale lines were detected in the image.'),
    intent: normalizeOptionalText(parsed?.intent) || 'unknown',
    confidence:
      typeof parsed?.confidence === 'number' && Number.isFinite(parsed.confidence)
        ? Math.max(0, Math.min(1, parsed.confidence))
        : null,
    items,
    raw: content,
    usage: body?.usage || {},
    model: aiConfig.model || 'openai/gpt-4o-mini',
  };
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

function ensureBunnyImageStorageConfigured() {
  if (
    !config.bunnyStorageZone ||
    !config.bunnyStorageAccessKey ||
    !config.bunnyCdnBaseUrl
  ) {
    throw createHttpError(
      503,
      'Bunny image storage is not configured yet. Set BUNNY_STORAGE_ZONE, BUNNY_STORAGE_ACCESS_KEY, and BUNNY_CDN_BASE_URL on the backend.',
    );
  }
}

function parseImageDataUrlForUpload(value) {
  const text = normalizeOptionalText(value);
  if (!text) {
    throw createHttpError(400, 'An image is required');
  }

  const match = text.match(
    /^data:(image\/(?:png|jpe?g|webp|gif));base64,([A-Za-z0-9+/=\s]+)$/i,
  );
  if (!match) {
    throw createHttpError(
      400,
      'Use a base64 PNG, JPG, WebP, or GIF image data URL',
    );
  }

  const mimeType =
    match[1].toLowerCase() === 'image/jpg'
      ? 'image/jpeg'
      : match[1].toLowerCase();
  const base64 = match[2].replace(/\s/g, '');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(base64)) {
    throw createHttpError(400, 'The image data is not valid base64');
  }

  const bytes = Buffer.from(base64, 'base64');
  if (bytes.length === 0) {
    throw createHttpError(400, 'The image is empty');
  }
  if (bytes.length > config.bunnyMaxImageBytes) {
    const limitMb = Math.max(
      1,
      Math.floor(config.bunnyMaxImageBytes / 1024 / 1024),
    );
    throw createHttpError(
      413,
      `The image is too large. Use an image below ${limitMb} MB.`,
    );
  }

  return {
    bytes,
    mimeType,
    extension: extensionForImageMimeType(mimeType),
  };
}

function extensionForImageMimeType(mimeType) {
  switch (String(mimeType || '').toLowerCase()) {
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    default:
      return 'jpg';
  }
}

function sanitizeStoragePathSegment(value, fallback = 'item') {
  const text = normalizeOptionalText(value) || fallback;
  const safe = text
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 96);
  return safe || fallback;
}

function joinStoragePath(segments) {
  return segments
    .map((segment) => normalizeOptionalText(segment))
    .filter(Boolean)
    .map((segment) => String(segment).replace(/^\/+|\/+$/g, ''))
    .filter(Boolean)
    .join('/');
}

function encodeStoragePath(pathValue) {
  return String(pathValue || '')
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}

function bunnyPublicUrlForPath(storagePath) {
  return `${config.bunnyCdnBaseUrl}/${encodeStoragePath(storagePath)}`;
}

async function uploadProductImageToBunny({
  fetchImpl,
  businessContext,
  branchId,
  productId,
  productName,
  image,
}) {
  ensureBunnyImageStorageConfigured();

  const uploadRoot = joinStoragePath([config.bunnyUploadPath]);
  const cleanBusinessId = sanitizeStoragePathSegment(
    businessContext.businessId,
    'business',
  );
  const cleanBranchId = sanitizeStoragePathSegment(branchId, 'shared');
  const cleanProductLabel = sanitizeStoragePathSegment(
    productId || productName,
    'product',
  );
  const fileName = `${Date.now()}-${crypto.randomUUID()}-${cleanProductLabel}.${image.extension}`;
  const storagePath = joinStoragePath([
    uploadRoot,
    cleanBusinessId,
    cleanBranchId,
    fileName,
  ]);
  const uploadUrl =
    `${config.bunnyStorageEndpoint}/${encodeURIComponent(config.bunnyStorageZone)}/${encodeStoragePath(storagePath)}`;

  const response = await fetchImpl(uploadUrl, {
    method: 'PUT',
    headers: {
      AccessKey: config.bunnyStorageAccessKey,
      'Content-Type': 'application/octet-stream',
    },
    body: image.bytes,
  });

  if (!response.ok) {
    let responseText = '';
    try {
      responseText = await response.text();
    } catch (_) {
      responseText = '';
    }
    console.error('Bunny product image upload failed', {
      status: response.status,
      body: responseText.slice(0, 500),
    });
    throw createHttpError(
      502,
      'Could not upload the product image to Bunny. Check the backend Bunny Storage credentials.',
    );
  }

  return {
    imageUrl: bunnyPublicUrlForPath(storagePath),
    storagePath,
    contentType: image.mimeType,
    size: image.bytes.length,
  };
}

async function uploadStorefrontImageToBunny({
  fetchImpl,
  businessContext,
  kind,
  image,
}) {
  ensureBunnyImageStorageConfigured();

  const cleanKind = normalizeStorefrontImageKind(kind);
  const uploadRoot = joinStoragePath([config.bunnyUploadPath]);
  const cleanBusinessId = sanitizeStoragePathSegment(
    businessContext.businessId,
    'business',
  );
  const fileName = `${Date.now()}-${crypto.randomUUID()}-${cleanKind}.${image.extension}`;
  const storagePath = joinStoragePath([
    uploadRoot,
    cleanBusinessId,
    'storefront',
    fileName,
  ]);
  const uploadUrl =
    `${config.bunnyStorageEndpoint}/${encodeURIComponent(config.bunnyStorageZone)}/${encodeStoragePath(storagePath)}`;

  const response = await fetchImpl(uploadUrl, {
    method: 'PUT',
    headers: {
      AccessKey: config.bunnyStorageAccessKey,
      'Content-Type': 'application/octet-stream',
    },
    body: image.bytes,
  });

  if (!response.ok) {
    let responseText = '';
    try {
      responseText = await response.text();
    } catch (_) {
      responseText = '';
    }
    console.error('Bunny storefront image upload failed', {
      status: response.status,
      body: responseText.slice(0, 500),
    });
    throw createHttpError(
      502,
      'Could not upload the storefront image to Bunny. Check the backend Bunny Storage credentials.',
    );
  }

  return {
    imageUrl: bunnyPublicUrlForPath(storagePath),
    storagePath,
    contentType: image.mimeType,
    size: image.bytes.length,
    kind: cleanKind,
  };
}

app.post('/api/files/product-images', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.products);
    if (!hasBusinessFeature(businessContext, FEATURE_KEYS.products)) {
      throw createHttpError(403, 'This employee cannot manage products');
    }

    const image = parseImageDataUrlForUpload(req.body?.imageDataUrl);
    const branchId = normalizeOptionalText(
      req.query?.branchId ?? req.body?.branchId ?? req.headers['x-branch-id'],
    );
    const fetch = (await import('node-fetch')).default;
    const result = await uploadProductImageToBunny({
      fetchImpl: fetch,
      businessContext,
      branchId,
      productId: req.body?.productId,
      productName: req.body?.productName,
      image,
    });

    res.status(201).json({
      ok: true,
      data: result,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/files/storefront-images', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);

    const image = parseImageDataUrlForUpload(req.body?.imageDataUrl);
    const fetch = (await import('node-fetch')).default;
    const result = await uploadStorefrontImageToBunny({
      fetchImpl: fetch,
      businessContext,
      kind: req.body?.kind,
      image,
    });

    res.status(201).json({
      ok: true,
      data: result,
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

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

app.post('/api/ai/order-image/analyze', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }

    const imageDataUrl = normalizeOptionalText(req.body?.imageDataUrl);
    if (!imageDataUrl || !imageDataUrl.startsWith('data:image/')) {
      throw createHttpError(400, 'A base64 product or order image is required');
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
    const result = await requestOpenRouterOrderImageAnalysis({
      fetchImpl: fetch,
      aiConfig,
      imageDataUrl,
      note: req.body?.note,
    });

    res.json({
      ok: true,
      data: {
        summary: result.summary,
        intent: result.intent,
        confidence: result.confidence,
        items: result.items,
        raw: result.raw,
      },
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
      branchId: req.query?.branchId,
    });
    res.json({ ok: true, data: catalog });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/public/catalog', async (req, res, next) => {
  try {
    const subdomain = extractCatalogSubdomain(
      req.get('x-forwarded-host') || req.get('host'),
      config.publicCatalogRootDomain,
    );
    if (!subdomain) {
      throw createHttpError(400, 'Catalog subdomain is required');
    }
    const businessId = await findBusinessIdByCatalogSubdomain(query, subdomain);
    if (!businessId) {
      throw createHttpError(404, 'Catalog not found');
    }

    const catalog = await loadPublicCatalog(businessId, {
      currencyOverride: req.query?.currency,
      branchId: req.query?.branchId,
    });
    res.json({ ok: true, data: catalog });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/catalog/storefront', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const publicSubdomain = await ensureBusinessCatalogSubdomain(query, {
      businessId: businessContext.businessId,
      businessName: businessContext.businessName,
    });
    const url = buildCatalogStorefrontUrl(
      config.publicCatalogRootDomain,
      publicSubdomain,
    );
    const legacyBaseUrl =
      config.publicBaseUrl ||
      `https://${config.publicCatalogRootDomain}`;

    res.json({
      ok: true,
      data: {
        businessId: businessContext.businessId,
        subdomain: publicSubdomain,
        url,
        legacyUrl: `${legacyBaseUrl}/catalog/${encodeURIComponent(
          businessContext.businessId,
        )}`,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/catalog/brand', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const brand = await loadStorefrontBrand(businessContext.businessId);
    res.json({ ok: true, data: brand });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/catalog/brand', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const brand = await saveStorefrontBrand(
      businessContext.businessId,
      req.body || {},
    );
    await invalidateCatalogCache(businessContext.businessId);
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'catalog_brand',
      tables: ['businesses'],
    });
    res.json({ ok: true, data: brand });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/catalog/orders', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const scope = resolveDataScope(businessContext, req.query?.branchId);
    const status = normalizeCatalogOrderStatus(req.query?.status, {
      allowAll: true,
      fallback: 'pending',
    });
    const orders = await listPublicCatalogOrders(businessContext.businessId, {
      status,
      branchIds: scope.branchIds,
    });
    res.json({ ok: true, data: orders });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/catalog/orders/:orderId/status', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const scope = resolveDataScope(businessContext, req.query?.branchId);
    const orderId = normalizeOptionalText(req.params.orderId);
    const status = normalizeCatalogOrderStatus(req.body?.status);
    if (!orderId) {
      throw createHttpError(400, 'Order id is required');
    }
    const order = await updatePublicCatalogOrderStatus({
      businessId: businessContext.businessId,
      orderId,
      status,
      branchIds: scope.branchIds,
    });
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'catalog_order',
      tables: ['public_catalog_orders'],
    });
    res.json({ ok: true, data: order });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/catalog/orders/:orderId/payment-request', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const scope = resolveDataScope(businessContext, req.query?.branchId);
    const orderId = normalizeOptionalText(req.params.orderId);
    if (!orderId) {
      throw createHttpError(400, 'Order id is required');
    }
    await assertCatalogOrderScope({
      businessId: businessContext.businessId,
      orderId,
      branchIds: scope.branchIds,
    });
    const result = await requestPublicCatalogOrderPayment({
      businessContext,
      orderId,
      channel: req.body?.channel,
      recipient: req.body?.recipient,
      body: req.body?.body || req.body?.message,
      userId: businessContext.userId,
      sendViaApi: req.body?.sendViaApi === true || req.body?.send_via_api === true,
    });
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'catalog_order',
      tables: ['public_catalog_orders'],
    });
    res.json({ ok: true, data: result });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/public/catalog/:businessId/orders', publicWriteRateLimit, async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.params.businessId);
    if (!businessId) {
      throw createHttpError(400, 'Business catalog link is invalid');
    }

    const order = await createPublicCatalogOrder(businessId, req.body || {});
    notifyBusinessRealtimeChange({
      businessId,
      reason: 'catalog_order',
      tables: ['public_catalog_orders'],
    });
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

app.post('/api/public/demo-requests', publicWriteRateLimit, async (req, res, next) => {
  try {
    const request = await createLandingDemoRequest(req.body || {}, req);
    res.status(201).json({ ok: true, data: request });
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
      branchId: req.query?.branchId,
    });
    res
      .status(200)
      .type('html')
      .send(renderPublicCatalogPage(catalog));
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get(['/', '/catalog'], async (req, res, next) => {
  try {
    const subdomain = extractCatalogSubdomain(
      req.get('x-forwarded-host') || req.get('host'),
      config.publicCatalogRootDomain,
    );
    if (!subdomain) {
      next();
      return;
    }

    const businessId = await findBusinessIdByCatalogSubdomain(query, subdomain);
    if (!businessId) {
      throw createHttpError(404, 'Catalog not found');
    }

    const catalog = await loadPublicCatalog(businessId, {
      currencyOverride: req.query?.currency,
      branchId: req.query?.branchId,
    });
    res
      .status(200)
      .type('html')
      .send(renderPublicCatalogPage(catalog));
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.use(express.static(landingPageDir, { index: false }));
app.use('/landing', express.static(landingPageDir, { index: false }));

app.get(['/', '/landing'], (req, res, next) => {
  res.sendFile(landingIndexPath, (error) => {
    if (error) {
      next(error);
    }
  });
});

app.use((error, req, res, next) => {

  const statusCode =
    error && Number.isInteger(error.statusCode) ? error.statusCode : 500;
  const exposeMessage =
    statusCode < 500 ||
    error?.exposeMessage === true ||
    config.nodeEnv !== 'production';

  res.status(statusCode).json({
    ok: false,
    error: exposeMessage
      ? error.message || 'Unexpected server error'
      : 'Unexpected server error',
  });
});

server.listen(config.port, () => {
  console.log(
    `Piki POS sync backend listening on port ${config.port} (${config.nodeEnv})`,
  );
});

Promise.all([
  ensureSubscriptionSchema(),
  initializeCatalogSubdomainSchema(query),
  ensureDeviceUserSchema(),
  ensureEmailOtpSchema(),
  ensureEtimsSchema(),
  ensureLandingDemoRequestSchema(),
  ensureSyncStockEffectSchema(),
  ensureStorefrontBrandSchema(),
])
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

function realtimeBusinessRoom(businessId) {
  return `business:${normalizeCacheKeyPart(businessId)}`;
}

function changedTablesFromPushSummary(summary) {
  return syncTables
    .map((table) => table.name)
    .filter((tableName) => Number(summary?.applied?.[tableName] || 0) > 0);
}

function notifyBusinessRealtimeChange({
  businessId,
  sourceDeviceId = null,
  reason = 'sync',
  tables = [],
}) {
  const cleanBusinessId = normalizeOptionalText(businessId);
  if (!cleanBusinessId) {
    return;
  }

  const cleanTables = Array.isArray(tables)
    ? [
        ...new Set(
          tables.map((table) => normalizeOptionalText(table)).filter(Boolean),
        ),
      ]
    : [];

  io.to(realtimeBusinessRoom(cleanBusinessId)).emit('sync:changed', {
    type: 'sync_changed',
    businessId: cleanBusinessId,
    sourceDeviceId: normalizeOptionalText(sourceDeviceId),
    reason: normalizeOptionalText(reason) || 'sync',
    tables: cleanTables,
    serverTime: new Date().toISOString(),
  });
}

function buildCorsOptions() {
  const allowedOrigins = new Set(
    (config.allowedOrigins || []).map((origin) =>
      String(origin || '').trim().replace(/\/+$/, ''),
    ),
  );
  return {
    origin(origin, callback) {
      // Allow requests with no Origin header (mobile apps, server-to-server).
      // Reject explicit null origins to reduce CSRF surface from file:// or redirects.
      if (origin === undefined) {
        callback(null, true);
        return;
      }
      const normalizedOrigin = String(origin).trim().replace(/\/+$/, '');
      if (allowedOrigins.has(normalizedOrigin)) {
        callback(null, true);
        return;
      }
      callback(createHttpError(403, 'Origin is not allowed'));
    },
  };
}

function applySecurityHeaders(req, res, next) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader(
    'Permissions-Policy',
    'camera=(), microphone=(), geolocation=(), payment=()',
  );
  next();
}

function createRateLimiter({ windowMs, max, keyPrefix }) {
  const buckets = new Map();
  return (req, res, next) => {
    const now = Date.now();
    const identifier = [
      keyPrefix,
      req.ip || req.socket?.remoteAddress || 'unknown',
      normalizeOptionalText(req.body?.email) || normalizeOptionalText(req.params?.businessId) || '',
    ].join(':');
    const existing = buckets.get(identifier);
    const bucket =
      existing && existing.resetAt > now
        ? existing
        : { count: 0, resetAt: now + windowMs };
    bucket.count += 1;
    buckets.set(identifier, bucket);

    if (bucket.count > max) {
      res.setHeader('Retry-After', String(Math.ceil((bucket.resetAt - now) / 1000)));
      next(createHttpError(429, 'Too many requests. Please try again later.'));
      return;
    }

    if (buckets.size > 10000) {
      for (const [key, value] of buckets.entries()) {
        if (value.resetAt <= now) {
          buckets.delete(key);
        }
      }
    }
    next();
  };
}

function validateMpesaCallbackSecret(req) {
  if (!config.mpesaCallbackSecret) {
    return;
  }
  const provided =
    normalizeOptionalText(req.query?.secret) ||
    normalizeOptionalText(req.headers['x-mpesa-callback-secret']);
  if (!safeEquals(provided, config.mpesaCallbackSecret)) {
    throw createHttpError(401, 'Invalid M-Pesa callback secret');
  }
}

function safeEquals(left, right) {
  const leftValue = String(left || '');
  const rightValue = String(right || '');
  const length = Math.max(leftValue.length, rightValue.length);
  const leftBuffer = Buffer.alloc(length);
  const rightBuffer = Buffer.alloc(length);
  Buffer.from(leftValue).copy(leftBuffer);
  Buffer.from(rightValue).copy(rightBuffer);
  return (
    crypto.timingSafeEqual(leftBuffer, rightBuffer) &&
    leftValue.length === rightValue.length
  );
}

async function deleteBusinessRoute(req, res, next) {
  try {
    const businessContext = await requireBusinessContext(req, {
      allowExpired: true,
      allowReadOnlyExpired: true,
    });
    requireAdmin(businessContext);

    const confirmBusinessName = normalizeOptionalText(
      req.body?.confirmBusinessName ?? req.body?.businessName,
    );
    if (
      normalizeDeletionConfirmation(confirmBusinessName) !==
      normalizeDeletionConfirmation(businessContext.businessName)
    ) {
      throw createHttpError(
        400,
        'Type the business name exactly to confirm business deletion.',
      );
    }

    const deleted = await withTransaction((client) =>
      deleteBusinessAccount(client, {
        businessId: businessContext.businessId,
        deletedByUserId: businessContext.userId,
      }),
    );
    if (!deleted) {
      throw createHttpError(404, 'Business not found');
    }
    await invalidateCatalogCache(businessContext.businessId);

    res.json({
      ok: true,
      data: {
        businessId: deleted.businessId,
        businessName: deleted.businessName,
        deleted: deleted.deleted,
        releasedSubdomain: deleted.releasedSubdomain,
        deletedAt: deleted.deletedAt,
        subdomainReleasedAt: deleted.subdomainReleasedAt,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
}

async function requireBusinessContext(
  req,
  { allowExpired = false, allowReadOnlyExpired = false } = {}
) {
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
  if (!businessContext.userId) {
    const claimedUserId = normalizeOptionalText(
      req.query?.userId ?? req.body?.userId,
    );
    const userCount = await query(
      `SELECT COUNT(*)::int AS count
       FROM users
       WHERE business_id = $1 AND deleted_at IS NULL`,
      [businessContext.businessId],
    );
    if (Number(userCount.rows[0]?.count || 0) === 0 && claimedUserId) {
      businessContext.userId = claimedUserId;
      businessContext.userName = 'Business owner';
      businessContext.userRole = 'ADMIN';
      businessContext.featureAccessJson = null;
      businessContext.allowedBranchIdsJson = null;
      businessContext.bootstrapUser = true;
    } else {
      throw createHttpError(
        401,
        'This device is not linked to a signed-in employee. Sign out and sign in again.',
      );
    }
  }
  const readOnlyExpiredAllowed =
    allowReadOnlyExpired && businessContext.subscriptionStatus === 'expired';
  if (!businessContext.usable && !allowExpired && !readOnlyExpiredAllowed) {
    throw createHttpError(
      402,
      'Subscription expired. Renew the business subscription to continue syncing.',
    );
  }

  const authenticatedContext = {
    ...businessContext,
    role: normalizeBusinessRole(businessContext.userRole),
    featureAccess: resolveBusinessFeatureAccess(
      businessContext.userRole,
      businessContext.featureAccessJson,
    ),
    allowedBranchIds: parseJsonStringList(
      businessContext.allowedBranchIdsJson,
    ),
  };
  const requestedBranchId = normalizeOptionalText(
    req.query?.branchId ?? req.body?.branchId ?? req.headers['x-branch-id'],
  );
  if (
    requestedBranchId &&
    authenticatedContext.role !== 'ADMIN' &&
    authenticatedContext.allowedBranchIds.length > 0 &&
    !authenticatedContext.allowedBranchIds.includes(requestedBranchId)
  ) {
    throw createHttpError(403, 'This employee cannot access the selected branch');
  }
  return authenticatedContext;
}

function resolveBusinessFeatureAccess(roleValue, rawFeatures) {
  const role = normalizeBusinessRole(roleValue);
  if (role === 'ADMIN') {
    return ['*'];
  }
  const configured = parseJsonStringList(rawFeatures);
  if (normalizeOptionalText(rawFeatures)) {
    return configured;
  }
  if (role === 'MANAGER') {
    return ['*'];
  }
  return ['pos', 'sales', 'dashboard', 'kopesha', 'settings', 'shifts', 'agent'];
}

function normalizeBusinessRole(value) {
  const role = String(value || '').trim().toUpperCase();
  return role === 'ADMIN' || role === 'MANAGER' ? role : 'CASHIER';
}

function parseJsonStringList(value) {
  if (Array.isArray(value)) {
    return [...new Set(value.map(normalizeOptionalText).filter(Boolean))];
  }
  const raw = normalizeOptionalText(value);
  if (!raw) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed)
      ? [...new Set(parsed.map(normalizeOptionalText).filter(Boolean))]
      : [];
  } catch (_) {
    return [];
  }
}

function requireAdmin(businessContext) {
  if (businessContext.role !== 'ADMIN') {
    throw createHttpError(403, 'Administrator access is required');
  }
}

function requireManagerOrAdmin(businessContext) {
  if (businessContext.role !== 'ADMIN' && businessContext.role !== 'MANAGER') {
    throw createHttpError(403, 'Manager or administrator access is required');
  }
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
        if (price.provider === 'mpesa' || price.provider === 'google_pay') {
          continue;
        }
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
            store_product_id,
            is_active,
            created_at,
            updated_at
          )
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW())
          `,
          [
            price.id,
            plan.code,
            price.countryCode,
            price.currency,
            price.amountMinor,
            price.billingPeriod,
            price.provider,
            price.storeProductId,
            price.isActive,
          ],
        );
      }
    }

    const plans = await listPlans({ includeInactive: true }, client);
    return plans.find((item) => item.code === plan.code);
  });
}

async function loadSubscriptionOverview(
  businessId,
  planCode,
  countryCode,
  sellingMode,
  platform,
) {
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
  const effectiveCountryCode = normalizeCountryCode(countryCode || 'KE');
  const markets = subscriptionMarketsForPlatform(
    await listPublicMarkets(),
    platform,
    effectiveCountryCode,
  );
  const selectedMarket = selectSubscriptionMarket(markets, { countryCode });
  const plans = selectedMarket
    ? await listPublicPlans({ countryCode: effectiveCountryCode })
    : [];
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
    platform: normalizeSubscriptionPlatform(platform),
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
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'pending', $11, $12, $13, $13)
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
  if (!isPlausibleMpesaPasskey(mpesaConfig.passkey)) {
    throw createHttpError(
      400,
      'M-Pesa passkey looks invalid. Use the Lipa na M-Pesa Online passkey for this shortcode, not your Daraja login password or a certificate key.',
    );
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
    const darajaMessage = mpesaProviderMessage(body);
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
      darajaMessage
        ? `M-Pesa checkout failed: ${darajaMessage}`
        : 'M-Pesa checkout failed',
      { exposeMessage: true },
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
    const darajaMessage = mpesaProviderMessage(body);
    throw createHttpError(
      response.ok ? 502 : response.status,
      darajaMessage
        ? `M-Pesa auth failed: ${darajaMessage}`
        : `M-Pesa auth failed (HTTP ${response.status}). Check the Daraja Consumer Key and Consumer Secret for the selected sandbox/production base URL.`,
      { exposeMessage: true },
    );
  }
  return body.access_token;
}

function mpesaProviderMessage(body = {}) {
  return normalizeOptionalText(
    body.errorMessage ||
      body.ResponseDescription ||
      body.error_description ||
      body.error ||
      body.message ||
      body.ResultDesc,
  );
}

async function processGooglePlayConfirmation({
  businessId,
  paymentId,
  productId,
  purchaseToken,
}) {
  const paymentResult = await query(
    `
    SELECT p.*, price.store_product_id
    FROM subscription_payments p
    LEFT JOIN subscription_plan_prices price ON price.id = p.price_id
    WHERE p.id = $1 AND p.business_id = $2
    LIMIT 1
    `,
    [paymentId, businessId],
  );
  const payment = paymentResult.rows[0];
  if (!payment) {
    throw createHttpError(404, 'Subscription payment was not found');
  }
  if (payment.provider !== 'google_play') {
    throw createHttpError(400, 'Payment is not a Google Play checkout');
  }
  if (payment.status === 'paid' && payment.completed_at) {
    return { status: 'paid', activated: true };
  }
  if (!payment.store_product_id || payment.store_product_id !== productId) {
    throw createHttpError(400, 'Google Play product does not match this plan');
  }

  const reused = await query(
    `
    SELECT id
    FROM subscription_payments
    WHERE provider = 'google_play'
      AND provider_reference = $1
      AND id <> $2
    LIMIT 1
    `,
    [purchaseToken, paymentId],
  );
  if (reused.rows.length > 0) {
    throw createHttpError(409, 'This Google Play purchase was already used');
  }

  const gateway = await loadPaymentGateway('google_play');
  if (!gateway?.isActive) {
    throw createHttpError(400, 'Google Play Billing is not active');
  }
  const googleConfig = resolveGooglePlayGatewayConfig(gateway);
  const verification = await verifyGooglePlaySubscription({
    productId,
    purchaseToken,
    googleConfig,
  });

  await acknowledgeGooglePlaySubscription({
    productId,
    purchaseToken,
    googleConfig,
    verification,
  });

  await withTransaction(async (client) => {
    await client.query(
      `
      UPDATE subscription_payments
      SET provider_reference = $2,
          metadata_json = metadata_json || $3::jsonb,
          updated_at = NOW()
      WHERE id = $1
      `,
      [paymentId, purchaseToken, JSON.stringify({ googlePlay: verification })],
    );
    await activateSubscriptionFromPayment(client, paymentId);
  });
  return { status: 'paid', activated: true };
}

async function verifyGooglePlaySubscription({
  productId,
  purchaseToken,
  googleConfig,
}) {
  const accessToken = await getGooglePlayAccessToken(googleConfig);
  const fetch = (await import('node-fetch')).default;
  const url = `${googleConfig.apiBaseUrl}/${encodeURIComponent(
    googleConfig.packageName,
  )}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(response.status, body.error?.message || 'Google Play verification failed');
  }
  const validStates = new Set([
    'SUBSCRIPTION_STATE_ACTIVE',
    'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  ]);
  const productMatches = (body.lineItems || []).some(
    (item) => item.productId === productId,
  );
  if (!validStates.has(body.subscriptionState) || !productMatches) {
    throw createHttpError(400, 'Google Play subscription is not active for this product');
  }
  return body;
}

async function getGooglePlayAccessToken(googleConfig) {
  const assertion = jwt.sign(
    {
      iss: googleConfig.serviceAccountEmail,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
    },
    googleConfig.serviceAccountPrivateKey,
    { algorithm: 'RS256', expiresIn: '1h' },
  );
  const fetch = (await import('node-fetch')).default;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const body = await readMaybeJson(response);
  if (!response.ok || !body.access_token) {
    throw createHttpError(502, body.error_description || 'Google Play authentication failed');
  }
  return body.access_token;
}

async function acknowledgeGooglePlaySubscription({
  productId,
  purchaseToken,
  googleConfig,
  verification,
}) {
  if (verification.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED') {
    return;
  }
  const accessToken = await getGooglePlayAccessToken(googleConfig);
  const fetch = (await import('node-fetch')).default;
  const url = `${googleConfig.apiBaseUrl}/${encodeURIComponent(
    googleConfig.packageName,
  )}/purchases/subscriptions/${encodeURIComponent(
    productId,
  )}/tokens/${encodeURIComponent(purchaseToken)}:acknowledge`;
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: '{}',
  });
  if (!response.ok) {
    const body = await readMaybeJson(response);
    throw createHttpError(502, body.error?.message || 'Google Play acknowledgement failed');
  }
}

async function initiatePayPalCheckout(payment, gateway) {
  assertPublicPaymentReturnUrl();
  const paypalConfig = resolvePayPalGatewayConfig(gateway);
  const accessToken = await getPayPalAccessToken(paypalConfig);
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(`${paypalConfig.baseUrl}/v2/checkout/orders`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      'PayPal-Request-Id': payment.id,
    },
    body: JSON.stringify({
      intent: 'CAPTURE',
      purchase_units: [
        {
          reference_id: payment.externalReference,
          custom_id: payment.id,
          description: `Piki ${payment.planCode} subscription`,
          amount: {
            currency_code: payment.currency,
            value: minorAmountToMajor(payment.amountMinor),
          },
        },
      ],
      application_context: {
        brand_name: 'Piki POS',
        user_action: 'PAY_NOW',
        return_url: `${config.publicBaseUrl}/api/subscription/paypal/return?paymentId=${encodeURIComponent(payment.id)}`,
        cancel_url: `${config.publicBaseUrl}/api/subscription/paypal/cancel?paymentId=${encodeURIComponent(payment.id)}`,
      },
    }),
  });
  const body = await readMaybeJson(response);
  const checkoutUrl = (body.links || []).find((link) => link.rel === 'approve')?.href;
  if (!response.ok || !body.id || !checkoutUrl) {
    await markSubscriptionPaymentStatus(payment.id, 'failed', body);
    throw createHttpError(502, body.message || 'PayPal checkout could not be created');
  }
  await setSubscriptionProviderReference(payment.id, body.id, { paypalOrder: body });
  return { checkoutUrl, message: 'Continue in PayPal to complete payment.' };
}

async function getPayPalAccessToken(paypalConfig) {
  const fetch = (await import('node-fetch')).default;
  const credentials = Buffer.from(
    `${paypalConfig.clientId}:${paypalConfig.clientSecret}`,
  ).toString('base64');
  const response = await fetch(`${paypalConfig.baseUrl}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${credentials}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });
  const body = await readMaybeJson(response);
  if (!response.ok || !body.access_token) {
    throw createHttpError(502, body.error_description || 'PayPal authentication failed');
  }
  return body.access_token;
}

async function processPayPalReturn({ paymentId, orderId }) {
  const payment = await loadSubscriptionPaymentById(paymentId);
  if (!payment || payment.provider !== 'paypal') {
    throw createHttpError(404, 'PayPal payment was not found');
  }
  if (payment.status === 'paid') return;
  if (payment.providerReference !== orderId) {
    throw createHttpError(400, 'PayPal order does not match this payment');
  }
  const gateway = await loadPaymentGateway('paypal');
  const paypalConfig = resolvePayPalGatewayConfig(gateway);
  const accessToken = await getPayPalAccessToken(paypalConfig);
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(
    `${paypalConfig.baseUrl}/v2/checkout/orders/${encodeURIComponent(orderId)}/capture`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    },
  );
  const body = await readMaybeJson(response);
  const capture = body.purchase_units?.[0]?.payments?.captures?.[0];
  if (
    !response.ok ||
    body.status !== 'COMPLETED' ||
    capture?.status !== 'COMPLETED' ||
    capture.amount?.currency_code !== payment.currency ||
    majorAmountToMinor(capture.amount?.value) !== payment.amountMinor
  ) {
    throw createHttpError(400, body.message || 'PayPal payment details did not match');
  }
  await completeHostedSubscriptionPayment(paymentId, { paypalCapture: body });
}

async function initiateFlutterwaveCheckout(payment, gateway) {
  assertPublicPaymentReturnUrl();
  const flutterwaveConfig = resolveFlutterwaveGatewayConfig(gateway);
  const customer = await loadSubscriptionCustomer(payment.businessId);
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(`${flutterwaveConfig.baseUrl}/payments`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${flutterwaveConfig.secretKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      tx_ref: payment.externalReference,
      amount: Number(minorAmountToMajor(payment.amountMinor)),
      currency: payment.currency,
      redirect_url: `${config.publicBaseUrl}/api/subscription/flutterwave/return?paymentId=${encodeURIComponent(payment.id)}`,
      customer,
      meta: { paymentId: payment.id, planCode: payment.planCode },
      customizations: {
        title: 'Piki POS Subscription',
        description: `${payment.planCode} subscription`,
      },
    }),
  });
  const body = await readMaybeJson(response);
  const checkoutUrl = body.data?.link;
  if (!response.ok || body.status !== 'success' || !checkoutUrl) {
    await markSubscriptionPaymentStatus(payment.id, 'failed', body);
    throw createHttpError(502, body.message || 'Flutterwave checkout could not be created');
  }
  await setSubscriptionProviderReference(payment.id, payment.externalReference, {
    flutterwaveCheckout: body,
  });
  return { checkoutUrl, message: 'Continue in Flutterwave to complete payment.' };
}

async function processFlutterwaveReturn({
  paymentId,
  transactionId,
  transactionReference,
}) {
  const payment = await loadSubscriptionPaymentById(paymentId);
  if (!payment || payment.provider !== 'flutterwave') {
    throw createHttpError(404, 'Flutterwave payment was not found');
  }
  if (payment.status === 'paid') return;
  if (payment.providerReference !== transactionReference) {
    throw createHttpError(400, 'Flutterwave reference does not match this payment');
  }
  const gateway = await loadPaymentGateway('flutterwave');
  const flutterwaveConfig = resolveFlutterwaveGatewayConfig(gateway);
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(
    `${flutterwaveConfig.baseUrl}/transactions/${encodeURIComponent(transactionId)}/verify`,
    { headers: { Authorization: `Bearer ${flutterwaveConfig.secretKey}` } },
  );
  const body = await readMaybeJson(response);
  const data = body.data || {};
  if (
    !response.ok ||
    body.status !== 'success' ||
    data.status !== 'successful' ||
    data.tx_ref !== payment.providerReference ||
    data.currency !== payment.currency ||
    majorAmountToMinor(data.amount) !== payment.amountMinor
  ) {
    throw createHttpError(400, body.message || 'Flutterwave payment details did not match');
  }
  await completeHostedSubscriptionPayment(paymentId, {
    flutterwaveVerification: body,
  });
}

async function loadSubscriptionPaymentById(paymentId) {
  const result = await query(
    'SELECT * FROM subscription_payments WHERE id = $1 LIMIT 1',
    [paymentId],
  );
  return result.rows[0]
    ? {
        ...normalizePaymentRow(result.rows[0]),
        providerReference: result.rows[0].provider_reference,
      }
    : null;
}

async function loadSubscriptionCustomer(businessId) {
  const result = await query(
    `
    SELECT name, email, phone
    FROM users
    WHERE business_id = $1 AND role = 'ADMIN' AND deleted_at IS NULL
    ORDER BY created_at ASC
    LIMIT 1
    `,
    [businessId],
  );
  const user = result.rows[0] || {};
  return {
    name: user.name || 'Piki customer',
    email: user.email || 'customer@pikipos.com',
    phonenumber: user.phone || undefined,
  };
}

async function setSubscriptionProviderReference(paymentId, reference, metadata) {
  await query(
    `
    UPDATE subscription_payments
    SET provider_reference = $2,
        metadata_json = metadata_json || $3::jsonb,
        updated_at = NOW()
    WHERE id = $1
    `,
    [paymentId, reference, JSON.stringify(metadata || {})],
  );
}

async function markSubscriptionPaymentStatus(paymentId, status, metadata) {
  await query(
    `
    UPDATE subscription_payments
    SET status = $2,
        metadata_json = metadata_json || $3::jsonb,
        updated_at = NOW()
    WHERE id = $1 AND status <> 'paid'
    `,
    [paymentId, status, JSON.stringify(metadata || {})],
  );
}

async function completeHostedSubscriptionPayment(paymentId, metadata) {
  await withTransaction(async (client) => {
    await client.query(
      `
      UPDATE subscription_payments
      SET metadata_json = metadata_json || $2::jsonb,
          updated_at = NOW()
      WHERE id = $1
      `,
      [paymentId, JSON.stringify(metadata || {})],
    );
    await activateSubscriptionFromPayment(client, paymentId);
  });
}

function minorAmountToMajor(amountMinor) {
  return (Number(amountMinor || 0) / 100).toFixed(2);
}

function majorAmountToMinor(amount) {
  return Math.round(Number(amount || 0) * 100);
}

function assertPublicPaymentReturnUrl() {
  if (!isHttpsUrl(config.publicBaseUrl)) {
    throw createHttpError(400, 'PUBLIC_BASE_URL must be a public HTTPS URL');
  }
}

function sendPaymentReturnPage(
  res,
  { statusCode = 200, title, message },
) {
  res.status(statusCode).type('html').send(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title></head>
<body style="font-family:system-ui,sans-serif;background:#10050d;color:#fff;display:grid;place-items:center;min-height:100vh;margin:0"><main style="max-width:520px;padding:32px;text-align:center"><h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p></main></body></html>`);
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

async function ensureSyncStockEffectSchema(target = query) {
  await runDbQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS sync_stock_effects (
      sale_item_id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      product_id text NOT NULL,
      variant_id text,
      stock_delta double precision NOT NULL DEFAULT 0,
      applied_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_sync_stock_effects_business
     ON sync_stock_effects(business_id, applied_at DESC)`,
  );
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS sync_credit_payment_effects (
       payment_id text PRIMARY KEY,
       business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
       sale_id text NOT NULL,
       customer_id text NOT NULL,
       amount double precision NOT NULL DEFAULT 0,
       applied_at timestamptz NOT NULL DEFAULT NOW()
     )`,
  );
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS sync_refund_balance_effects (
       refund_sale_id text PRIMARY KEY,
       business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
       original_sale_id text NOT NULL,
       amount double precision NOT NULL DEFAULT 0,
       applied_at timestamptz NOT NULL DEFAULT NOW()
     )`,
  );
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS sync_sale_credit_baselines (
       sale_id text PRIMARY KEY,
       business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
       customer_id text,
       initial_balance_due double precision NOT NULL DEFAULT 0,
       initial_amount_paid double precision NOT NULL DEFAULT 0,
       created_at timestamptz NOT NULL DEFAULT NOW()
     )`,
  );
}

async function ensureStorefrontBrandSchema(target = query) {
  await runDbQuery(
    target,
    'ALTER TABLE businesses ADD COLUMN IF NOT EXISTS catalog_logo_url text',
  );
  await runDbQuery(
    target,
    'ALTER TABLE businesses ADD COLUMN IF NOT EXISTS catalog_cover_url text',
  );
  await runDbQuery(
    target,
    'ALTER TABLE businesses ADD COLUMN IF NOT EXISTS catalog_primary_color text',
  );
  await runDbQuery(
    target,
    'ALTER TABLE businesses ADD COLUMN IF NOT EXISTS catalog_tagline text',
  );
  await runDbQuery(
    target,
    'ALTER TABLE businesses ADD COLUMN IF NOT EXISTS catalog_description text',
  );
}

async function loadStorefrontBrand(businessId) {
  await ensureStorefrontBrandSchema(query);
  const result = await query(
    `SELECT
       id,
       name,
       catalog_logo_url,
       catalog_cover_url,
       catalog_primary_color,
       catalog_tagline,
       catalog_description,
       updated_at
     FROM businesses
     WHERE id = $1 AND deleted_at IS NULL
     LIMIT 1`,
    [businessId],
  );
  if (!result.rows.length) {
    throw createHttpError(404, 'Business was not found');
  }
  return normalizeStorefrontBrandRow(result.rows[0]);
}

async function saveStorefrontBrand(businessId, input) {
  await ensureStorefrontBrandSchema(query);
  const logoUrl = normalizeStorefrontImageUrl(
    input.logoUrl ?? input.logo_url,
    'logo URL',
  );
  const coverUrl = normalizeStorefrontImageUrl(
    input.coverUrl ?? input.cover_url,
    'cover photo URL',
  );
  const primaryColor = normalizeStorefrontColor(
    input.primaryColor ?? input.primary_color,
  );
  const tagline = limitText(input.tagline, 80);
  const description = limitText(input.description, 260);

  const result = await query(
    `UPDATE businesses
     SET catalog_logo_url = $2,
         catalog_cover_url = $3,
         catalog_primary_color = $4,
         catalog_tagline = $5,
         catalog_description = $6,
         updated_at = NOW()
     WHERE id = $1 AND deleted_at IS NULL
     RETURNING
       id,
       name,
       catalog_logo_url,
       catalog_cover_url,
       catalog_primary_color,
       catalog_tagline,
       catalog_description,
       updated_at`,
    [businessId, logoUrl, coverUrl, primaryColor, tagline, description],
  );
  if (!result.rows.length) {
    throw createHttpError(404, 'Business was not found');
  }
  return normalizeStorefrontBrandRow(result.rows[0]);
}

function normalizeStorefrontBrandRow(row) {
  return {
    businessId: row.id,
    businessName: normalizeOptionalText(row.name) || 'Store',
    logoUrl: safePublicImageUrl(row.catalog_logo_url),
    coverUrl: safePublicImageUrl(row.catalog_cover_url),
    primaryColor: normalizeStorefrontColor(row.catalog_primary_color, {
      fallback: '#ff2a6d',
      throwOnInvalid: false,
    }),
    tagline: normalizeOptionalText(row.catalog_tagline) || 'Online catalog',
    description:
      normalizeOptionalText(row.catalog_description) ||
      'Shop products, choose variants, and send your order directly to the store. The team will confirm availability and payment before fulfillment.',
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeStorefrontImageUrl(value, label = 'image URL') {
  const clean = normalizeOptionalText(value);
  if (!clean) {
    return null;
  }
  const safe = safePublicImageUrl(clean);
  if (!safe) {
    throw createHttpError(400, `Use a valid http or https ${label}.`);
  }
  if (safe.length > 2048) {
    throw createHttpError(400, `The ${label} is too long.`);
  }
  return safe;
}

function normalizeStorefrontColor(
  value,
  { fallback = '#ff2a6d', throwOnInvalid = true } = {},
) {
  const clean = normalizeOptionalText(value);
  if (!clean) {
    return fallback;
  }
  const withHash = clean.startsWith('#') ? clean : `#${clean}`;
  if (/^#[0-9a-f]{6}$/i.test(withHash)) {
    return withHash.toLowerCase();
  }
  if (throwOnInvalid) {
    throw createHttpError(400, 'Use a valid 6-digit brand color, like #ff2a6d.');
  }
  return fallback;
}

function normalizeStorefrontImageKind(value) {
  const clean = normalizeOptionalText(value)?.toLowerCase();
  if (clean === 'logo' || clean === 'cover') {
    return clean;
  }
  throw createHttpError(400, 'Image kind must be logo or cover.');
}

async function applySaleItemStockEffect(
  client,
  saleItem,
  businessId,
  {
    applyProductStock = true,
    applyVariantStock = true,
    applyBatchStock = true,
  } = {},
) {
  const saleItemId = normalizeOptionalText(saleItem?.id);
  const productId = normalizeOptionalText(saleItem?.product_id);
  const variantId = normalizeOptionalText(saleItem?.variant_id);
  if (!saleItemId || !productId) {
    return null;
  }

  const productResult = await client.query(
    `SELECT id, track_stock, sale_to_stock_factor
     FROM products
     WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL
     LIMIT 1`,
    [businessId, productId],
  );
  const product = productResult.rows[0];
  if (!product || Number(product.track_stock ?? 1) === 0) {
    return null;
  }

  const quantity = Number(saleItem.quantity || 0);
  if (!Number.isFinite(quantity) || Math.abs(quantity) < 0.000001) {
    return null;
  }
  const factor = Number(product.sale_to_stock_factor || 1);
  const stockDelta = -quantity * (Number.isFinite(factor) && factor > 0 ? factor : 1);
  if (Math.abs(stockDelta) < 0.000001) {
    return null;
  }

  const effectResult = await client.query(
    `INSERT INTO sync_stock_effects (
       sale_item_id, business_id, product_id, variant_id, stock_delta
     )
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (sale_item_id) DO NOTHING
     RETURNING sale_item_id`,
    [saleItemId, businessId, productId, variantId, stockDelta],
  );
  if (effectResult.rowCount === 0) {
    return null;
  }

  let latestRevision = null;
  if (applyProductStock) {
    const productUpdate = await client.query(
      `UPDATE products
       SET stock = COALESCE(stock, 0) + $3,
           updated_at = NOW(),
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $1 AND id = $2
       RETURNING server_revision`,
      [businessId, productId, stockDelta],
    );
    latestRevision = maxCursor(
      latestRevision,
      productUpdate.rows[0]?.server_revision,
    );
  }

  if (variantId && applyVariantStock) {
    const variantUpdate = await client.query(
      `UPDATE product_variants
       SET stock = COALESCE(stock, 0) + $3,
           updated_at = NOW(),
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $1 AND id = $2
       RETURNING server_revision`,
      [businessId, variantId, stockDelta],
    );
    latestRevision = maxCursor(
      latestRevision,
      variantUpdate.rows[0]?.server_revision,
    );
  }

  if (!variantId && applyBatchStock && stockDelta < -0.000001) {
    const saleId = normalizeOptionalText(saleItem.sale_id);
    const saleResult = await client.query(
      `SELECT COALESCE(branch_id, 'main_branch') AS branch_id
       FROM sales
       WHERE business_id = $1 AND id = $2
       LIMIT 1`,
      [businessId, saleId],
    );
    const branchId = normalizeOptionalText(saleResult.rows[0]?.branch_id);
    if (branchId) {
      let remaining = Math.abs(stockDelta);
      const batches = await client.query(
        `SELECT id, quantity_remaining
         FROM stock_batches
         WHERE business_id = $1
           AND product_id = $2
           AND COALESCE(branch_id, 'main_branch') = $3
           AND deleted_at IS NULL
           AND quantity_remaining > 0
         ORDER BY received_at ASC, created_at ASC, id ASC
         FOR UPDATE`,
        [businessId, productId, branchId],
      );
      for (const batch of batches.rows) {
        if (remaining <= 0.000001) break;
        const available = Number(batch.quantity_remaining || 0);
        if (available <= 0) continue;
        const deduction = Math.min(available, remaining);
        const batchUpdate = await client.query(
          `UPDATE stock_batches
           SET quantity_remaining = GREATEST(0, COALESCE(quantity_remaining, 0) - $3),
               finished_at = CASE
                 WHEN COALESCE(quantity_remaining, 0) - $3 <= 0 THEN NOW()
                 ELSE NULL
               END,
               updated_at = NOW(),
               sync_status = 'synced',
               server_revision = nextval('sync_revision_seq')
           WHERE business_id = $1 AND id = $2
           RETURNING server_revision`,
          [businessId, batch.id, deduction],
        );
        latestRevision = maxCursor(
          latestRevision,
          batchUpdate.rows[0]?.server_revision,
        );
        remaining -= deduction;
      }
    }
  }

  return latestRevision;
}

async function applyCreditPaymentEffect(client, payment, businessId) {
  const paymentId = normalizeOptionalText(payment.id);
  const saleId = normalizeOptionalText(payment.sale_id);
  const customerId = normalizeOptionalText(payment.customer_id);
  const amount = Number(payment.amount || 0);
  if (!paymentId || !saleId || !customerId || !Number.isFinite(amount) || amount <= 0) {
    return null;
  }
  const effect = await client.query(
    `INSERT INTO sync_credit_payment_effects (
       payment_id, business_id, sale_id, customer_id, amount
     ) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (payment_id) DO NOTHING
     RETURNING payment_id`,
    [paymentId, businessId, saleId, customerId, amount],
  );
  if (effect.rowCount === 0) return null;
  return null;
}

async function applyRefundBalanceEffect(client, refundSale, businessId) {
  const refundId = normalizeOptionalText(refundSale.id);
  const originalSaleId = normalizeOptionalText(refundSale.refund_for_sale_id);
  const amount = Math.abs(Number(refundSale.total_amount || 0));
  if (!refundId || !originalSaleId || !Number.isFinite(amount) || amount <= 0) {
    return null;
  }
  const effect = await client.query(
    `INSERT INTO sync_refund_balance_effects (
       refund_sale_id, business_id, original_sale_id, amount
     ) VALUES ($1, $2, $3, $4)
     ON CONFLICT (refund_sale_id) DO NOTHING
     RETURNING refund_sale_id`,
    [refundId, businessId, originalSaleId, amount],
  );
  if (effect.rowCount === 0) return null;

  const updated = await client.query(
    `UPDATE sales
     SET refund_sale_id = COALESCE(refund_sale_id, $3),
         refunded_at = COALESCE(refunded_at, NOW()),
         updated_at = NOW(),
         sync_status = 'synced',
         server_revision = nextval('sync_revision_seq')
     WHERE business_id = $1 AND id = $2
     RETURNING server_revision`,
    [businessId, originalSaleId, refundId],
  );
  return updated.rows[0]?.server_revision || null;
}

function sumIncomingAmounts(
  rows,
  idField,
  amountField,
  { absolute = false } = {},
) {
  const totals = new Map();
  for (const row of Array.isArray(rows) ? rows : []) {
    const id = normalizeOptionalText(row?.[idField]);
    let amount = Number(row?.[amountField] || 0);
    if (!id || !Number.isFinite(amount)) continue;
    if (absolute) amount = Math.abs(amount);
    if (amount <= 0) continue;
    totals.set(id, (totals.get(id) || 0) + amount);
  }
  return totals;
}

async function ensureSaleCreditBaselineFromServer(client, businessId, saleId) {
  const normalizedSaleId = normalizeOptionalText(saleId);
  if (!normalizedSaleId) return;
  await client.query(
    `INSERT INTO sync_sale_credit_baselines (
       sale_id,
       business_id,
       customer_id,
       initial_balance_due,
       initial_amount_paid
     )
     SELECT
       s.id,
       s.business_id,
       s.customer_id,
       GREATEST(0, COALESCE(s.balance_due, 0))
         + COALESCE((
             SELECT SUM(cp.amount)
             FROM credit_payments cp
             WHERE cp.business_id = s.business_id
               AND cp.sale_id = s.id
               AND cp.deleted_at IS NULL
           ), 0)
         + COALESCE((
             SELECT SUM(ABS(r.total_amount))
             FROM sales r
             WHERE r.business_id = s.business_id
               AND r.refund_for_sale_id = s.id
               AND r.deleted_at IS NULL
           ), 0),
       GREATEST(
         0,
         COALESCE(s.amount_paid, 0)
           - COALESCE((
               SELECT SUM(cp.amount)
               FROM credit_payments cp
               WHERE cp.business_id = s.business_id
                 AND cp.sale_id = s.id
                 AND cp.deleted_at IS NULL
             ), 0)
       )
     FROM sales s
     WHERE s.business_id = $1 AND s.id = $2
     ON CONFLICT (sale_id) DO NOTHING`,
    [businessId, normalizedSaleId],
  );
}

async function ensureSaleCreditBaselineFromIncoming(
  client,
  businessId,
  sale,
  incomingPayments,
  incomingRefunds,
) {
  const saleId = normalizeOptionalText(sale.id);
  const customerId = normalizeOptionalText(sale.customer_id);
  if (!saleId || !customerId || normalizeOptionalText(sale.refund_for_sale_id)) {
    return;
  }
  const balanceDue = Math.max(0, Number(sale.balance_due || 0));
  const amountPaid = Math.max(0, Number(sale.amount_paid || 0));
  await client.query(
    `INSERT INTO sync_sale_credit_baselines (
       sale_id,
       business_id,
       customer_id,
       initial_balance_due,
       initial_amount_paid
     ) VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (sale_id) DO NOTHING`,
    [
      saleId,
      businessId,
      customerId,
      balanceDue + incomingPayments + incomingRefunds,
      Math.max(0, amountPaid - incomingPayments),
    ],
  );
}

async function rebuildSaleCreditBalance(client, businessId, saleId) {
  await ensureSaleCreditBaselineFromServer(client, businessId, saleId);
  const updated = await client.query(
    `UPDATE sales s
     SET balance_due = GREATEST(
           0,
           b.initial_balance_due
             - COALESCE((
                 SELECT SUM(cp.amount)
                 FROM credit_payments cp
                 WHERE cp.business_id = s.business_id
                   AND cp.sale_id = s.id
                   AND cp.deleted_at IS NULL
               ), 0)
             - COALESCE((
                 SELECT SUM(ABS(r.total_amount))
                 FROM sales r
                 WHERE r.business_id = s.business_id
                   AND r.refund_for_sale_id = s.id
                   AND r.deleted_at IS NULL
               ), 0)
         ),
         amount_paid = b.initial_amount_paid
           + COALESCE((
               SELECT SUM(cp.amount)
               FROM credit_payments cp
               WHERE cp.business_id = s.business_id
                 AND cp.sale_id = s.id
                 AND cp.deleted_at IS NULL
             ), 0),
         updated_at = NOW(),
         sync_status = 'synced',
         server_revision = nextval('sync_revision_seq')
     FROM sync_sale_credit_baselines b
     WHERE s.business_id = $1
       AND s.id = $2
       AND b.business_id = s.business_id
       AND b.sale_id = s.id
     RETURNING s.server_revision, s.customer_id`,
    [businessId, saleId],
  );
  if (updated.rows.length === 0) return null;
  return {
    serverRevision: updated.rows[0].server_revision,
    customerId: normalizeOptionalText(updated.rows[0].customer_id),
  };
}

async function rebuildCustomerBalance(client, businessId, customerId) {
  const updated = await client.query(
    `UPDATE customers c
     SET balance = COALESCE((
           SELECT SUM(GREATEST(0, COALESCE(s.balance_due, 0)))
           FROM sales s
           WHERE s.business_id = c.business_id
             AND s.customer_id = c.id
             AND s.deleted_at IS NULL
             AND s.refund_for_sale_id IS NULL
         ), 0),
         updated_at = NOW(),
         sync_status = 'synced',
         server_revision = nextval('sync_revision_seq')
     WHERE c.business_id = $1 AND c.id = $2
     RETURNING server_revision`,
    [businessId, customerId],
  );
  return updated.rows[0]?.server_revision || null;
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

function normalizeSubscriptionPlatform(value) {
  const platform = String(value || '').trim().toLowerCase();
  if (platform === 'android') return 'android';
  if (platform === 'windows') return 'windows';
  return platform || 'windows';
}

function subscriptionProviderAllowedForPlatform(provider, platform) {
  const cleanProvider = normalizeProvider(provider);
  const cleanPlatform = normalizeSubscriptionPlatform(platform);
  if (cleanPlatform === 'android') {
    return cleanProvider === 'google_play';
  }
  return cleanProvider === 'paypal' || cleanProvider === 'flutterwave';
}

function subscriptionMarketsForPlatform(markets, platform, countryCode) {
  const cleanCountry = normalizeCountryCode(countryCode || 'KE');
  const filtered = (markets || []).filter((market) =>
    subscriptionProviderAllowedForPlatform(market.provider, platform),
  );
  const providers = [...new Set(filtered.map((market) => market.provider))];
  return providers.flatMap((provider) => {
    const exact = filtered.find(
      (market) =>
        market.provider === provider && market.countryCode === cleanCountry,
    );
    if (exact) return [exact];
    const global = filtered.find(
      (market) => market.provider === provider && market.countryCode === 'GLOBAL',
    );
    if (!global) return [];
    return [
      {
        ...global,
        countryCode: cleanCountry,
        label: cleanCountry === 'KE' ? 'Kenya' : cleanCountry,
      },
    ];
  });
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
    baseUrl: firstConfiguredText(publicConfig.baseUrl, config.mpesaBaseUrl),
    shortcode: firstConfiguredText(publicConfig.shortcode, config.mpesaShortcode),
    callbackUrl: firstConfiguredText(
      publicConfig.callbackUrl,
      config.mpesaCallbackUrl,
    ),
    consumerKey: firstConfiguredText(
      secretConfig.consumerKey,
      config.mpesaConsumerKey,
    ),
    consumerSecret: firstConfiguredText(
      secretConfig.consumerSecret,
      config.mpesaConsumerSecret,
    ),
    passkey: firstConfiguredText(secretConfig.passkey, config.mpesaPasskey),
  };
}

function firstConfiguredText(...values) {
  for (const value of values) {
    const normalized = normalizeOptionalText(value);
    if (normalized) {
      return normalized;
    }
  }
  return '';
}

function resolveGooglePlayGatewayConfig(gateway) {
  const publicConfig = gateway?.publicConfig || {};
  const secretConfig = gateway?.secretConfig || {};
  return {
    packageName: publicConfig.packageName || config.googlePlayPackageName,
    serviceAccountEmail:
      secretConfig.serviceAccountEmail || config.googlePlayServiceAccountEmail,
    serviceAccountPrivateKey: String(
      secretConfig.serviceAccountPrivateKey ||
        config.googlePlayServiceAccountPrivateKey ||
        '',
    ).replace(/\\n/g, '\n'),
    apiBaseUrl: config.googlePlayApiBaseUrl.replace(/\/+$/, ''),
  };
}

function resolvePayPalGatewayConfig(gateway) {
  const publicConfig = gateway?.publicConfig || {};
  const secretConfig = gateway?.secretConfig || {};
  return {
    baseUrl: String(publicConfig.baseUrl || config.paypalBaseUrl).replace(/\/+$/, ''),
    clientId: secretConfig.clientId || config.paypalClientId,
    clientSecret: secretConfig.clientSecret || config.paypalClientSecret,
  };
}

function resolveFlutterwaveGatewayConfig(gateway) {
  const publicConfig = gateway?.publicConfig || {};
  const secretConfig = gateway?.secretConfig || {};
  return {
    baseUrl: String(publicConfig.baseUrl || config.flutterwaveBaseUrl).replace(/\/+$/, ''),
    secretKey: secretConfig.secretKey || config.flutterwaveSecretKey,
  };
}

function normalizePaymentRow(row) {
  const metadata = row.metadata_json || {};
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
    message: paymentMetadataMessage(metadata),
    metadata,
    createdAt: toIsoString(row.created_at),
  };
}

function paymentMetadataMessage(metadata = {}) {
  return normalizeOptionalText(
    metadata.resultDescription ||
      metadata.ResultDesc ||
      metadata.ResponseDescription ||
      metadata.errorMessage ||
      metadata.error ||
      metadata.message,
  );
}

async function loadPublicCatalog(
  businessId,
  { currencyOverride, branchId: requestedBranchId } = {},
) {
  await ensureCatalogSubdomainSchema(query);
  await ensureStorefrontBrandSchema(query);
  const cacheKey = await buildCatalogCacheKey(businessId, {
    currencyOverride,
    branchId: requestedBranchId,
  });
  const cached = await cacheGetJson(cacheKey);
  if (cached) {
    return cached;
  }
  const businessResult = await query(
    `
    SELECT b.id, b.name, b.country_code, b.currency, b.updated_at,
           b.catalog_logo_url, b.catalog_cover_url, b.catalog_primary_color,
           b.catalog_tagline, b.catalog_description,
           cs.whatsapp_number
    FROM businesses b
    LEFT JOIN business_communication_settings cs
      ON cs.business_id = b.id
    WHERE b.id = $1
      AND b.deleted_at IS NULL
    LIMIT 1
    `,
    [businessId],
  );
  const business = businessResult.rows[0];
  if (!business) {
    throw createHttpError(404, 'Catalog not found');
  }

  const branchesResult = await query(
    `SELECT id, name
     FROM branches
     WHERE business_id = $1
       AND deleted_at IS NULL
       AND COALESCE(is_active, 1) = 1
     ORDER BY CASE WHEN id = 'main_branch' THEN 0 ELSE 1 END, name ASC`,
    [businessId],
  );
  const branches = normalizePublicCatalogBranches(branchesResult.rows);
  const requested = normalizeOptionalText(requestedBranchId);
  if (requested && !branches.some((branch) => branch.id === requested)) {
    throw createHttpError(404, 'Catalog branch not found');
  }
  const selectedBranch = requested
    ? branches.find((branch) => branch.id === requested)
    : branches.find((branch) => branch.id === 'main_branch') || branches[0] || {
        id: 'main_branch',
        name: 'Main',
      };

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
      AND COALESCE(p.branch_id, 'main_branch') = $2
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
    [businessId, selectedBranch.id],
  );

  const products = productsResult.rows.map((row) =>
    normalizePublicCatalogProduct(row),
  );
  const servicesResult = await query(
    `
    SELECT
      s.id,
      COALESCE(s.branch_id, 'main_branch') AS branch_id,
      s.name,
      s.category,
      s.description,
      s.base_price,
      s.duration_minutes,
      s.updated_at
    FROM services s
    WHERE s.business_id = $1
      AND s.deleted_at IS NULL
      AND COALESCE(NULLIF(LOWER(s.is_active::text), ''), '1') NOT IN ('0', 'false', 'no', 'off')
      AND COALESCE(s.branch_id, 'main_branch') = $2
    ORDER BY s.category ASC NULLS LAST, s.name ASC
    LIMIT 500
    `,
    [businessId, selectedBranch.id],
  );
  const serviceItems = servicesResult.rows.map((row) =>
    normalizePublicCatalogService(row),
  );
  const catalogItems = [...products, ...serviceItems];
  const categories = [
    ...new Set(
      catalogItems
        .map((item) => item.category)
        .filter((category) => category && category.trim()),
    ),
  ].sort((a, b) => a.localeCompare(b));

  const currencyInfo = publicCatalogCurrencyInfo(
    currencyOverride || business.currency,
    business.country_code,
  );

  const catalog = {
    business: {
      id: business.id,
      name: business.name,
      countryCode: business.country_code || 'GLOBAL',
      whatsappNumber: normalizeOptionalText(business.whatsapp_number),
      brand: normalizeStorefrontBrandRow(business),
      branches,
      selectedBranch,
    },
    currency: currencyInfo.code,
    currencyCode: currencyInfo.code,
    currencySymbol: currencyInfo.symbol,
    currencyLabel: currencyInfo.label,
    categories,
    products: catalogItems,
    updatedAt: catalogItems.reduce((latest, item) => {
      if (!item.updatedAt) return latest;
      if (!latest || item.updatedAt > latest) return item.updatedAt;
      return latest;
    }, toIsoString(business.updated_at)),
  };
  await cacheSetJson(cacheKey, catalog);
  return catalog;
}

async function buildCatalogCacheKey(
  businessId,
  { currencyOverride, branchId } = {},
) {
  const version = (await cacheGetText(catalogCacheVersionKey(businessId))) || '0';
  return [
    'catalog',
    normalizeCacheKeyPart(businessId),
    normalizeCacheKeyPart(version),
    normalizeCacheKeyPart(branchId || 'default'),
    normalizeCacheKeyPart(currencyOverride || 'default'),
  ].join(':');
}

async function invalidateCatalogCache(businessId) {
  await cacheIncrement(catalogCacheVersionKey(businessId));
}

function catalogCacheVersionKey(businessId) {
  return `catalog-version:${normalizeCacheKeyPart(businessId)}`;
}

function normalizeCacheKeyPart(value) {
  return encodeURIComponent(String(value || '').trim().toLowerCase());
}

function hasCatalogCacheChanges(summary) {
  return [...CATALOG_CACHE_TABLES].some(
    (table) => Number(summary?.applied?.[table] || 0) > 0,
  );
}

async function createPublicCatalogOrder(businessId, payload) {
  await ensureCatalogSubdomainSchema(query);
  await ensurePublicCatalogOrderSchema(query);

  const requestedBranchId = normalizeOptionalText(
    payload.branchId || payload.branch_id,
  );
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
    'SELECT id, name FROM businesses WHERE id = $1 AND deleted_at IS NULL LIMIT 1',
    [businessId],
  );
  const business = businessResult.rows[0];
  if (!business) {
    throw createHttpError(404, 'Catalog not found');
  }

  const preparedItems = [];
  for (const rawItem of rawItems) {
    const itemType = normalizePublicCatalogItemType(
      rawItem?.itemType || rawItem?.item_type || rawItem?.type,
    );
    const productId = normalizeOptionalText(rawItem?.productId || rawItem?.product_id);
    const serviceId = normalizeOptionalText(rawItem?.serviceId || rawItem?.service_id);
    const variantId = normalizeOptionalText(rawItem?.variantId || rawItem?.variant_id);
    const quantity = Number(rawItem?.quantity);
    if (
      (itemType === 'service' ? !(serviceId || productId) : !productId) ||
      !Number.isFinite(quantity) ||
      quantity <= 0
    ) {
      throw createHttpError(400, 'Each order item needs an item and quantity');
    }
    if (quantity > 9999) {
      throw createHttpError(400, 'Order quantity is too high');
    }

    const item = await resolvePublicCatalogOrderItem({
      businessId,
      itemType,
      productId,
      serviceId,
      variantId,
      quantity,
      branchId: requestedBranchId,
    });
    preparedItems.push(item);
  }

  const orderBranchIds = [
    ...new Set(preparedItems.map((item) => item.branchId).filter(Boolean)),
  ];
  if (orderBranchIds.length !== 1) {
    throw createHttpError(400, 'Catalog orders must contain items from one branch');
  }
  const branchId = orderBranchIds[0];

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
        branch_id,
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
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending', $9, $10, 'catalog_link', $11, $12)
      `,
      [
        orderId,
        businessId,
        branchId,
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
          item_type,
          service_id,
          product_id,
          variant_id,
          product_name,
          variant_name,
          quantity,
          unit_price,
          line_total,
          created_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        `,
        [
          crypto.randomUUID(),
          orderId,
          businessId,
          item.itemType,
          item.serviceId,
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
    branchId,
    customerName,
    phone,
    fulfillmentMethod,
    deliveryAddress,
    note,
    status: 'pending',
    subtotal,
    itemCount,
    items: preparedItems.map((item) => ({
      itemType: item.itemType,
      productId: item.productId,
      serviceId: item.serviceId,
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

async function listPublicCatalogOrders(
  businessId,
  { status = 'pending', branchIds = null } = {},
) {
  await ensurePublicCatalogOrderSchema(query);

  const params = [businessId];
  const where = ['o.business_id = $1'];
  if (status && status !== 'all') {
    params.push(status);
    where.push(`o.status = $${params.length}`);
  }
  if (branchIds != null) {
    params.push(branchIds);
    where.push(
      `COALESCE(o.branch_id, 'main_branch') = ANY($${params.length}::text[])`,
    );
  }

  const ordersResult = await query(
    `
    SELECT o.*, b.name AS branch_name
    FROM public_catalog_orders o
    LEFT JOIN branches b
      ON b.business_id = o.business_id
     AND b.id = COALESCE(o.branch_id, 'main_branch')
    WHERE ${where.join(' AND ')}
    ORDER BY o.created_at DESC
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
  await ensureCatalogSubdomainSchema(query);
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
    SELECT o.*
    FROM public_catalog_orders o
    JOIN businesses b
      ON b.id = o.business_id
     AND b.deleted_at IS NULL
    WHERE o.business_id = $1
      AND LOWER(SUBSTRING(o.id FROM 1 FOR 8)) = $2
      AND regexp_replace(COALESCE(o.phone, ''), '[^0-9]', '', 'g') = ANY($3::text[])
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

async function updatePublicCatalogOrderStatus({
  businessId,
  orderId,
  status,
  branchIds = null,
}) {
  await ensurePublicCatalogOrderSchema(query);
  const params = [businessId, orderId, status];
  const branchClause = branchIds == null
    ? ''
    : `AND COALESCE(branch_id, 'main_branch') = ANY($4::text[])`;
  if (branchIds != null) params.push(branchIds);
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
      ${branchClause}
    RETURNING *
    `,
    params,
  );
  if (result.rows.length === 0) {
    throw createHttpError(404, 'Catalog order not found');
  }
  const orders = await attachPublicCatalogOrderItems(result.rows);
  return orders[0];
}

async function assertCatalogOrderScope({ businessId, orderId, branchIds }) {
  if (branchIds == null) return;
  await ensurePublicCatalogOrderSchema(query);
  const result = await query(
    `SELECT id
     FROM public_catalog_orders
     WHERE business_id = $1
       AND id = $2
       AND COALESCE(branch_id, 'main_branch') = ANY($3::text[])
     LIMIT 1`,
    [businessId, orderId, branchIds],
  );
  if (result.rows.length === 0) {
    throw createHttpError(404, 'Catalog order not found');
  }
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
    branchId: row.branch_id || 'main_branch',
    branchName: row.branch_name ||
      (row.branch_id === 'main_branch' ? 'Main' : row.branch_id || 'Main'),
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
    itemType: normalizePublicCatalogItemType(row.item_type),
    productId: row.product_id,
    serviceId: row.service_id || '',
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
  itemType = 'product',
  productId,
  serviceId,
  variantId,
  quantity,
  branchId,
}) {
  if (itemType === 'service') {
    const normalizedServiceId = normalizeServiceCatalogId(serviceId || productId);
    const result = await query(
      `
      SELECT
        s.id AS service_id,
        COALESCE(s.branch_id, 'main_branch') AS branch_id,
        s.name AS service_name,
        s.base_price
      FROM services s
      WHERE s.business_id = $1
        AND s.id = $2
        AND s.deleted_at IS NULL
        AND COALESCE(NULLIF(LOWER(s.is_active::text), ''), '1') NOT IN ('0', 'false', 'no', 'off')
        AND ($3::text IS NULL OR COALESCE(s.branch_id, 'main_branch') = $3)
      LIMIT 1
      `,
      [businessId, normalizedServiceId, branchId],
    );
    const row = result.rows[0];
    if (!row) {
      throw createHttpError(400, 'One of the selected services is no longer available');
    }

    const unitPrice = Number(row.base_price || 0);
    const cleanQuantity = Math.round(quantity * 1000) / 1000;
    return {
      itemType: 'service',
      branchId: row.branch_id,
      productId: row.service_id,
      serviceId: row.service_id,
      variantId: null,
      productName: String(row.service_name || '').trim(),
      variantName: null,
      quantity: cleanQuantity,
      unitPrice,
      lineTotal: Math.round(cleanQuantity * unitPrice * 100) / 100,
    };
  }

  const result = await query(
    `
    SELECT
      p.id AS product_id,
      COALESCE(p.branch_id, 'main_branch') AS branch_id,
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
      AND ($4::text IS NULL OR COALESCE(p.branch_id, 'main_branch') = $4)
    LIMIT 1
    `,
    [businessId, productId, variantId, branchId],
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
    itemType: 'product',
    branchId: row.branch_id,
    productId: row.product_id,
    serviceId: null,
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
      branch_id text NOT NULL DEFAULT 'main_branch',
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
      item_type text NOT NULL DEFAULT 'product',
      service_id text,
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
     ADD COLUMN IF NOT EXISTS branch_id text NOT NULL DEFAULT 'main_branch'`,
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
    `ALTER TABLE public_catalog_order_items
     ADD COLUMN IF NOT EXISTS item_type text NOT NULL DEFAULT 'product'`,
  );
  await runDbQuery(
    target,
    `ALTER TABLE public_catalog_order_items
     ADD COLUMN IF NOT EXISTS service_id text`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_public_catalog_orders_business_status
     ON public_catalog_orders(business_id, status, created_at DESC)`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_public_catalog_orders_business_branch
     ON public_catalog_orders(business_id, branch_id, created_at DESC)`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_public_catalog_order_items_order
     ON public_catalog_order_items(order_id)`,
  );
}

async function createLandingDemoRequest(payload, req) {
  await ensureLandingDemoRequestSchema(query);

  const fullName = limitText(
    normalizeOptionalText(payload.fullName || payload.name),
    160,
  );
  const email = limitText(
    normalizeOptionalText(payload.email)?.toLowerCase(),
    200,
  );
  const storeType = normalizeLandingStoreType(payload.storeType);
  const message = limitText(
    normalizeOptionalText(payload.message || payload.notes),
    1200,
  );

  if (!fullName) {
    throw createHttpError(400, 'Full name is required');
  }
  if (!email || !email.includes('@')) {
    throw createHttpError(400, 'A valid email address is required');
  }

  const now = new Date().toISOString();
  const metadata = {
    source: 'landing_page',
    referrer: normalizeOptionalText(req.get?.('referer')),
    userAgent: normalizeOptionalText(req.get?.('user-agent')),
  };

  const result = await query(
    `
    INSERT INTO landing_demo_requests (
      id,
      full_name,
      email,
      store_type,
      message,
      source,
      status,
      metadata_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5, 'landing_page', 'new', $6::jsonb, $7, $7)
    RETURNING *
    `,
    [
      crypto.randomUUID(),
      fullName,
      email,
      storeType,
      message,
      JSON.stringify(metadata),
      now,
    ],
  );

  return normalizeLandingDemoRequestRow(result.rows[0]);
}

async function ensureLandingDemoRequestSchema(target = query) {
  await runDbQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS landing_demo_requests (
      id text PRIMARY KEY,
      full_name text NOT NULL,
      email text NOT NULL,
      store_type text NOT NULL DEFAULT 'other',
      message text,
      source text NOT NULL DEFAULT 'landing_page',
      status text NOT NULL DEFAULT 'new',
      metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_landing_demo_requests_email
     ON landing_demo_requests(email)`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_landing_demo_requests_created_at
     ON landing_demo_requests(created_at DESC)`,
  );
}

function normalizeLandingDemoRequestRow(row) {
  return {
    id: row.id,
    fullName: row.full_name,
    email: row.email,
    storeType: row.store_type,
    message: row.message,
    status: row.status,
    createdAt: toIsoString(row.created_at),
  };
}

function normalizeLandingStoreType(value) {
  const normalized = normalizeOptionalText(value)
    ?.toLowerCase()
    .replace(/[^a-z0-9_]+/g, '_');
  const allowedTypes = new Set([
    'retail',
    'pharmacy',
    'wholesale',
    'service',
    'other',
  ]);
  return allowedTypes.has(normalized) ? normalized : 'other';
}

function limitText(value, maxLength) {
  const normalized = normalizeOptionalText(value);
  return normalized ? normalized.slice(0, maxLength) : null;
}

function shortOrderNumber(orderId) {
  const clean = String(orderId || '').replace(/-/g, '').toUpperCase();
  return clean ? clean.slice(0, 8) : 'ORDER';
}

function normalizePublicCatalogItemType(value) {
  return String(value || '').trim().toLowerCase() === 'service'
    ? 'service'
    : 'product';
}

function normalizeServiceCatalogId(value) {
  const normalized = normalizeOptionalText(value);
  if (!normalized) {
    return null;
  }
  return normalized.startsWith('service:')
    ? normalized.slice('service:'.length)
    : normalized;
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
    type: 'product',
    id: row.id,
    productId: row.id,
    serviceId: null,
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

function normalizePublicCatalogService(row) {
  const durationMinutes = Number(row.duration_minutes || 0);
  const description = normalizeOptionalText(row.description);
  const durationLabel = durationMinutes > 0
    ? `${durationMinutes} min`
    : null;

  return {
    type: 'service',
    id: `service:${row.id}`,
    productId: null,
    serviceId: row.id,
    name: String(row.name || '').trim(),
    price: Number(row.base_price || 0),
    brand: 'Service',
    category: normalizeOptionalText(row.category) || 'Services',
    unit: 'service',
    imageUrl: null,
    hasVariants: false,
    variants: [],
    availability: 'Available',
    description,
    durationMinutes: durationMinutes > 0 ? durationMinutes : null,
    summary: durationLabel || description,
    updatedAt: toIsoString(row.updated_at),
  };
}

function renderPublicCatalogPage(catalog) {
  const businessName = catalog.business.name || 'Catalog';
  const productCount = catalog.products.length;
  const branchName = catalog.business.selectedBranch?.name || 'Main store';
  const storeInitial = businessName.trim().charAt(0).toUpperCase() || 'P';
  const brand = catalog.business.brand || {};
  const primaryColor = normalizeStorefrontColor(brand.primaryColor, {
    fallback: '#000000',
    throwOnInvalid: false,
  });
  const logoUrl = safePublicImageUrl(brand.logoUrl);
  const coverUrl = safePublicImageUrl(brand.coverUrl);
  const tagline = normalizeOptionalText(brand.tagline) || 'Online catalog';
  const description =
    normalizeOptionalText(brand.description) ||
    'Shop products and services, choose variants, and send your order directly to the store.';
  const safeCatalogJson = JSON.stringify(catalog).replace(/</g, '\\u003c');
  const whatsappNumber = normalizePublicPhone(catalog.business.whatsappNumber || '');

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0" />
  <title>\${escapeHtml(businessName)} - Store</title>
  <meta name="description" content="\${escapeHtml(description)}" />
  <meta property="og:title" content="\${escapeHtml(businessName)}" />
  <meta property="og:description" content="\${escapeHtml(description)}" />
  \${coverUrl ? \`<meta property="og:image" content="\${escapeHtml(coverUrl)}" />\` : ''}
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #f7f9fa;
      --surface: #ffffff;
      --ink: #111827;
      --muted: #6b7280;
      --line: #e5e7eb;
      --primary: \${escapeHtml(primaryColor)};
      --success: #059669;
      --danger: #dc2626;
      --radius-sm: 8px;
      --radius-md: 12px;
      --radius-lg: 20px;
      --shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
      --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
      --shadow-lg: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
      --shadow-floating: 0 24px 50px -12px rgba(0,0,0,0.25);
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
      -webkit-font-smoothing: antialiased;
      padding-bottom: 80px;
    }
    
    /* Navbar */
    .navbar {
      position: sticky;
      top: 0;
      z-index: 40;
      background: rgba(255, 255, 255, 0.85);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      border-bottom: 1px solid var(--line);
      padding: 12px 0;
    }
    .wrap {
      width: min(1200px, 100% - 32px);
      margin: 0 auto;
    }
    .nav-inner {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
    }
    .brand-lockup {
      display: flex;
      align-items: center;
      gap: 12px;
      text-decoration: none;
      color: var(--ink);
      font-weight: 800;
      font-size: 20px;
      letter-spacing: -0.02em;
    }
    .logo-mark {
      width: 40px;
      height: 40px;
      border-radius: var(--radius-sm);
      overflow: hidden;
      background: var(--primary);
      color: #fff;
      display: grid;
      place-items: center;
      font-size: 18px;
    }
    .logo-mark img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }
    .nav-actions {
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .cart-btn-top {
      background: var(--ink);
      color: #fff;
      border: none;
      padding: 10px 16px;
      border-radius: 999px;
      font-weight: 600;
      font-size: 14px;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 8px;
      transition: opacity 0.2s;
    }
    .cart-btn-top:hover { opacity: 0.9; }
    .cart-badge {
      background: var(--primary);
      color: #fff;
      min-width: 20px;
      height: 20px;
      border-radius: 10px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      font-size: 11px;
      font-weight: 800;
      padding: 0 6px;
    }

    /* Hero */
    .hero {
      position: relative;
      background: \${coverUrl ? \`url('\${escapeHtml(coverUrl)}')\` : 'linear-gradient(135deg, var(--ink), #374151)'};
      background-size: cover;
      background-position: center;
      min-height: 380px;
      display: flex;
      align-items: flex-end;
      padding: 60px 0 40px;
    }
    .hero::before {
      content: '';
      position: absolute;
      inset: 0;
      background: linear-gradient(to top, rgba(0,0,0,0.85) 0%, rgba(0,0,0,0.3) 50%, rgba(0,0,0,0.1) 100%);
    }
    .hero-content {
      position: relative;
      z-index: 10;
      color: #fff;
      max-width: 800px;
    }
    .hero-title {
      font-size: clamp(36px, 6vw, 64px);
      font-weight: 800;
      margin: 0 0 12px 0;
      line-height: 1.1;
      letter-spacing: -0.03em;
    }
    .hero-subtitle {
      font-size: clamp(16px, 2vw, 20px);
      color: rgba(255,255,255,0.85);
      margin: 0 0 24px 0;
      line-height: 1.5;
    }
    .search-bar {
      position: relative;
      max-width: 500px;
      margin-top: 24px;
    }
    .search-bar input {
      width: 100%;
      background: rgba(255,255,255,0.95);
      border: 2px solid transparent;
      padding: 16px 20px 16px 48px;
      border-radius: 999px;
      font-size: 16px;
      outline: none;
      box-shadow: var(--shadow-lg);
      transition: all 0.2s;
    }
    .search-bar input:focus {
      background: #fff;
      border-color: var(--primary);
    }
    .search-icon {
      position: absolute;
      left: 18px;
      top: 50%;
      transform: translateY(-50%);
      width: 20px;
      height: 20px;
      opacity: 0.5;
    }

    /* Categories */
    .categories-wrap {
      padding: 24px 0;
      background: var(--surface);
      border-bottom: 1px solid var(--line);
      position: sticky;
      top: 65px;
      z-index: 30;
      box-shadow: 0 4px 12px rgba(0,0,0,0.02);
    }
    .categories {
      display: flex;
      gap: 12px;
      overflow-x: auto;
      scrollbar-width: none;
      -webkit-overflow-scrolling: touch;
      padding-bottom: 4px;
    }
    .categories::-webkit-scrollbar { display: none; }
    .cat-btn {
      background: var(--bg);
      border: 1px solid var(--line);
      padding: 10px 20px;
      border-radius: 999px;
      font-size: 14px;
      font-weight: 600;
      color: var(--muted);
      cursor: pointer;
      white-space: nowrap;
      transition: all 0.2s;
    }
    .cat-btn.active {
      background: var(--ink);
      border-color: var(--ink);
      color: #fff;
    }
    .cat-btn:hover:not(.active) {
      background: #e5e7eb;
      color: var(--ink);
    }

    /* Product Grid */
    .catalog-section {
      padding: 48px 0;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 24px;
    }
    .card {
      background: var(--surface);
      border-radius: var(--radius-lg);
      overflow: hidden;
      box-shadow: var(--shadow-sm);
      border: 1px solid var(--line);
      display: flex;
      flex-direction: column;
      transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
      cursor: pointer;
      position: relative;
    }
    .card:hover {
      box-shadow: var(--shadow-lg);
      transform: translateY(-4px);
    }
    .card-img-wrap {
      aspect-ratio: 4/3;
      background: #f3f4f6;
      overflow: hidden;
      position: relative;
    }
    .card-img-wrap img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      transition: transform 0.5s ease;
    }
    .card:hover .card-img-wrap img {
      transform: scale(1.05);
    }
    .placeholder-icon {
      position: absolute;
      inset: 0;
      display: grid;
      place-items: center;
      color: #9ca3af;
      font-size: 40px;
    }
    .availability-badge {
      position: absolute;
      top: 12px;
      left: 12px;
      background: rgba(255,255,255,0.9);
      backdrop-filter: blur(4px);
      padding: 4px 10px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 700;
      color: var(--ink);
      box-shadow: var(--shadow-sm);
    }
    .availability-badge.unavailable {
      color: var(--danger);
      background: rgba(254, 226, 226, 0.9);
    }
    .card-body {
      padding: 20px;
      display: flex;
      flex-direction: column;
      flex: 1;
    }
    .card-brand {
      font-size: 12px;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.05em;
      font-weight: 700;
      margin-bottom: 4px;
    }
    .card-title {
      font-size: 16px;
      font-weight: 700;
      color: var(--ink);
      margin: 0 0 8px 0;
      line-height: 1.3;
    }
    .card-variants {
      font-size: 13px;
      color: var(--muted);
      margin-bottom: 16px;
    }
    .card-footer {
      margin-top: auto;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .card-price {
      font-size: 20px;
      font-weight: 800;
      color: var(--ink);
    }
    .add-btn {
      background: var(--ink);
      color: #fff;
      border: none;
      width: 36px;
      height: 36px;
      border-radius: 18px;
      display: grid;
      place-items: center;
      font-size: 20px;
      cursor: pointer;
      transition: background 0.2s, transform 0.2s;
    }
    .add-btn:hover {
      background: var(--primary);
      transform: scale(1.05);
    }
    .variant-select-wrapper {
      margin-top: 12px;
    }
    .variant-select-wrapper select {
      width: 100%;
      padding: 10px 12px;
      border-radius: var(--radius-sm);
      border: 1px solid var(--line);
      font-family: inherit;
      font-size: 14px;
      background: #f9fafc;
    }

    /* Cart Drawer */
    .cart-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(17, 24, 39, 0.6);
      backdrop-filter: blur(4px);
      z-index: 100;
      opacity: 0;
      pointer-events: none;
      transition: opacity 0.3s ease;
    }
    .cart-backdrop.open {
      opacity: 1;
      pointer-events: auto;
    }
    .cart-drawer {
      position: fixed;
      top: 0;
      right: 0;
      bottom: 0;
      width: min(440px, 100vw);
      background: var(--surface);
      z-index: 101;
      transform: translateX(100%);
      transition: transform 0.4s cubic-bezier(0.16, 1, 0.3, 1);
      display: flex;
      flex-direction: column;
      box-shadow: var(--shadow-floating);
    }
    .cart-drawer.open {
      transform: translateX(0);
    }
    .cart-header {
      padding: 24px;
      border-bottom: 1px solid var(--line);
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .cart-header h2 {
      margin: 0;
      font-size: 24px;
      font-weight: 800;
      letter-spacing: -0.03em;
    }
    .close-btn {
      background: transparent;
      border: none;
      font-size: 28px;
      color: var(--muted);
      cursor: pointer;
      line-height: 1;
      padding: 4px;
    }
    .close-btn:hover { color: var(--ink); }
    
    .cart-body {
      flex: 1;
      overflow-y: auto;
      padding: 24px;
      display: flex;
      flex-direction: column;
      gap: 24px;
    }
    .cart-item {
      display: flex;
      gap: 16px;
      align-items: center;
    }
    .cart-item-img {
      width: 64px;
      height: 64px;
      border-radius: var(--radius-sm);
      background: #f3f4f6;
      object-fit: cover;
    }
    .cart-item-info {
      flex: 1;
      display: flex;
      flex-direction: column;
      gap: 4px;
    }
    .cart-item-title {
      font-size: 14px;
      font-weight: 600;
      color: var(--ink);
    }
    .cart-item-price {
      font-size: 14px;
      color: var(--muted);
    }
    .cart-item-actions {
      display: flex;
      align-items: center;
      gap: 12px;
      background: var(--bg);
      border-radius: 999px;
      padding: 4px;
      border: 1px solid var(--line);
    }
    .qty-btn {
      width: 28px;
      height: 28px;
      border-radius: 14px;
      background: #fff;
      border: 1px solid var(--line);
      display: grid;
      place-items: center;
      cursor: pointer;
      font-size: 16px;
      font-weight: 600;
      color: var(--ink);
    }
    .qty-display {
      font-size: 14px;
      font-weight: 600;
      min-width: 20px;
      text-align: center;
    }
    .cart-empty-state {
      text-align: center;
      padding: 60px 20px;
      color: var(--muted);
    }
    .cart-empty-state svg {
      width: 64px;
      height: 64px;
      opacity: 0.2;
      margin-bottom: 16px;
    }

    /* Checkout Form */
    .checkout-form {
      display: flex;
      flex-direction: column;
      gap: 16px;
      background: var(--bg);
      padding: 20px;
      border-radius: var(--radius-md);
      border: 1px solid var(--line);
    }
    .form-group {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }
    .form-group label {
      font-size: 13px;
      font-weight: 700;
      color: var(--ink);
    }
    .form-input {
      padding: 12px 16px;
      border-radius: var(--radius-sm);
      border: 1px solid var(--line);
      font-family: inherit;
      font-size: 15px;
      transition: all 0.2s;
    }
    .form-input:focus {
      outline: none;
      border-color: var(--primary);
      box-shadow: 0 0 0 3px rgba(0,0,0,0.05);
    }
    textarea.form-input {
      min-height: 80px;
      resize: vertical;
    }
    .radio-group {
      display: flex;
      gap: 12px;
    }
    .radio-label {
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 12px;
      border: 1px solid var(--line);
      border-radius: var(--radius-sm);
      cursor: pointer;
      font-weight: 600;
      font-size: 14px;
      background: #fff;
      transition: all 0.2s;
    }
    .radio-label:has(input:checked) {
      border-color: var(--ink);
      background: var(--ink);
      color: #fff;
    }
    .radio-label input {
      display: none;
    }

    .cart-footer {
      padding: 24px;
      border-top: 1px solid var(--line);
      background: var(--surface);
    }
    .cart-total-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
      font-size: 20px;
      font-weight: 800;
    }
    .checkout-btn {
      width: 100%;
      padding: 16px;
      background: var(--primary);
      color: #fff;
      border: none;
      border-radius: var(--radius-sm);
      font-size: 16px;
      font-weight: 800;
      cursor: pointer;
      transition: transform 0.2s, opacity 0.2s;
    }
    .checkout-btn:hover { opacity: 0.9; }
    .checkout-btn:active { transform: scale(0.98); }
    .checkout-btn:disabled {
      background: var(--muted);
      cursor: not-allowed;
      transform: none;
    }
    .whatsapp-btn {
      display: none;
      width: 100%;
      padding: 16px;
      background: #25D366;
      color: #fff;
      border: none;
      border-radius: var(--radius-sm);
      font-size: 16px;
      font-weight: 800;
      cursor: pointer;
      text-align: center;
      text-decoration: none;
      margin-top: 12px;
    }

    /* System Messages */
    .alert {
      padding: 16px;
      border-radius: var(--radius-sm);
      font-size: 14px;
      font-weight: 600;
      margin-bottom: 16px;
      display: none;
    }
    .alert-success { background: #d1fae5; color: #065f46; border: 1px solid #34d399; }
    .alert-error { background: #fee2e2; color: #991b1b; border: 1px solid #f87171; }

    /* Footer */
    .site-footer {
      border-top: 1px solid var(--line);
      padding: 40px 0;
      margin-top: 40px;
      background: #fff;
      text-align: center;
      color: var(--muted);
      font-size: 14px;
    }
    .footer-links {
      display: flex;
      justify-content: center;
      gap: 24px;
      margin-top: 16px;
    }
    .footer-links a {
      color: var(--muted);
      text-decoration: none;
      font-weight: 600;
    }
    .footer-links a:hover { color: var(--ink); }

    /* Mobile floating button */
    .mobile-cart-float {
      display: none;
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: var(--primary);
      color: white;
      border: none;
      border-radius: 999px;
      padding: 14px 24px;
      font-weight: 800;
      font-size: 15px;
      box-shadow: var(--shadow-floating);
      z-index: 30;
      cursor: pointer;
    }

    @media (max-width: 768px) {
      .hero { min-height: 320px; padding: 40px 0 30px; }
      .hero-title { font-size: 32px; }
      .grid { grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 16px; }
      .card-body { padding: 12px; }
      .card-title { font-size: 14px; }
      .card-price { font-size: 16px; }
      .add-btn { width: 32px; height: 32px; font-size: 18px; }
      .navbar .cart-btn-top { display: none; }
      .mobile-cart-float { display: flex; align-items: center; gap: 8px; }
    }
  </style>
</head>
<body>

  <!-- Top Navigation -->
  <header class="navbar">
    <div class="wrap nav-inner">
      <a href="#" class="brand-lockup">
        <div class="logo-mark">
          \${logoUrl ? \`<img src="\${escapeHtml(logoUrl)}" alt="Logo" />\` : storeInitial}
        </div>
        <span>\${escapeHtml(businessName)}</span>
      </a>
      <div class="nav-actions">
        <button class="cart-btn-top" onclick="toggleCart()">
          <svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"></path>
          </svg>
          Cart <span class="cart-badge" id="nav-cart-count">0</span>
        </button>
      </div>
    </div>
  </header>

  <!-- Hero Banner -->
  <section class="hero">
    <div class="wrap hero-content">
      <h1 class="hero-title">\${escapeHtml(businessName)}</h1>
      <p class="hero-subtitle">\${escapeHtml(tagline)}</p>
      
      <div class="search-bar">
        <svg class="search-icon" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
        </svg>
        <input type="text" id="search-input" placeholder="Search products..." onkeyup="handleSearch()" />
      </div>
    </div>
  </section>

  <!-- Categories Sticky Bar -->
  <div class="categories-wrap">
    <div class="wrap categories" id="category-pills">
      <button class="cat-btn active" onclick="setCategory('all', this)">All Items</button>
      <!-- Categories injected via JS -->
    </div>
  </div>

  <!-- Main Catalog Grid -->
  <main class="catalog-section wrap">
    <div id="empty-state" style="display: none; text-align: center; padding: 60px 0; color: var(--muted);">
      <svg width="64" height="64" fill="none" stroke="currentColor" viewBox="0 0 24 24" style="opacity:0.3; margin:0 auto 16px;">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"></path>
      </svg>
      <h3>No products found</h3>
      <p>Try adjusting your search or category filter.</p>
    </div>
    
    <div class="grid" id="product-grid">
      <!-- Products injected via JS -->
    </div>
  </main>

  <!-- Order Tracking -->
  <section class="wrap" style="margin-top: 48px; background: var(--surface); padding: 32px; border-radius: var(--radius-lg); border: 1px solid var(--line);">
    <h3 style="margin: 0 0 16px; font-size: 20px;">Track your order</h3>
    <form id="tracking-form" style="display: flex; gap: 12px; flex-wrap: wrap; align-items: flex-end;" onsubmit="trackOrder(event)">
      <div class="form-group" style="flex:1; min-width:200px">
        <label>Order Number</label>
        <input id="tracking-order-number" class="form-input" required placeholder="A1B2C3D4">
      </div>
      <div class="form-group" style="flex:1; min-width:200px">
        <label>Phone Number</label>
        <input id="tracking-phone" class="form-input" required placeholder="+254...">
      </div>
      <button type="submit" id="track-btn" class="cart-btn-top" style="height: 44px">Track Order</button>
    </form>
    <div id="tracking-result" class="alert" style="margin-top:16px"></div>
  </section>

  <!-- Footer -->
  <footer class="site-footer">
    <div class="wrap">
      <p>Powered by <strong>Piki POS</strong></p>
      <div class="footer-links">
        <a href="#">Terms of Service</a>
        <a href="#">Privacy Policy</a>
      </div>
    </div>
  </footer>

  <!-- Mobile Floating Cart -->
  <button class="mobile-cart-float" onclick="toggleCart()">
    <svg width="20" height="20" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"></path>
    </svg>
    View Cart (<span id="fab-cart-count">0</span>)
  </button>

  <!-- Slide-out Cart Drawer -->
  <div class="cart-backdrop" id="cart-backdrop" onclick="toggleCart()"></div>
  <aside class="cart-drawer" id="cart-drawer">
    <div class="cart-header">
      <h2>Your Cart</h2>
      <button class="close-btn" onclick="toggleCart()">&times;</button>
    </div>
    
    <div class="cart-body" id="cart-body">
      <!-- Cart items injected via JS -->
      <div class="cart-empty-state" id="cart-empty-state">
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"></path>
        </svg>
        <p>Your cart is empty.<br>Browse the catalog to add items.</p>
      </div>
      
      <!-- Checkout Form (Hidden when empty) -->
      <div id="checkout-section" style="display: none;">
        <h3 style="margin: 0 0 16px; font-size: 16px;">Delivery Details</h3>
        
        <div id="alert-success" class="alert alert-success">Order placed successfully!</div>
        <div id="alert-error" class="alert alert-error">Something went wrong.</div>

        <form id="order-form" class="checkout-form" onsubmit="submitOrder(event)">
          <div class="form-group">
            <label>Name</label>
            <input type="text" id="customer-name" class="form-input" required placeholder="John Doe">
          </div>
          <div class="form-group">
            <label>Phone Number</label>
            <input type="tel" id="customer-phone" class="form-input" required placeholder="+254...">
          </div>
          
          <div class="radio-group">
            <label class="radio-label">
              <input type="radio" name="fulfillment" value="delivery" checked> Delivery
            </label>
            <label class="radio-label">
              <input type="radio" name="fulfillment" value="pickup"> Pickup
            </label>
          </div>

          <div class="form-group">
            <label>Address / Note</label>
            <textarea id="order-note" class="form-input" placeholder="Delivery instructions..."></textarea>
          </div>
        </form>
      </div>
    </div>
    
    <div class="cart-footer">
      <div class="cart-total-row">
        <span>Total</span>
        <span id="cart-total-display">$0.00</span>
      </div>
      <button class="checkout-btn" id="checkout-btn" onclick="document.getElementById('order-form').requestSubmit()" disabled>Place Order</button>
      <a href="#" class="whatsapp-btn" id="whatsapp-btn" target="_blank">Send via WhatsApp</a>
    </div>
  </aside>

  <!-- Application State & Logic -->
  <script id="catalog-data" type="application/json">\${safeCatalogJson}</script>
  <script>
    // System Init
    const catalog = JSON.parse(document.getElementById('catalog-data').textContent);
    const shopWhatsApp = '\${escapeHtml(whatsappNumber)}';
    
    // State
    const state = {
      cart: new Map(),
      activeCategory: 'all',
      searchQuery: '',
      isCartOpen: false
    };

    // DOM Elements
    const els = {
      grid: document.getElementById('product-grid'),
      empty: document.getElementById('empty-state'),
      catPills: document.getElementById('category-pills'),
      navCount: document.getElementById('nav-cart-count'),
      fabCount: document.getElementById('fab-cart-count'),
      cartDrawer: document.getElementById('cart-drawer'),
      cartBackdrop: document.getElementById('cart-backdrop'),
      cartBody: document.getElementById('cart-body'),
      cartEmpty: document.getElementById('cart-empty-state'),
      checkoutSec: document.getElementById('checkout-section'),
      cartTotal: document.getElementById('cart-total-display'),
      checkoutBtn: document.getElementById('checkout-btn'),
      whatsappBtn: document.getElementById('whatsapp-btn'),
      alertSuccess: document.getElementById('alert-success'),
      alertError: document.getElementById('alert-error'),
      searchInput: document.getElementById('search-input')
    };

    // Currency Formatter
    const currencyCode = catalog.currencyCode || catalog.currency || 'KES';
    const currencySymbol = String(catalog.currencySymbol || '').trim();
    const formatMoney = (amount) => {
      amount = Number(amount || 0);
      if (currencySymbol) {
        return currencySymbol + amount.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      }
      return new Intl.NumberFormat('en', { style: 'currency', currency: currencyCode }).format(amount);
    };

    // Helpers
    const safeHtml = (str) => String(str || '').replace(/[&<>"']/g, m => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[m]);
    
    function init() {
      // Extract unique categories
      const cats = new Set();
      [...catalog.products, ...catalog.services].forEach(item => {
        if (item.category && item.category !== 'Services') cats.add(item.category);
      });
      
      // Render category pills
      const sortedCats = Array.from(cats).sort();
      sortedCats.forEach(c => {
        const btn = document.createElement('button');
        btn.className = 'cat-btn';
        btn.textContent = c;
        btn.onclick = () => setCategory(c, btn);
        els.catPills.appendChild(btn);
      });

      renderGrid();
      renderCart();
    }

    function handleSearch() {
      state.searchQuery = els.searchInput.value.toLowerCase().trim();
      renderGrid();
    }

    function setCategory(cat, btnElement) {
      state.activeCategory = cat;
      document.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
      btnElement.classList.add('active');
      renderGrid();
    }

    function toggleCart() {
      state.isCartOpen = !state.isCartOpen;
      if (state.isCartOpen) {
        els.cartDrawer.classList.add('open');
        els.cartBackdrop.classList.add('open');
        document.body.style.overflow = 'hidden';
      } else {
        els.cartDrawer.classList.remove('open');
        els.cartBackdrop.classList.remove('open');
        document.body.style.overflow = '';
      }
    }

    function getItems() {
      return [...catalog.products, ...catalog.services].filter(item => {
        const matchCat = state.activeCategory === 'all' || item.category === state.activeCategory;
        const matchSearch = !state.searchQuery || item.name.toLowerCase().includes(state.searchQuery) || (item.brand || '').toLowerCase().includes(state.searchQuery);
        return matchCat && matchSearch;
      });
    }

    function renderGrid() {
      const items = getItems();
      els.grid.innerHTML = '';
      
      if (items.length === 0) {
        els.empty.style.display = 'block';
        return;
      }
      
      els.empty.style.display = 'none';
      
      items.forEach(item => {
        const isAvailable = item.availability === 'Available';
        const badge = isAvailable 
          ? '' 
          : '<div class="availability-badge unavailable">Unavailable</div>';
        
        const img = item.imageUrl 
          ? \`<img src="\${safeHtml(item.imageUrl)}" loading="lazy" alt="\${safeHtml(item.name)}">\`
          : \`<div class="placeholder-icon"><svg width="32" height="32" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"></path></svg></div>\`;

        // Handle variants selector if needed
        let variantsHtml = '';
        let primaryPrice = item.price;
        
        if (item.hasVariants && item.variants.length > 0) {
          primaryPrice = item.variants[0].price;
          variantsHtml = \`
            <div class="variant-select-wrapper" onclick="event.stopPropagation()">
              <select id="var-\${item.id}" onchange="updatePrice('\${item.id}', this.options[this.selectedIndex].dataset.price)">
                \${item.variants.map((v, i) => \`<option value="\${v.id}" data-price="\${v.price}" \${i===0?'selected':''}>\${safeHtml(v.name)} - \${formatMoney(v.price)}</option>\`).join('')}
              </select>
            </div>
          \`;
        } else if (item.hasVariants) {
          variantsHtml = '<div class="card-variants">Multiple options available</div>';
        }

        const priceId = \`price-\${item.id}\`;

        const card = document.createElement('div');
        card.className = 'card';
        card.onclick = () => {
          // If variants exist, get the selected one
          let selectedVarId = null;
          if (item.hasVariants && item.variants.length > 0) {
            const sel = document.getElementById(\`var-\${item.id}\`);
            if (sel) selectedVarId = sel.value;
          }
          addToCart(item, selectedVarId);
        };

        card.innerHTML = \`
          <div class="card-img-wrap">
            \${badge}
            \${img}
          </div>
          <div class="card-body">
            \${item.brand && item.brand !== 'Service' ? \`<div class="card-brand">\${safeHtml(item.brand)}</div>\` : ''}
            <h3 class="card-title">\${safeHtml(item.name)}</h3>
            \${variantsHtml}
            <div class="card-footer">
              <div class="card-price" id="\${priceId}">\${formatMoney(primaryPrice)}</div>
              <button class="add-btn" onclick="event.stopPropagation(); this.parentElement.parentElement.parentElement.click()" aria-label="Add to cart">
                +
              </button>
            </div>
          </div>
        \`;
        els.grid.appendChild(card);
      });
    }

    // Global function to update price displayed on the card when variant changes
    window.updatePrice = (itemId, newPrice) => {
      const priceEl = document.getElementById(\`price-\${itemId}\`);
      if (priceEl) {
        priceEl.textContent = formatMoney(newPrice);
      }
    };

    function cartKey(item, variantId) {
      return item.id + ':' + (variantId || '');
    }

    function addToCart(item, variantId) {
      const key = cartKey(item, variantId);
      const existing = state.cart.get(key);
      
      let variant = null;
      if (variantId && item.variants) {
        variant = item.variants.find(v => v.id === variantId);
      }

      state.cart.set(key, {
        item,
        variant,
        qty: existing ? existing.qty + 1 : 1
      });

      // Reset states
      els.alertSuccess.style.display = 'none';
      els.alertError.style.display = 'none';
      els.whatsappBtn.style.display = 'none';
      els.checkoutBtn.style.display = 'block';

      renderCart();
      toggleCart(); // Open cart on add
    }

    function updateQty(key, delta) {
      const existing = state.cart.get(key);
      if (!existing) return;
      
      const newQty = existing.qty + delta;
      if (newQty <= 0) {
        state.cart.delete(key);
      } else {
        existing.qty = newQty;
      }
      renderCart();
    }

    function renderCart() {
      const items = Array.from(state.cart.values());
      const totalQty = items.reduce((sum, i) => sum + i.qty, 0);
      
      els.navCount.textContent = totalQty;
      els.fabCount.textContent = totalQty;

      if (items.length === 0) {
        els.cartEmpty.style.display = 'block';
        els.checkoutSec.style.display = 'none';
        els.checkoutBtn.disabled = true;
        // clear old item nodes
        document.querySelectorAll('.cart-item-row').forEach(n => n.remove());
        els.cartTotal.textContent = formatMoney(0);
        return;
      }

      els.cartEmpty.style.display = 'none';
      els.checkoutSec.style.display = 'block';
      els.checkoutBtn.disabled = false;

      // Render lines
      document.querySelectorAll('.cart-item-row').forEach(n => n.remove());
      
      let totalValue = 0;

      items.forEach(cartEntry => {
        const { item, variant, qty } = cartEntry;
        const key = cartKey(item, variant ? variant.id : null);
        const price = variant ? variant.price : item.price;
        const title = variant ? \`\${item.name} (\${variant.name})\` : item.name;
        totalValue += (price * qty);

        const imgHtml = item.imageUrl 
          ? \`<img src="\${safeHtml(item.imageUrl)}" class="cart-item-img">\`
          : \`<div class="cart-item-img" style="display:grid;place-items:center;color:#9ca3af"><svg width="24" height="24" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16"></path></svg></div>\`;

        const row = document.createElement('div');
        row.className = 'cart-item cart-item-row';
        row.innerHTML = \`
          \${imgHtml}
          <div class="cart-item-info">
            <div class="cart-item-title">\${safeHtml(title)}</div>
            <div class="cart-item-price">\${formatMoney(price)}</div>
          </div>
          <div class="cart-item-actions">
            <button class="qty-btn" onclick="updateQty('\${key}', -1)">-</button>
            <span class="qty-display">\${qty}</span>
            <button class="qty-btn" onclick="updateQty('\${key}', 1)">+</button>
          </div>
        \`;
        els.cartBody.insertBefore(row, els.checkoutSec);
      });

      els.cartTotal.textContent = formatMoney(totalValue);
    }

    async function submitOrder(e) {
      e.preventDefault();
      
      const items = Array.from(state.cart.values());
      if (items.length === 0) return;

      const name = document.getElementById('customer-name').value;
      const phone = document.getElementById('customer-phone').value;
      const method = document.querySelector('input[name="fulfillment"]:checked').value;
      const note = document.getElementById('order-note').value;

      els.checkoutBtn.disabled = true;
      els.checkoutBtn.textContent = 'Processing...';
      els.alertError.style.display = 'none';

      try {
        const payload = {
          businessId: catalog.business.id,
          branchId: catalog.business.selectedBranch ? catalog.business.selectedBranch.id : null,
          customerName: name,
          phone,
          fulfillmentMethod: method,
          deliveryAddress: note,
          note: note,
          lines: items.map(entry => ({
            productId: entry.item.type === 'product' ? entry.item.id : null,
            variantId: entry.variant ? entry.variant.id : null,
            serviceId: entry.item.type === 'service' ? entry.item.serviceId : null,
            quantity: entry.qty
          }))
        };

        const res = await fetch('/api/public/orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        const data = await res.json();
        
        if (!res.ok) {
          throw new Error(data.message || 'Failed to submit order');
        }

        // Success
        state.cart.clear();
        renderCart();
        
        els.alertSuccess.textContent = 'Order placed successfully! Reference: ' + data.order.order_number;
        els.alertSuccess.style.display = 'block';
        els.checkoutBtn.style.display = 'none';

        // Show WhatsApp button if configured
        if (shopWhatsApp) {
          const waUrl = new URL('https://wa.me/' + shopWhatsApp.replace(/\\D/g, ''));
          waUrl.searchParams.set('text', \`Hi, I just placed an order (\${data.order.order_number}) on your catalog. Please confirm.\`);
          els.whatsappBtn.href = waUrl.toString();
          els.whatsappBtn.style.display = 'block';
        }

      } catch (err) {
        els.alertError.textContent = err.message;
        els.alertError.style.display = 'block';
        els.checkoutBtn.disabled = false;
        els.checkoutBtn.textContent = 'Place Order';
      }
    }

    async function trackOrder(e) {
      e.preventDefault();
      const btn = document.getElementById('track-btn');
      const resDiv = document.getElementById('tracking-result');
      btn.textContent = 'Tracking...';
      btn.disabled = true;
      try {
        const no = document.getElementById('tracking-order-number').value.trim();
        const ph = document.getElementById('tracking-phone').value.trim();
        const res = await fetch(`/api/public/orders/${encodeURIComponent(no)}/track?phone=${encodeURIComponent(ph)}`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || 'Not found');
        resDiv.className = 'alert alert-success';
        resDiv.innerHTML = `Order status: <strong>${safeHtml(data.order.status)}</strong><br>Last updated: ${new Date(data.order.updated_at).toLocaleString()}`;
        resDiv.style.display = 'block';
      } catch (err) {
        resDiv.className = 'alert alert-error';
        resDiv.textContent = err.message;
        resDiv.style.display = 'block';
      } finally {
        btn.textContent = 'Track Order';
        btn.disabled = false;
      }
    }

    // Start
    init();
  </script>
</body>
</html>\`;
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

function normalizeDeletionConfirmation(value) {
  const normalized = normalizeOptionalText(value);
  return normalized ? normalized.replace(/\s+/g, ' ').toLowerCase() : null;
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
    const errors = [];
    if (gateway.provider === 'mpesa' && !config.mpesaCallbackSecret) {
      errors.push('M-Pesa callback secret');
    }
    return errors;
  } catch (error) {
    const message = error.message || 'Payment gateway is incomplete.';
    return [message.replace(/^Complete [^:]+:\s*/i, '')];
  }
}

function createHttpError(statusCode, message, { exposeMessage = false } = {}) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.exposeMessage = exposeMessage;
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

function isBranchScopedTable(tableName) {
  const table = syncTables.find((entry) => entry.name === tableName);
  return Boolean(table?.columns?.includes('branch_id'));
}

const syncTableFeatures = Object.freeze({
  categories: 'categories',
  expense_categories: 'profit_loss',
  suppliers: 'purchases',
  products: 'products',
  product_variants: 'products',
  purchase_invoices: 'purchases',
  supplier_payments: 'purchases',
  purchase_orders: 'purchases',
  purchase_order_items: 'purchases',
  stock_batches: 'products',
  stock_transfers: 'transfers',
  customer_invoices: 'sales',
  customer_invoice_items: 'sales',
  expenses: 'profit_loss',
  services: 'services',
  service_fields: 'services',
  service_orders: 'services',
  service_field_values: 'services',
});

const employeeAttributionTables = new Set([
  'shifts',
  'cash_movements',
  'credit_payments',
  'audit_logs',
]);

function hasBusinessFeature(businessContext, feature) {
  return businessContext.featureAccess.includes('*') ||
    businessContext.featureAccess.includes(feature);
}

async function validateSyncWriteAccess(
  client,
  tableName,
  record,
  scope,
  businessContext,
) {
  if (tableName === 'users' || tableName === 'branches') {
    if (businessContext.role !== 'ADMIN') {
      return rejectedAccess('admin_write_required', 'Only an administrator can change this data');
    }
  }
  if (
    tableName === 'payment_methods' &&
    businessContext.role !== 'ADMIN' &&
    businessContext.role !== 'MANAGER'
  ) {
    return rejectedAccess(
      'manager_write_required',
      'Only a manager or administrator can change payment methods',
    );
  }

  const feature = syncTableFeatures[tableName];
  if (feature && !hasBusinessFeature(businessContext, feature)) {
    return rejectedAccess(
      'feature_access_denied',
      `This employee cannot change ${feature.replaceAll('_', ' ')}`,
    );
  }

  if (tableName === 'sales') {
    const saleUserId = normalizeOptionalText(record.user_id);
    if (businessContext.role !== 'ADMIN' && saleUserId !== businessContext.userId) {
      return rejectedAccess(
        'employee_identity_mismatch',
        'Sales must be recorded under the employee signed in on this device',
      );
    }
    if (
      normalizeOptionalText(record.refund_for_sale_id) &&
      businessContext.role !== 'ADMIN' &&
      businessContext.role !== 'MANAGER'
    ) {
      return rejectedAccess(
        'refund_access_denied',
        'Only a manager or administrator can issue refunds',
      );
    }
  }

  if (
    employeeAttributionTables.has(tableName) &&
    businessContext.role !== 'ADMIN'
  ) {
    const attributedUserId = normalizeOptionalText(record.user_id);
    if (attributedUserId && attributedUserId !== businessContext.userId) {
      return rejectedAccess(
        'employee_identity_mismatch',
        'Activity must be recorded under the employee signed in on this device',
      );
    }
    record.user_id = attributedUserId || businessContext.userId;
  }

  if (isBranchScopedTable(tableName)) {
    let rowBranchId = normalizeOptionalText(record.branch_id);
    if (!rowBranchId && scope.branchIds?.length === 1) {
      rowBranchId = scope.branchIds[0];
      record.branch_id = rowBranchId;
    }
    if (
      scope.branchIds != null &&
      (!rowBranchId || !scope.branchIds.includes(rowBranchId))
    ) {
      return rejectedAccess(
        'branch_scope_mismatch',
        'Record branch is outside this employee\'s allowed branches',
      );
    }
  }

  if (tableName === 'stock_transfers' && scope.branchIds != null) {
    const transferBranches = [record.from_branch_id, record.to_branch_id]
      .map(normalizeOptionalText)
      .filter(Boolean);
    if (transferBranches.some((branch) => !scope.branchIds.includes(branch))) {
      return rejectedAccess(
        'branch_scope_mismatch',
        'Stock transfer includes a branch this employee cannot access',
      );
    }
  }

  const childScope = childBranchScopes[tableName];
  if (childScope && scope.branchIds != null) {
    const parentId = normalizeOptionalText(record[childScope.foreignKey]);
    if (!parentId) {
      return rejectedAccess('missing_parent', 'Scoped record is missing its parent');
    }
    const result = await client.query(
      `SELECT COALESCE(branch_id, 'main_branch') AS branch_id
       FROM ${childScope.table}
       WHERE business_id = $1 AND id = $2
       LIMIT 1`,
      [businessContext.businessId, parentId],
    );
    const parentBranchId = normalizeOptionalText(result.rows[0]?.branch_id);
    if (!parentBranchId || !scope.branchIds.includes(parentBranchId)) {
      return rejectedAccess(
        'branch_scope_mismatch',
        'Related record is outside this employee\'s allowed branches',
      );
    }
  }

  return { ok: true };
}

function rejectedAccess(code, message) {
  return { ok: false, error: { code, message } };
}

function resolveDataScope(businessContext, requestedBranchId) {
  const requested = normalizeOptionalText(requestedBranchId);
  const allowed = businessContext.role === 'ADMIN'
    ? []
    : businessContext.allowedBranchIds;

  if (requested && allowed.length > 0 && !allowed.includes(requested)) {
    throw createHttpError(403, 'This employee cannot access the selected branch');
  }

  return {
    branchIds: requested ? [requested] : allowed.length > 0 ? allowed : null,
    userId: businessContext.userId,
    restrictUsers: businessContext.role === 'CASHIER',
    restrictToOwnActivity: businessContext.role === 'CASHIER',
  };
}

function dataScopeKey(businessContext, scope) {
  const branches = scope.branchIds == null
    ? '*'
    : [...scope.branchIds].sort().join(',');
  return [businessContext.userId, businessContext.role, branches].join(':');
}

const childBranchScopes = Object.freeze({
  sale_items: { table: 'sales', foreignKey: 'sale_id' },
  service_fields: { table: 'services', foreignKey: 'service_id' },
  service_field_values: {
    table: 'service_orders',
    foreignKey: 'service_order_id',
  },
  service_sale_items: { table: 'sales', foreignKey: 'sale_id' },
});

function dataScopeClause(tableName, scope, params, alias = 't') {
  const clauses = [];
  if (scope?.restrictUsers && tableName === 'users') {
    params.push(scope.userId);
    clauses.push(`${alias}.id = $${params.length}`);
  }

  if (
    scope?.restrictToOwnActivity &&
    ['sales', 'shifts', 'cash_movements', 'credit_payments', 'audit_logs'].includes(
      tableName,
    )
  ) {
    params.push(scope.userId);
    clauses.push(`${alias}.user_id = $${params.length}`);
  }
  if (
    scope?.restrictToOwnActivity &&
    (tableName === 'sale_items' || tableName === 'service_sale_items')
  ) {
    params.push(scope.userId);
    clauses.push(
      `EXISTS (
         SELECT 1
         FROM sales activity_parent
         WHERE activity_parent.business_id = ${alias}.business_id
           AND activity_parent.id = ${alias}.sale_id
           AND activity_parent.user_id = $${params.length}
       )`,
    );
  }

  if (!scope || scope.branchIds == null) {
    return clauses.length ? ` AND ${clauses.join(' AND ')}` : '';
  }

  const usesBranchScope =
    tableName === 'branches' ||
    isBranchScopedTable(tableName) ||
    Boolean(childBranchScopes[tableName]);
  if (!usesBranchScope) {
    return clauses.length ? ` AND ${clauses.join(' AND ')}` : '';
  }

  params.push(scope.branchIds);
  const branchParam = `$${params.length}::text[]`;
  if (tableName === 'branches') {
    clauses.push(`${alias}.id = ANY(${branchParam})`);
  } else if (isBranchScopedTable(tableName)) {
    clauses.push(
      `COALESCE(${alias}.branch_id, 'main_branch') = ANY(${branchParam})`,
    );
  } else if (childBranchScopes[tableName]) {
    const parent = childBranchScopes[tableName];
    clauses.push(
      `EXISTS (
         SELECT 1
         FROM ${parent.table} scope_parent
         WHERE scope_parent.business_id = ${alias}.business_id
           AND scope_parent.id = ${alias}.${parent.foreignKey}
           AND COALESCE(scope_parent.branch_id, 'main_branch') = ANY(${branchParam})
       )`,
    );
  }
  return clauses.length ? ` AND ${clauses.join(' AND ')}` : '';
}

function buildStatusQuery(tableName, syncWindow, businessId, scope) {
  const baseParams = [businessId];
  const scopeClause = dataScopeClause(tableName, scope, baseParams);
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
            FROM ${tableName} t
            WHERE t.business_id = $1${scopeClause}`,
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
            FROM ${tableName} t
            WHERE t.business_id = $1${scopeClause}`,
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
          FROM ${tableName} t
          WHERE t.business_id = $1${scopeClause}`,
    params: baseParams,
  };
}

function buildPullQuery(tableName, syncWindow, businessId, scope) {
  const baseParams = [businessId];
  const scopeClause = dataScopeClause(tableName, scope, baseParams);
  if (syncWindow.cursor != null) {
    const params = [...baseParams, syncWindow.cursor];
    const cursorParam = `$${params.length}`;
    return {
      sql: `SELECT *
            FROM ${tableName} t
            WHERE t.business_id = $1${scopeClause}
              AND t.server_revision > ${cursorParam}::bigint
            ORDER BY t.server_revision ASC, t.id ASC`,
      params,
    };
  }

  if (syncWindow.since != null) {
    const params = [...baseParams, syncWindow.since];
    const sinceParam = `$${params.length}`;
    return {
      sql: `SELECT *
            FROM ${tableName} t
            WHERE t.business_id = $1${scopeClause}
              AND t.updated_at > ${sinceParam}
            ORDER BY t.updated_at ASC, t.id ASC`,
      params,
    };
  }

  return {
    sql: `SELECT *
          FROM ${tableName} t
          WHERE t.business_id = $1${scopeClause}
          ORDER BY t.updated_at ASC, t.id ASC`,
    params: baseParams,
  };
}

async function getSnapshotCursor(client, businessId, scope = null) {
  let snapshotCursor = null;
  for (const table of syncTables) {
    const params = [businessId];
    const scopeClause = dataScopeClause(table.name, scope, params);
    const result = await client.query(
      `SELECT MAX(t.server_revision)::text AS snapshot_cursor
       FROM ${table.name} t
       WHERE t.business_id = $1${scopeClause}`,
      params,
    );
    snapshotCursor = maxCursor(
      snapshotCursor,
      result.rows[0]?.snapshot_cursor,
    );
  }
  return normalizeCursor(snapshotCursor);
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
