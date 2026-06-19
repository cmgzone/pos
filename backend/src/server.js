const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const fs = require('fs');
const fsp = require('fs/promises');
const http = require('http');
const path = require('path');
const { Transform } = require('stream');
const { pipeline } = require('stream/promises');
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
  areRecordsEquivalent,
  buildRejectedWriteResult,
  canonicalizeRecord,
  compareTimestamps,
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
  currencyForCountry,
  resolveRequestCountry,
} = require('./geo');
const {
  normalizeSubscriptionPlatform,
  subscriptionProviderAllowedForPlatform,
  selectSubscriptionMarket,
  subscriptionMarketsForPlatform,
} = require('./subscriptionMarkets');
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
  getBusinessWhatsAppConnectStatus,
  createBusinessWhatsAppConnectSession,
  resolveBusinessWhatsAppConnectSession,
  consumeBusinessWhatsAppConnectSession,
  connectBusinessWhatsApp,
  disconnectBusinessWhatsApp,
  sendBusinessMessage,
  listMessageLogs,
} = require('./communication');
const { sendLandingDemoRequestEmail } = require('./landingMailer');
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
const storefrontWebDistDir = path.resolve(__dirname, '..', '..', 'storefront-web', 'dist');
const storefrontWebIndexPath = path.join(storefrontWebDistDir, 'index.html');
const appReleaseUrlPrefix = '/downloads/app';
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
app.use(
  appReleaseUrlPrefix,
  express.static(config.appReleaseDir, {
    index: false,
    setHeaders(res, filePath) {
      const extension = path.extname(filePath).toLowerCase();
      if (extension === '.apk') {
        res.setHeader('Content-Type', 'application/vnd.android.package-archive');
      }
      if (['.apk', '.exe', '.msi', '.zip'].includes(extension)) {
        res.setHeader(
          'Content-Disposition',
          `attachment; filename="${path.basename(filePath).replaceAll('"', '')}"`,
        );
      }
    },
  }),
);

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

app.get('/api/geo/country', (req, res) => {
  const countryCode = resolveRequestCountry(req);
  res.json({ ok: true, countryCode });
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

          // A same-timestamp conflict was applied using server_revision as a
          // tiebreaker. Count it as a conflict for client visibility, but treat
          // the row as applied so the client marks its local copy as synced
          // instead of overwriting it with a stale server row.
          if (result.status === 'conflict_applied') {
            conflictCount[table.name] += 1;
            result.status = 'applied';
          }

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
    res.json({
      ok: true,
      data: appVersionForPlatform(version, req.query?.platform),
    });
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

app.post('/api/platform/app-release/:platform', requirePlatformAdmin, async (req, res, next) => {
  try {
    const platform = normalizeReleasePlatform(req.params.platform);
    const version =
      normalizeOptionalText(req.query?.version) ||
      normalizeOptionalText(req.headers['x-app-version']);
    if (!version) {
      throw createHttpError(400, 'Release version is required before upload.');
    }

    const upload = await saveUploadedAppRelease({
      req,
      platform,
      version,
      originalName:
        normalizeOptionalText(req.query?.fileName) ||
        normalizeOptionalText(req.headers['x-file-name']),
    });
    const current = await loadAppVersionConfig();
    const nextVersion =
      platform === 'android'
        ? {
            ...current,
            latestVersion: version,
            androidVersion: version,
            apkUrl: upload.url,
            androidUrl: upload.url,
          }
        : {
            ...current,
            windowsVersion: version,
            windowsUrl: upload.url,
          };
    const saved = await saveAppVersionConfig(nextVersion);
    res.status(201).json({ ok: true, data: { ...saved, upload } });
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

app.get('/api/business/whatsapp-connect', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const status = await getBusinessWhatsAppConnectStatus(
      businessContext.businessId,
    );
    res.json({ ok: true, data: status });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/business/whatsapp-connect/session', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const status = await getBusinessWhatsAppConnectStatus(
      businessContext.businessId,
    );
    const platform = status.platform || {};
    if (!platform.isActive || !platform.setupReady) {
      throw createHttpError(
        400,
        'WhatsApp setup is not enabled yet. Contact Piki support.',
      );
    }
    if (!platform.oauthRedirectUri) {
      throw createHttpError(
        400,
        'WhatsApp setup redirect is not configured yet. Contact Piki support.',
      );
    }

    const session = await createBusinessWhatsAppConnectSession(
      businessContext.businessId,
      businessContext.deviceId,
    );
    const connectUrl = buildWhatsAppConnectUrl(req, session.token);
    if (!connectUrl) {
      throw createHttpError(
        400,
        'WhatsApp setup link could not be created.',
      );
    }

    res.json({
      ok: true,
      data: {
        connectUrl,
        sessionToken: session.token,
        sessionExpiresAt: session.expiresAt,
        platform,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/business/whatsapp-connect/session/:token', async (req, res, next) => {
  try {
    const session = await resolveBusinessWhatsAppConnectSession(req.params.token);
    if (!session) {
      throw createHttpError(
        401,
        'WhatsApp connection session expired. Start again from Piki POS settings.',
      );
    }
    const status = await getBusinessWhatsAppConnectStatus(session.businessId);
    res.json({
      ok: true,
      data: {
        sessionExpiresAt: session.expiresAt,
        platform: status.platform || {},
        whatsappConnected: status.whatsappConnected,
        whatsappDisplayPhoneNumber: status.whatsappDisplayPhoneNumber,
        whatsappPhoneNumberId: status.whatsappPhoneNumberId,
        whatsappWabaId: status.whatsappWabaId,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/business/whatsapp-connect/complete', async (req, res, next) => {
  try {
    const connectSessionToken = normalizeOptionalText(
      req.body?.connectSession ??
        req.body?.connect_session ??
        req.body?.sessionToken ??
        req.body?.session ??
        req.query?.connectSession,
    );
    if (connectSessionToken) {
      const session = await resolveBusinessWhatsAppConnectSession(
        connectSessionToken,
      );
      if (!session) {
        throw createHttpError(
          401,
          'WhatsApp connection session expired. Start again from Piki POS settings.',
        );
      }
      const settings = await connectBusinessWhatsApp(
        session.businessId,
        req.body || {},
      );
      await consumeBusinessWhatsAppConnectSession(connectSessionToken);
      await invalidateCatalogCache(session.businessId);
      res.json({ ok: true, data: settings });
      return;
    }

    const businessContext = await requireBusinessContext(req);
    const settings = await connectBusinessWhatsApp(
      businessContext.businessId,
      req.body || {},
    );
    await invalidateCatalogCache(businessContext.businessId);
    res.json({ ok: true, data: settings });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.delete('/api/business/whatsapp-connect', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const settings = await disconnectBusinessWhatsApp(
      businessContext.businessId,
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

app.get(
  [
    '/whatsapp/connect',
    '/whatsapp/connect/callback',
    '/whatsapp-connect',
    '/whatsapp-connect/callback',
  ],
  (req, res) => {
    res
      .status(200)
      .type('html')
      .set('Cache-Control', 'no-cache, no-store, must-revalidate')
      .send(renderWhatsAppConnectPage());
  },
);

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
    let notificationSent = false;
    try {
      const notification = await sendLandingDemoRequestEmail(request);
      notificationSent = Boolean(notification.sent);
    } catch (error) {
      console.error('Could not send landing demo request notification:', error.message);
    }
    res.status(201).json({ ok: true, data: request, notificationSent });
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
      .set('Cache-Control', 'no-cache, no-store, must-revalidate');
    try {
      const html = await renderStorefrontSpaPage(catalog);
      res.send(html);
    } catch (spaError) {
      res.send(renderPublicCatalogPage(catalog));
    }
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
      .set('Cache-Control', 'no-cache, no-store, must-revalidate');
    try {
      const html = await renderStorefrontSpaPage(catalog);
      res.send(html);
    } catch (spaError) {
      res.send(renderPublicCatalogPage(catalog));
    }
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/sitemap.xml', (req, res, next) => {
  res.type('application/xml');
  res.sendFile(path.join(landingPageDir, 'sitemap.xml'), (error) => {
    if (error) next(error);
  });
});

app.get('/robots.txt', (req, res, next) => {
  res.type('text/plain');
  res.sendFile(path.join(landingPageDir, 'robots.txt'), (error) => {
    if (error) next(error);
  });
});

app.use(express.static(landingPageDir, { index: false }));
app.use('/landing', express.static(landingPageDir, { index: false }));
app.use('/storefront', express.static(storefrontWebDistDir, { index: false }));

app.get(['/', '/landing'], (req, res, next) => {
  res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.set('Pragma', 'no-cache');
  res.set('Expires', '0');
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
  ensureProductStorefrontSchema(),
  ensureQuotationsSchema(),
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
    throw createHttpError(
      401,
      'M-Pesa callback secret is not configured. Set MPESA_CALLBACK_SECRET before accepting callbacks.',
    );
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
  const amount = Math.max(1, Math.round(payment.amountMinor / 100));
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
    'ALTER TABLE businesses ADD COLUMN IF NOT EXISTS catalog_cover_urls_json jsonb',
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

async function ensureProductStorefrontSchema(target = query) {
  await runDbQuery(
    target,
    'ALTER TABLE products ADD COLUMN IF NOT EXISTS description text',
  );
  await runDbQuery(
    target,
    'ALTER TABLE products ADD COLUMN IF NOT EXISTS image_urls_json text',
  );
  await runDbQuery(
    target,
    'ALTER TABLE products ADD COLUMN IF NOT EXISTS show_online integer NOT NULL DEFAULT 1',
  );
  await runDbQuery(
    target,
    'ALTER TABLE products ADD COLUMN IF NOT EXISTS is_featured integer NOT NULL DEFAULT 0',
  );
}

async function ensureQuotationsSchema(target = query) {
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS quotation_sequences (
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      next_number integer NOT NULL DEFAULT 1,
      PRIMARY KEY (business_id, branch_id)
    )`,
  );
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS quotations (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      quotation_no text NOT NULL,
      customer_id text,
      customer_name text,
      subtotal numeric NOT NULL DEFAULT 0,
      discount_total numeric NOT NULL DEFAULT 0,
      tax_total numeric NOT NULL DEFAULT 0,
      total numeric NOT NULL DEFAULT 0,
      expiry_date text,
      notes text,
      status text NOT NULL DEFAULT 'draft',
      created_by text,
      converted_sale_id text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      deleted_at timestamptz,
      sync_status text NOT NULL DEFAULT 'synced',
      server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq')
    )`,
  );
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS quotation_items (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      quotation_id text NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
      product_id text,
      variant_id text,
      product_name text NOT NULL,
      quantity numeric NOT NULL DEFAULT 0,
      unit text NOT NULL DEFAULT 'pcs',
      unit_price numeric NOT NULL DEFAULT 0,
      discount numeric NOT NULL DEFAULT 0,
      tax numeric NOT NULL DEFAULT 0,
      line_total numeric NOT NULL DEFAULT 0,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      deleted_at timestamptz,
      sync_status text NOT NULL DEFAULT 'synced',
      server_revision bigint NOT NULL DEFAULT nextval('sync_revision_seq')
    )`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_quotations_business_revision
     ON quotations(business_id, server_revision, id)`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_quotation_items_business_revision
     ON quotation_items(business_id, server_revision, id)`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_quotations_status
     ON quotations(business_id, branch_id, status, expiry_date)`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_quotation_items_quotation_id
     ON quotation_items(business_id, quotation_id)`,
  );
  await runDbQuery(
    target,
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_quotations_branch_number_unique
     ON quotations(business_id, branch_id, quotation_no)
     WHERE deleted_at IS NULL`,
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
       catalog_cover_urls_json,
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
  const coverUrls = normalizeStorefrontCoverUrls(
    input.coverUrls ?? input.cover_urls,
    coverUrl,
  );
  const primaryCoverUrl = coverUrls[0] || coverUrl;
  const primaryColor = normalizeStorefrontColor(
    input.primaryColor ?? input.primary_color,
  );
  const tagline = limitText(input.tagline, 80);
  const description = limitText(input.description, 260);

  const result = await query(
    `UPDATE businesses
     SET catalog_logo_url = $2,
         catalog_cover_url = $3,
         catalog_cover_urls_json = $4::jsonb,
         catalog_primary_color = $5,
         catalog_tagline = $6,
         catalog_description = $7,
         updated_at = NOW()
     WHERE id = $1 AND deleted_at IS NULL
     RETURNING
       id,
       name,
       catalog_logo_url,
       catalog_cover_url,
       catalog_cover_urls_json,
       catalog_primary_color,
       catalog_tagline,
       catalog_description,
       updated_at`,
    [
      businessId,
      logoUrl,
      primaryCoverUrl,
      JSON.stringify(coverUrls),
      primaryColor,
      tagline,
      description,
    ],
  );
  if (!result.rows.length) {
    throw createHttpError(404, 'Business was not found');
  }
  return normalizeStorefrontBrandRow(result.rows[0]);
}

function normalizeStorefrontBrandRow(row) {
  const coverUrl = safePublicImageUrl(row.catalog_cover_url);
  const coverUrls = normalizeStoredStorefrontCoverUrls(
    row.catalog_cover_urls_json,
    coverUrl,
  );
  return {
    businessId: row.id,
    businessName: normalizeOptionalText(row.name) || 'Store',
    logoUrl: safePublicImageUrl(row.catalog_logo_url),
    coverUrl: coverUrls[0] || coverUrl,
    coverUrls,
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
  await ensureProductStorefrontSchema(query);
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
           b.catalog_cover_urls_json, b.catalog_tagline, b.catalog_description,
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
      p.description,
      p.image_urls_json,
      p.show_online,
      p.is_featured,
      p.track_stock,
      p.has_variants,
      p.updated_at,
      COALESCE(sales_stats.sold_qty, 0) AS sold_qty,
      COALESCE(sales_stats.sold_revenue, 0) AS sold_revenue,
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
    LEFT JOIN (
      SELECT
        si.product_id,
        SUM(si.quantity) AS sold_qty,
        SUM(si.quantity * si.unit_price) AS sold_revenue
      FROM sale_items si
      JOIN sales s
        ON s.id = si.sale_id
       AND s.business_id = si.business_id
      WHERE si.business_id = $1
        AND si.deleted_at IS NULL
        AND s.deleted_at IS NULL
        AND COALESCE(s.branch_id, 'main_branch') = $2
        AND COALESCE(s.payment_type, '') NOT LIKE 'refund%'
      GROUP BY si.product_id
    ) sales_stats
      ON sales_stats.product_id = p.id
    WHERE p.business_id = $1
      AND p.deleted_at IS NULL
      AND COALESCE(p.show_online, 1) <> 0
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
      p.description,
      p.image_urls_json,
      p.show_online,
      p.is_featured,
      p.track_stock,
      p.has_variants,
      p.updated_at,
      sales_stats.sold_qty,
      sales_stats.sold_revenue,
      c.name
    ORDER BY
      COALESCE(p.is_featured, 0) DESC,
      COALESCE(sales_stats.sold_qty, 0) DESC,
      c.name ASC NULLS LAST,
      p.name ASC
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
      p.show_online,
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
      AND COALESCE(p.show_online, 1) <> 0
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
  const imageUrls = normalizeStoredProductImageUrls(
    row.image_urls_json,
    row.image_url,
  );
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
    description: limitText(row.description, 420),
    unit: normalizeOptionalText(row.sale_unit) || normalizeOptionalText(row.unit) || 'pcs',
    imageUrl: imageUrls[0] || safePublicImageUrl(row.image_url),
    imageUrls,
    isFeatured: Number(row.is_featured || 0) !== 0,
    soldQty: Number(row.sold_qty || 0),
    soldRevenue: Number(row.sold_revenue || 0),
    hasVariants,
    variants,
    availability: available ? 'Available' : 'Ask for availability',
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeStoredProductImageUrls(value, fallbackImageUrl = null) {
  const values = [];
  if (Array.isArray(value)) {
    values.push(...value);
  } else if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) {
        values.push(...parsed);
      } else {
        values.push(value);
      }
    } catch (_) {
      values.push(value);
    }
  }
  if (!values.length && fallbackImageUrl) {
    values.push(fallbackImageUrl);
  }

  const normalized = [];
  const seen = new Set();
  for (const candidate of values) {
    const url = safePublicImageUrl(candidate);
    if (!url || seen.has(url)) continue;
    normalized.push(url);
    seen.add(url);
    if (normalized.length >= 8) break;
  }
  return normalized;
}

function normalizeStorefrontCoverUrls(
  value,
  fallbackCoverUrl = null,
  { throwOnInvalid = true } = {},
) {
  const values = [];
  if (Array.isArray(value)) {
    values.push(...value);
  } else if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) {
        values.push(...parsed);
      } else {
        values.push(value);
      }
    } catch (_) {
      values.push(value);
    }
  }
  if (!values.length && fallbackCoverUrl) {
    values.push(fallbackCoverUrl);
  }

  const normalized = [];
  const seen = new Set();
  for (const candidate of values) {
    let url = null;
    try {
      url = normalizeStorefrontImageUrl(candidate, 'store photo URL');
    } catch (error) {
      if (throwOnInvalid) throw error;
      continue;
    }
    if (!url || seen.has(url)) continue;
    normalized.push(url);
    seen.add(url);
    if (normalized.length >= 8) break;
  }
  return normalized;
}

function normalizeStoredStorefrontCoverUrls(value, fallbackCoverUrl = null) {
  return normalizeStorefrontCoverUrls(value, fallbackCoverUrl, {
    throwOnInvalid: false,
  });
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

let storefrontSpaTemplatePromise = null;

function readStorefrontSpaTemplate() {
  if (!storefrontSpaTemplatePromise) {
    storefrontSpaTemplatePromise = (async () => {
      try {
        const raw = await fsp.readFile(storefrontWebIndexPath, 'utf8');
        return raw;
      } catch (error) {
        storefrontSpaTemplatePromise = null;
        throw error;
      }
    })();
  }
  return storefrontSpaTemplatePromise;
}

function buildStorefrontBootstrapScript(catalog) {
  const businessId = normalizeOptionalText(catalog.business?.id) || '';
  const subdomain =
    normalizeOptionalText(catalog.business?.publicSubdomain) || '';
  const branchId =
    normalizeOptionalText(catalog.business?.selectedBranch?.id) || '';
  const payload = { businessId, subdomain, branchId };
  const safe = JSON.stringify(payload).replace(/</g, '\\u003c');
  const safeCatalog = JSON.stringify(catalog).replace(/</g, '\\u003c');
  return `<script>window.__STOREFRONT__=${safe};window.__STOREFRONT_CATALOG__=${safeCatalog};</script>`;
}

function injectStorefrontMeta(html, catalog) {
  const businessName = normalizeOptionalText(catalog.business?.name) || 'Online Store';
  const brand = catalog.business?.brand || {};
  const primaryColor = normalizeStorefrontColor(brand.primaryColor, {
    fallback: '#111827',
    throwOnInvalid: false,
  });
  const coverUrls = normalizeStoredStorefrontCoverUrls(
    brand.coverUrls,
    safePublicImageUrl(brand.coverUrl),
  );
  const coverUrl = coverUrls[0] || safePublicImageUrl(brand.coverUrl);
  const description =
    normalizeOptionalText(brand.description) ||
    'Shop products and services, choose variants, and send your order directly to the store.';
  const title = `${escapeHtml(businessName)} - Online Store`;

  const headTags = [
    `<title>${title}</title>`,
    `<meta name="description" content="${escapeHtml(description)}" />`,
    `<meta name="theme-color" content="${escapeHtml(primaryColor)}" />`,
    `<meta property="og:title" content="${title}" />`,
    `<meta property="og:description" content="${escapeHtml(description)}" />`,
    `<meta property="og:type" content="website" />`,
    coverUrl
      ? `<meta property="og:image" content="${escapeHtml(coverUrl)}" />`
      : '',
    `<meta name="twitter:card" content="summary_large_image" />`,
    `<meta name="twitter:title" content="${title}" />`,
    `<meta name="twitter:description" content="${escapeHtml(description)}" />`,
    coverUrl
      ? `<meta name="twitter:image" content="${escapeHtml(coverUrl)}" />`
      : '',
    buildStorefrontBootstrapScript(catalog),
  ]
    .filter(Boolean)
    .join('\n  ');

  let updated = html;
  const titleReplaced =
    /<title>[^<]*<\/title>/i.test(updated) &&
    (updated = updated.replace(
      /<title>[^<]*<\/title>/i,
      headTags,
    ));
  if (!titleReplaced) {
    updated = updated.replace(
      /<\/head>/i,
      `  ${headTags}\n</head>`,
    );
  }
  updated = injectStorefrontRootFallback(updated, catalog);
  return updated;
}

async function renderStorefrontSpaPage(catalog) {
  const template = await readStorefrontSpaTemplate();
  return injectStorefrontMeta(template, catalog);
}

function injectStorefrontRootFallback(html, catalog) {
  const fallback = renderStorefrontRootFallback(catalog);
  if (/<div id="root">/i.test(html)) {
    return html.replace(
      /<div id="root">[\s\S]*<\/div>\s*<\/body>/i,
      `${fallback}\n  </body>`,
    );
  }
  return html.replace(/<body([^>]*)>/i, `<body$1>\n    ${fallback}`);
}

function renderStorefrontRootFallback(catalog) {
  const business = catalog.business || {};
  const brand = business.brand || {};
  const businessName = normalizeOptionalText(business.name) || 'Online Store';
  const branchName = normalizeOptionalText(business.selectedBranch?.name);
  const primaryColor = normalizeStorefrontColor(brand.primaryColor, {
    fallback: '#111827',
    throwOnInvalid: false,
  });
  const logoUrl = safePublicImageUrl(brand.logoUrl);
  const coverUrls = normalizeStoredStorefrontCoverUrls(
    brand.coverUrls,
    safePublicImageUrl(brand.coverUrl),
  );
  const tagline = normalizeOptionalText(brand.tagline) || 'Online catalog';
  const description =
    normalizeOptionalText(brand.description) ||
    'Shop products and services, choose variants, and send your order directly to the store.';
  const products = Array.isArray(catalog.products) ? catalog.products : [];
  const visibleItems = products.slice(0, 12);
  const storeInitial = businessName.trim().charAt(0).toUpperCase() || 'P';
  const itemCountLabel =
    products.length === 1 ? '1 item available' : `${products.length} items available`;
  const slideDurationSeconds = Math.max(coverUrls.length * 5, 10);
  const slideWindow = coverUrls.length > 1 ? 100 / coverUrls.length : 100;
  const slideFadePercent = Math.min(6, slideWindow * 0.25);
  const slideVisibleEnd = Math.max(0, slideWindow - slideFadePercent).toFixed(2);
  const slideFadeEnd = slideWindow.toFixed(2);
  const fallbackSlides = coverUrls
    .map(
      (url, index) =>
        `<img src="${escapeHtml(url)}" alt="" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:${index === 0 ? '1' : '0'};transform:scale(1.04);${coverUrls.length > 1 ? `animation:storefrontHeroFade ${slideDurationSeconds}s infinite ease-in-out;animation-delay:${index * 5}s` : ''}">`,
    )
    .join('');

  const productCards = visibleItems
    .map((item) => {
      const name = normalizeOptionalText(item.name) || 'Catalog item';
      const imageUrl = safePublicImageUrl(item.imageUrl);
      const description = limitText(item.description || item.summary, 120);
      const price = formatStorefrontFallbackPrice(item, catalog);
      return `
          <article style="border:1px solid #e5e7eb;border-radius:18px;background:#fff;overflow:hidden;box-shadow:0 10px 24px -18px rgba(15,23,42,.38)">
            <div style="height:150px;background:#f3f4f6;display:grid;place-items:center;color:#9ca3af;font-weight:800">
              ${
                imageUrl
                  ? `<img src="${escapeHtml(imageUrl)}" alt="${escapeHtml(name)}" style="width:100%;height:100%;object-fit:cover" loading="lazy">`
                  : `<span>${escapeHtml(storeInitial)}</span>`
              }
            </div>
            <div style="padding:16px">
              <h2 style="margin:0 0 10px;font-size:17px;line-height:1.25;color:#111827">${escapeHtml(name)}</h2>
              ${description ? `<p style="margin:0 0 10px;color:#6b7280;font-size:13px;line-height:1.45">${escapeHtml(description)}</p>` : ''}
              <strong style="font-size:17px;color:#111827">${escapeHtml(price)}</strong>
            </div>
          </article>`;
    })
    .join('');

  const emptyState = `
        <div style="border:1px dashed #d1d5db;border-radius:22px;background:#fff;padding:36px 24px;text-align:center;color:#6b7280">
          <h2 style="margin:0 0 8px;color:#111827;font-size:22px">No products published yet</h2>
          <p style="margin:0">This store is online. Products will appear here once the business publishes its catalog.</p>
        </div>`;

  return `<div id="root">
    <main data-static-storefront="true" style="min-height:100vh;background:#f6f7f9;color:#111827;font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
      <style>
        @keyframes storefrontHeroFade { 0%, ${slideVisibleEnd}% { opacity: 1; transform: scale(1.08); } ${slideFadeEnd}%, 100% { opacity: 0; transform: scale(1.02); } }
      </style>
      <section style="position:relative;overflow:hidden;background:linear-gradient(135deg,#111827 0%,#1f2937 62%,${escapeHtml(primaryColor)} 150%);color:#fff;padding:46px 20px 58px">
        ${fallbackSlides}
        <div style="position:absolute;inset:0;background:linear-gradient(135deg,rgba(17,24,39,.9),rgba(31,41,55,.72) 55%,rgba(0,0,0,.42));"></div>
        <div style="position:relative;max-width:1120px;margin:0 auto;display:grid;gap:22px">
          <div style="display:flex;align-items:center;gap:16px">
            <div style="width:64px;height:64px;border-radius:20px;background:#fff;display:grid;place-items:center;color:${escapeHtml(primaryColor)};font-weight:900;font-size:24px;overflow:hidden">
              ${
                logoUrl
                  ? `<img src="${escapeHtml(logoUrl)}" alt="${escapeHtml(businessName)} logo" style="width:100%;height:100%;object-fit:cover">`
                  : escapeHtml(storeInitial)
              }
            </div>
            <div>
              <p style="margin:0 0 4px;color:rgba(255,255,255,.72);font-size:13px;font-weight:800;text-transform:uppercase;letter-spacing:.06em">Online Store</p>
              <h1 style="margin:0;font-size:clamp(30px,5vw,56px);line-height:1.02">${escapeHtml(businessName)}</h1>
            </div>
          </div>
          <div style="max-width:720px">
            <p style="margin:0 0 10px;font-size:clamp(18px,2.6vw,26px);font-weight:800">${escapeHtml(tagline)}</p>
            <p style="margin:0;color:rgba(255,255,255,.78);font-size:16px;line-height:1.7">${escapeHtml(description)}</p>
          </div>
          <div style="display:flex;flex-wrap:wrap;gap:10px">
            <span style="border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.1);border-radius:999px;padding:9px 13px;font-size:13px;font-weight:800">${escapeHtml(itemCountLabel)}</span>
            ${
              branchName
                ? `<span style="border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.1);border-radius:999px;padding:9px 13px;font-size:13px;font-weight:800">${escapeHtml(branchName)}</span>`
                : ''
            }
          </div>
        </div>
      </section>
      <section style="max-width:1120px;margin:-28px auto 0;padding:0 20px 48px">
        ${
          visibleItems.length
            ? `<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:18px">${productCards}</div>`
            : emptyState
        }
      </section>
    </main>
  </div>`;
}

function formatStorefrontFallbackPrice(item, catalog) {
  const variants = Array.isArray(item.variants) ? item.variants : [];
  const hasItemPrice =
    item.price !== null &&
    item.price !== undefined &&
    item.price !== '' &&
    Number.isFinite(Number(item.price));
  const amount = hasItemPrice
    ? Number(item.price)
    : Number(variants[0]?.price || 0);
  const currencySymbol = normalizeOptionalText(catalog.currencySymbol);
  const currencyCode = normalizeOptionalText(catalog.currencyCode || catalog.currency) || 'KES';
  if (currencySymbol) {
    return `${currencySymbol}${amount.toLocaleString('en', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })}`;
  }
  try {
    return new Intl.NumberFormat('en', {
      style: 'currency',
      currency: currencyCode,
    }).format(amount);
  } catch (_) {
    return `${currencyCode} ${amount.toLocaleString('en', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })}`;
  }
}

function renderPublicCatalogPage(catalog) {
  const businessName = catalog.business.name || 'Catalog';
  const productCount = catalog.products.length;
  const branchName = catalog.business.selectedBranch?.name || 'Main store';
  const storeInitial = businessName.trim().charAt(0).toUpperCase() || 'P';
  const brand = catalog.business.brand || {};
  const primaryColor = normalizeStorefrontColor(brand.primaryColor, {
    fallback: '#111827',
    throwOnInvalid: false,
  });
  const logoUrl = safePublicImageUrl(brand.logoUrl);
  const coverUrls = normalizeStoredStorefrontCoverUrls(
    brand.coverUrls,
    safePublicImageUrl(brand.coverUrl),
  );
  const coverUrl = coverUrls[0] || safePublicImageUrl(brand.coverUrl);
  const tagline = normalizeOptionalText(brand.tagline) || 'Online store';
  const description =
    normalizeOptionalText(brand.description) ||
    'Shop products and services, choose variants, and send your order directly to the store.';
  const safeCatalogJson = JSON.stringify(catalog).replace(/</g, '\\u003c');
  const whatsappNumber = normalizePublicPhone(catalog.business.whatsappNumber || '');
  const branchCount = Array.isArray(catalog.business.branches)
    ? catalog.business.branches.length
    : 0;
  const serviceCount = catalog.products.filter(
    (item) => item.type === 'service',
  ).length;
  const productOnlyCount = productCount - serviceCount;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0" />
  <meta name="theme-color" content="${escapeHtml(primaryColor)}" />
  <title>${escapeHtml(businessName)} - Online Store</title>
  <meta name="description" content="${escapeHtml(description)}" />
  <meta property="og:title" content="${escapeHtml(businessName)} - Online Store" />
  <meta property="og:description" content="${escapeHtml(description)}" />
  <meta property="og:type" content="website" />
  ${coverUrl ? `<meta property="og:image" content="${escapeHtml(coverUrl)}" />` : ''}
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #f6f7f9;
      --surface: #ffffff;
      --surface-2: #fbfcfd;
      --ink: #0b1220;
      --ink-2: #1f2937;
      --muted: #6b7280;
      --muted-2: #9ca3af;
      --line: #eaecef;
      --line-2: #f1f3f5;
      --primary: ${escapeHtml(primaryColor)};
      --primary-ink: #ffffff;
      --primary-soft: color-mix(in srgb, ${escapeHtml(primaryColor)} 12%, #ffffff);
      --primary-ring: color-mix(in srgb, ${escapeHtml(primaryColor)} 32%, #ffffff);
      --success: #059669;
      --success-soft: #ecfdf5;
      --danger: #dc2626;
      --danger-soft: #fef2f2;
      --warn: #b45309;
      --warn-soft: #fffbeb;
      --star: #f59e0b;
      --radius-xs: 8px;
      --radius-sm: 12px;
      --radius-md: 16px;
      --radius-lg: 22px;
      --radius-xl: 28px;
      --shadow-xs: 0 1px 2px rgba(16,24,40,0.06);
      --shadow-sm: 0 2px 6px rgba(16,24,40,0.06), 0 1px 2px rgba(16,24,40,0.04);
      --shadow-md: 0 8px 20px -6px rgba(16,24,40,0.10), 0 2px 6px rgba(16,24,40,0.06);
      --shadow-lg: 0 24px 48px -12px rgba(16,24,40,0.18), 0 8px 16px -8px rgba(16,24,40,0.10);
      --shadow-floating: 0 32px 64px -16px rgba(16,24,40,0.28);
      --ring: 0 0 0 4px var(--primary-ring);
      --ease: cubic-bezier(0.22, 1, 0.36, 1);
      --wrap: min(1240px, 100% - 32px);
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; -webkit-text-size-adjust: 100%; scroll-padding-top: 150px; }
    body {
      margin: 0;
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: var(--bg);
      color: var(--ink);
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
      padding-bottom: 96px;
      line-height: 1.5;
    }
    img { display: block; max-width: 100%; }
    button { font-family: inherit; }
    a { color: inherit; }
    .wrap { width: var(--wrap); margin: 0 auto; }
    .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0); border: 0; }
    ::selection { background: var(--primary-soft); color: var(--ink); }

    /* Announcement bar */
    .announce {
      background: var(--ink);
      color: #fff;
      font-size: 13px;
      font-weight: 600;
      text-align: center;
      padding: 9px 16px;
      letter-spacing: 0.01em;
    }
    .announce .dot { opacity: .5; padding: 0 10px; }

    /* Top stack: navbar + search + categories move as one sticky unit */
    .top-stack {
      position: sticky;
      top: 0;
      z-index: 50;
      background: var(--surface);
    }

    /* Navbar */
    .navbar {
      background: rgba(255,255,255,0.86);
      backdrop-filter: saturate(180%) blur(14px);
      -webkit-backdrop-filter: saturate(180%) blur(14px);
      border-bottom: 1px solid var(--line);
    }
    .nav-inner {
      display: flex;
      align-items: center;
      gap: 20px;
      height: 68px;
    }
    .brand-lockup {
      display: flex;
      align-items: center;
      gap: 12px;
      text-decoration: none;
      color: var(--ink);
      font-weight: 800;
      font-size: 18px;
      letter-spacing: -0.02em;
      flex-shrink: 0;
    }
    .logo-mark {
      width: 40px;
      height: 40px;
      border-radius: 12px;
      overflow: hidden;
      background: var(--primary);
      color: #fff;
      display: grid;
      place-items: center;
      font-size: 17px;
      font-weight: 800;
      box-shadow: var(--shadow-sm);
      flex-shrink: 0;
    }
    .logo-mark img { width: 100%; height: 100%; object-fit: cover; }
    .brand-meta { display: flex; flex-direction: column; line-height: 1.15; }
    .brand-meta small { font-size: 11px; font-weight: 600; color: var(--muted); letter-spacing: 0.02em; }

    .nav-search {
      flex: 1;
      max-width: 460px;
      position: relative;
      display: flex;
      align-items: center;
    }
    .nav-search input {
      width: 100%;
      background: var(--surface-2);
      border: 1px solid var(--line);
      padding: 11px 16px 11px 42px;
      border-radius: 999px;
      font-size: 14px;
      color: var(--ink);
      outline: none;
      transition: border-color .18s, box-shadow .18s, background .18s;
    }
    .nav-search input::placeholder { color: var(--muted-2); }
    .nav-search input:focus {
      background: #fff;
      border-color: var(--primary);
      box-shadow: 0 0 0 4px var(--primary-ring);
    }
    .nav-search .ic {
      position: absolute;
      left: 14px;
      width: 18px; height: 18px;
      color: var(--muted);
      pointer-events: none;
    }
    .nav-actions { display: flex; align-items: center; gap: 10px; flex-shrink: 0; }
    .icon-btn {
      position: relative;
      background: var(--surface-2);
      border: 1px solid var(--line);
      width: 42px; height: 42px;
      border-radius: 12px;
      display: grid; place-items: center;
      color: var(--ink);
      cursor: pointer;
      transition: background .18s, border-color .18s, transform .18s;
    }
    .icon-btn:hover { background: #fff; border-color: var(--line-2); transform: translateY(-1px); }
    .icon-btn svg { width: 20px; height: 20px; }
    .cart-badge {
      position: absolute;
      top: -6px; right: -6px;
      background: var(--primary);
      color: #fff;
      min-width: 20px; height: 20px;
      border-radius: 10px;
      display: inline-flex; align-items: center; justify-content: center;
      font-size: 11px; font-weight: 800;
      padding: 0 6px;
      border: 2px solid #fff;
      box-shadow: var(--shadow-xs);
    }
    .cart-badge.is-empty { display: none; }

    /* Hero */
    .hero {
      position: relative;
      background: ${coverUrl ? `url('${escapeHtml(coverUrl)}')` : 'linear-gradient(135deg, var(--ink) 0%, #1f2937 60%, var(--primary) 140%)'};
      background-size: cover;
      background-position: center;
      min-height: 420px;
      display: flex;
      align-items: flex-end;
      padding: 64px 0 56px;
      overflow: hidden;
    }
    .hero::before {
      content: '';
      position: absolute; inset: 0;
      background: linear-gradient(to top, rgba(8,12,20,0.86) 0%, rgba(8,12,20,0.42) 45%, rgba(8,12,20,0.18) 100%);
    }
    .hero::after {
      content: '';
      position: absolute; inset: 0;
      background: radial-gradient(120% 80% at 80% 0%, color-mix(in srgb, ${escapeHtml(primaryColor)} 40%, transparent) 0%, transparent 60%);
      mix-blend-mode: screen;
      opacity: .6;
    }
    .hero-content { position: relative; z-index: 10; color: #fff; max-width: 820px; }
    .hero-eyebrow {
      display: inline-flex; align-items: center; gap: 8px;
      background: rgba(255,255,255,0.14);
      border: 1px solid rgba(255,255,255,0.22);
      padding: 7px 14px;
      border-radius: 999px;
      font-size: 12px; font-weight: 700;
      letter-spacing: 0.04em; text-transform: uppercase;
      backdrop-filter: blur(6px);
      margin-bottom: 18px;
    }
    .hero-eyebrow .pulse { width: 7px; height: 7px; border-radius: 50%; background: #34d399; box-shadow: 0 0 0 0 rgba(52,211,153,.7); animation: pulse 2s infinite; }
    @keyframes pulse { 0%{box-shadow:0 0 0 0 rgba(52,211,153,.6)} 70%{box-shadow:0 0 0 8px rgba(52,211,153,0)} 100%{box-shadow:0 0 0 0 rgba(52,211,153,0)} }
    .hero-title {
      font-size: clamp(34px, 6vw, 60px);
      font-weight: 900;
      margin: 0 0 14px;
      line-height: 1.05;
      letter-spacing: -0.03em;
      text-wrap: balance;
    }
    .hero-subtitle {
      font-size: clamp(15px, 2vw, 18px);
      color: rgba(255,255,255,0.86);
      margin: 0 0 26px;
      line-height: 1.55;
      max-width: 620px;
    }
    .hero-stats {
      display: flex; flex-wrap: wrap; gap: 10px;
    }
    .hero-stat {
      display: inline-flex; align-items: center; gap: 8px;
      background: rgba(255,255,255,0.10);
      border: 1px solid rgba(255,255,255,0.18);
      padding: 9px 14px;
      border-radius: 12px;
      font-size: 13px; font-weight: 600;
      color: #fff;
      backdrop-filter: blur(6px);
    }
    .hero-stat svg { width: 16px; height: 16px; opacity: .9; }
    .hero-stat b { font-weight: 800; }

    /* Mobile search (under navbar) */
    .mobile-search { display: none; padding: 12px 0; background: var(--surface); border-bottom: 1px solid var(--line); }
    .mobile-search .nav-search { max-width: none; }

    /* Toolbar (categories + count + sort) */
    .toolbar {
      background: rgba(255,255,255,0.92);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
      border-bottom: 1px solid var(--line);
      padding: 14px 0;
    }
    .toolbar-row { display: flex; align-items: center; gap: 16px; }
    .categories {
      display: flex; gap: 8px;
      overflow-x: auto;
      scrollbar-width: none;
      -webkit-overflow-scrolling: touch;
      padding-bottom: 2px;
      flex: 1;
    }
    .categories::-webkit-scrollbar { display: none; }
    .cat-btn {
      background: var(--surface-2);
      border: 1px solid var(--line);
      padding: 9px 16px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 600;
      color: var(--muted);
      cursor: pointer;
      white-space: nowrap;
      transition: all .18s var(--ease);
      display: inline-flex; align-items: center; gap: 7px;
    }
    .cat-btn .cat-count {
      font-size: 11px; font-weight: 700;
      background: var(--line-2); color: var(--muted);
      padding: 1px 7px; border-radius: 999px;
    }
    .cat-btn:hover:not(.active) { background: #fff; color: var(--ink); border-color: var(--line-2); }
    .cat-btn.active {
      background: var(--ink);
      border-color: var(--ink);
      color: #fff;
    }
    .cat-btn.active .cat-count { background: rgba(255,255,255,0.18); color: #fff; }

    .sort-wrap { position: relative; flex-shrink: 0; }
    .sort-select {
      appearance: none;
      background: var(--surface-2);
      border: 1px solid var(--line);
      padding: 9px 34px 9px 14px;
      border-radius: 10px;
      font-size: 13px; font-weight: 600;
      color: var(--ink);
      cursor: pointer;
      outline: none;
    }
    .sort-select:focus { border-color: var(--primary); box-shadow: 0 0 0 4px var(--primary-ring); }
    .sort-wrap::after {
      content: ''; position: absolute; right: 12px; top: 50%;
      width: 8px; height: 8px;
      border-right: 1.5px solid var(--muted);
      border-bottom: 1.5px solid var(--muted);
      transform: translateY(-65%) rotate(45deg);
      pointer-events: none;
    }

    /* Section heading */
    .section-head {
      display: flex; align-items: flex-end; justify-content: space-between;
      gap: 16px; margin: 40px 0 20px;
    }
    .section-head h2 {
      margin: 0; font-size: 24px; font-weight: 800; letter-spacing: -0.02em;
    }
    .section-head p { margin: 4px 0 0; color: var(--muted); font-size: 14px; }
    .result-count { font-size: 13px; color: var(--muted); font-weight: 600; white-space: nowrap; }

    /* Product grid */
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 20px;
    }
    .card {
      background: var(--surface);
      border-radius: var(--radius-lg);
      overflow: hidden;
      box-shadow: var(--shadow-xs);
      border: 1px solid var(--line);
      display: flex;
      flex-direction: column;
      transition: transform .35s var(--ease), box-shadow .35s var(--ease), border-color .25s;
      cursor: pointer;
      position: relative;
      isolation: isolate;
    }
    .card:hover {
      box-shadow: var(--shadow-lg);
      transform: translateY(-5px);
      border-color: transparent;
    }
    .card-media {
      aspect-ratio: 1 / 1;
      background: linear-gradient(135deg, #f3f4f6, #e9ecef);
      overflow: hidden;
      position: relative;
    }
    .card-media img {
      width: 100%; height: 100%;
      object-fit: cover;
      transition: transform .6s var(--ease);
    }
    .card:hover .card-media img { transform: scale(1.06); }
    .ph-icon {
      position: absolute; inset: 0;
      display: grid; place-items: center;
      color: #c7ccd1;
    }
    .ph-icon svg { width: 38px; height: 38px; }
    .tag-row {
      position: absolute; top: 12px; left: 12px; right: 12px;
      display: flex; justify-content: space-between; gap: 8px;
      pointer-events: none;
    }
    .chip {
      background: rgba(255,255,255,0.92);
      backdrop-filter: blur(6px);
      padding: 5px 10px;
      border-radius: 999px;
      font-size: 11px; font-weight: 700;
      color: var(--ink);
      box-shadow: var(--shadow-xs);
      letter-spacing: 0.02em;
    }
    .chip.cat { background: var(--ink); color: #fff; }
    .chip.unavailable { color: var(--danger); background: rgba(254,242,242,0.95); }
    .chip.service { background: var(--primary-soft); color: var(--primary); }

    .quick-add {
      position: absolute;
      left: 12px; right: 12px; bottom: 12px;
      display: flex; gap: 8px;
      transform: translateY(calc(100% + 12px));
      opacity: 0;
      transition: transform .35s var(--ease), opacity .25s var(--ease);
      pointer-events: none;
    }
    .card:hover .quick-add, .card:focus-within .quick-add { transform: translateY(0); opacity: 1; pointer-events: auto; }
    .quick-add select {
      flex: 1;
      padding: 10px 12px;
      border-radius: 12px;
      border: 1px solid var(--line);
      font-family: inherit;
      font-size: 13px;
      background: #fff;
      color: var(--ink);
      box-shadow: var(--shadow-sm);
      outline: none;
    }
    .quick-add select:focus { border-color: var(--primary); box-shadow: 0 0 0 4px var(--primary-ring); }
    .qa-btn {
      background: var(--ink);
      color: #fff;
      border: none;
      padding: 10px 16px;
      border-radius: 12px;
      font-size: 13px; font-weight: 700;
      cursor: pointer;
      display: inline-flex; align-items: center; gap: 6px;
      box-shadow: var(--shadow-md);
      transition: background .18s, transform .18s;
      white-space: nowrap;
    }
    .qa-btn:hover { background: var(--primary); }
    .qa-btn:active { transform: scale(.96); }
    .qa-btn svg { width: 16px; height: 16px; }

    .card-body { padding: 16px 16px 18px; display: flex; flex-direction: column; flex: 1; gap: 8px; }
    .card-cat { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; font-weight: 700; }
    .card-title {
      font-size: 15px; font-weight: 700; color: var(--ink);
      margin: 0; line-height: 1.35;
      display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical;
      overflow: hidden;
    }
    .card-brand { font-size: 12px; color: var(--muted); font-weight: 600; }
    .card-variant-note { font-size: 12px; color: var(--muted); }
    .card-foot { margin-top: auto; display: flex; align-items: center; justify-content: space-between; gap: 10px; padding-top: 6px; }
    .price-stack { display: flex; flex-direction: column; line-height: 1.1; }
    .price { font-size: 18px; font-weight: 800; color: var(--ink); letter-spacing: -0.01em; }
    .price-sub { font-size: 11px; color: var(--muted); font-weight: 600; }
    .add-round {
      background: var(--ink);
      color: #fff; border: none;
      width: 38px; height: 38px;
      border-radius: 12px;
      display: grid; place-items: center;
      cursor: pointer;
      transition: background .18s, transform .18s;
      box-shadow: var(--shadow-sm);
    }
    .add-round:hover { background: var(--primary); transform: translateY(-1px) scale(1.04); }
    .add-round:active { transform: scale(.94); }
    .add-round svg { width: 18px; height: 18px; }
    .card.is-unavailable { opacity: .92; }
    .card.is-unavailable .add-round { background: var(--muted-2); cursor: not-allowed; }

    /* Empty state */
    .empty {
      display: none;
      text-align: center;
      padding: 80px 20px;
      color: var(--muted);
    }
    .empty .emoji {
      width: 84px; height: 84px; border-radius: 24px;
      background: var(--surface); border: 1px solid var(--line);
      display: grid; place-items: center; margin: 0 auto 18px;
      box-shadow: var(--shadow-sm);
    }
    .empty .emoji svg { width: 38px; height: 38px; color: var(--muted-2); }
    .empty h3 { margin: 0 0 6px; font-size: 18px; color: var(--ink); }
    .empty p { margin: 0; font-size: 14px; }
    .empty .btn-ghost { margin-top: 18px; }

    .btn-ghost {
      background: var(--surface);
      border: 1px solid var(--line);
      padding: 10px 18px;
      border-radius: 999px;
      font-size: 13px; font-weight: 700;
      color: var(--ink);
      cursor: pointer;
      transition: background .18s, border-color .18s;
    }
    .btn-ghost:hover { background: var(--surface-2); border-color: var(--line-2); }

    /* Trust badges */
    .trust {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 16px;
      margin: 48px 0 0;
    }
    .trust-card {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: var(--radius-md);
      padding: 18px;
      display: flex; align-items: center; gap: 14px;
      box-shadow: var(--shadow-xs);
    }
    .trust-ic {
      width: 42px; height: 42px; border-radius: 12px;
      background: var(--primary-soft); color: var(--primary);
      display: grid; place-items: center; flex-shrink: 0;
    }
    .trust-ic svg { width: 22px; height: 22px; }
    .trust-title { font-size: 14px; font-weight: 700; color: var(--ink); }
    .trust-sub { font-size: 12px; color: var(--muted); }

    /* Tracking */
    .panel {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: var(--radius-lg);
      padding: 28px;
      box-shadow: var(--shadow-xs);
    }
    .panel-head { display: flex; align-items: center; gap: 12px; margin-bottom: 18px; }
    .panel-head .pi { width: 40px; height: 40px; border-radius: 12px; background: var(--primary-soft); color: var(--primary); display: grid; place-items: center; }
    .panel-head h3 { margin: 0; font-size: 18px; font-weight: 800; }
    .panel-head p { margin: 2px 0 0; font-size: 13px; color: var(--muted); }
    .track-grid { display: grid; grid-template-columns: 1fr 1fr auto; gap: 12px; align-items: end; }
    .track-result { margin-top: 16px; }
    .status-pill {
      display: inline-flex; align-items: center; gap: 8px;
      padding: 6px 12px; border-radius: 999px;
      font-size: 12px; font-weight: 800; text-transform: uppercase; letter-spacing: 0.04em;
    }
    .status-pill.pending { background: var(--warn-soft); color: var(--warn); }
    .status-pill.accepted { background: #eef2ff; color: #4338ca; }
    .status-pill.payment_requested { background: #e0f2fe; color: #0369a1; }
    .status-pill.fulfilled { background: var(--success-soft); color: var(--success); }
    .status-pill.rejected, .status-pill.cancelled { background: var(--danger-soft); color: var(--danger); }

    /* Footer */
    .site-footer { margin-top: 56px; background: var(--ink); color: #cbd5e1; padding: 48px 0 32px; }
    .footer-grid { display: grid; grid-template-columns: 1.4fr 1fr 1fr 1.2fr; gap: 32px; }
    .footer-brand { display: flex; align-items: center; gap: 12px; margin-bottom: 14px; color: #fff; font-weight: 800; font-size: 18px; }
    .footer-brand .logo-mark { box-shadow: none; }
    .footer-text { font-size: 13px; line-height: 1.6; color: #94a3b8; max-width: 320px; }
    .footer-col h4 { color: #fff; font-size: 13px; text-transform: uppercase; letter-spacing: 0.08em; margin: 0 0 14px; }
    .footer-col a { display: block; color: #94a3b8; text-decoration: none; font-size: 14px; padding: 5px 0; transition: color .15s; }
    .footer-col a:hover { color: #fff; }
    .footer-contact { font-size: 14px; color: #cbd5e1; line-height: 1.7; }
    .footer-contact a { display: inline-flex; align-items: center; gap: 8px; color: #fff; text-decoration: none; font-weight: 700; margin-top: 8px; }
    .footer-bottom { border-top: 1px solid rgba(255,255,255,0.10); margin-top: 32px; padding-top: 20px; display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; font-size: 12px; color: #94a3b8; }
    .footer-bottom a { color: #94a3b8; text-decoration: none; }
    .footer-bottom a:hover { color: #fff; }

    /* Floating cart (mobile) */
    .fab-cart {
      display: none;
      position: fixed;
      bottom: 18px; right: 18px;
      background: var(--ink);
      color: #fff; border: none;
      border-radius: 999px;
      padding: 14px 20px;
      font-weight: 800; font-size: 14px;
      box-shadow: var(--shadow-floating);
      z-index: 40;
      cursor: pointer;
      align-items: center; gap: 10px;
    }
    .fab-cart svg { width: 20px; height: 20px; }
    .fab-cart .cart-badge { position: static; border: none; }

    /* Cart drawer */
    .cart-backdrop {
      position: fixed; inset: 0;
      background: rgba(8,12,20,0.55);
      backdrop-filter: blur(4px);
      z-index: 100;
      opacity: 0; pointer-events: none;
      transition: opacity .3s;
    }
    .cart-backdrop.open { opacity: 1; pointer-events: auto; }
    .cart-drawer {
      position: fixed; top: 0; right: 0; bottom: 0;
      width: min(460px, 100vw);
      background: var(--surface);
      z-index: 101;
      transform: translateX(100%);
      transition: transform .42s var(--ease);
      display: flex; flex-direction: column;
      box-shadow: var(--shadow-floating);
    }
    .cart-drawer.open { transform: translateX(0); }
    .cart-header {
      padding: 20px 22px;
      border-bottom: 1px solid var(--line);
      display: flex; align-items: center; justify-content: space-between; gap: 12px;
    }
    .cart-header h2 { margin: 0; font-size: 20px; font-weight: 800; letter-spacing: -0.02em; }
    .cart-header .sub { font-size: 12px; color: var(--muted); margin-top: 2px; }
    .close-btn {
      background: var(--surface-2); border: 1px solid var(--line);
      width: 36px; height: 36px; border-radius: 10px;
      display: grid; place-items: center;
      color: var(--muted); cursor: pointer; font-size: 20px; line-height: 1;
      transition: background .15s, color .15s;
    }
    .close-btn:hover { background: #fff; color: var(--ink); }

    .ship-bar { padding: 14px 22px; background: var(--surface-2); border-bottom: 1px solid var(--line); }
    .ship-track { height: 8px; background: var(--line-2); border-radius: 999px; overflow: hidden; }
    .ship-fill { height: 100%; background: linear-gradient(90deg, var(--primary), color-mix(in srgb, var(--primary) 60%, #34d399)); border-radius: 999px; transition: width .4s var(--ease); width: 0%; }
    .ship-text { font-size: 12px; color: var(--muted); margin-top: 8px; font-weight: 600; }
    .ship-text b { color: var(--ink); }

    .cart-body {
      flex: 1; overflow-y: auto;
      padding: 20px 22px;
      display: flex; flex-direction: column; gap: 14px;
    }
    .cart-item {
      display: flex; gap: 12px; align-items: center;
      background: var(--surface-2);
      border: 1px solid var(--line);
      border-radius: var(--radius-md);
      padding: 12px;
    }
    .cart-item-img {
      width: 60px; height: 60px;
      border-radius: 10px;
      background: #f3f4f6;
      object-fit: cover; flex-shrink: 0;
    }
    .cart-item-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
    .cart-item-title { font-size: 14px; font-weight: 700; color: var(--ink); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .cart-item-price { font-size: 13px; color: var(--muted); font-weight: 600; }
    .cart-item-actions { display: flex; align-items: center; gap: 8px; }
    .qty {
      display: inline-flex; align-items: center;
      background: #fff; border: 1px solid var(--line);
      border-radius: 999px; padding: 3px;
    }
    .qty-btn {
      width: 26px; height: 26px; border-radius: 50%;
      background: transparent; border: none;
      display: grid; place-items: center;
      cursor: pointer; color: var(--ink); font-size: 16px; font-weight: 700;
      transition: background .15s;
    }
    .qty-btn:hover { background: var(--line-2); }
    .qty-display { font-size: 14px; font-weight: 700; min-width: 22px; text-align: center; }
    .remove-btn {
      background: transparent; border: none; color: var(--muted-2);
      cursor: pointer; width: 26px; height: 26px; display: grid; place-items: center;
      border-radius: 8px; transition: color .15s, background .15s;
    }
    .remove-btn:hover { color: var(--danger); background: var(--danger-soft); }
    .remove-btn svg { width: 16px; height: 16px; }

    .cart-empty-state { text-align: center; padding: 56px 20px; color: var(--muted); }
    .cart-empty-state .ce-ic { width: 76px; height: 76px; border-radius: 22px; background: var(--surface-2); border: 1px solid var(--line); display: grid; place-items: center; margin: 0 auto 16px; }
    .cart-empty-state .ce-ic svg { width: 34px; height: 34px; color: var(--muted-2); }
    .cart-empty-state h4 { margin: 0 0 6px; font-size: 16px; color: var(--ink); }
    .cart-empty-state p { margin: 0 0 18px; font-size: 13px; }

    /* Checkout form */
    .checkout-form { display: flex; flex-direction: column; gap: 14px; }
    .form-group { display: flex; flex-direction: column; gap: 6px; }
    .form-group label { font-size: 12px; font-weight: 700; color: var(--ink-2); letter-spacing: 0.01em; }
    .form-input {
      padding: 12px 14px;
      border-radius: 12px;
      border: 1px solid var(--line);
      font-family: inherit; font-size: 14px;
      background: #fff; color: var(--ink);
      transition: border-color .18s, box-shadow .18s;
    }
    .form-input::placeholder { color: var(--muted-2); }
    .form-input:focus { outline: none; border-color: var(--primary); box-shadow: 0 0 0 4px var(--primary-ring); }
    textarea.form-input { min-height: 76px; resize: vertical; }
    .radio-group { display: flex; gap: 10px; }
    .radio-label {
      flex: 1; display: flex; align-items: center; justify-content: center; gap: 8px;
      padding: 12px;
      border: 1px solid var(--line);
      border-radius: 12px;
      cursor: pointer; font-weight: 700; font-size: 13px;
      background: #fff; color: var(--muted);
      transition: all .18s;
    }
    .radio-label svg { width: 16px; height: 16px; }
    .radio-label:has(input:checked) { border-color: var(--ink); background: var(--ink); color: #fff; }
    .radio-label input { display: none; }

    .summary { display: flex; flex-direction: column; gap: 8px; padding: 16px; background: var(--surface-2); border: 1px solid var(--line); border-radius: var(--radius-md); }
    .summary-row { display: flex; justify-content: space-between; font-size: 13px; color: var(--muted); }
    .summary-row.total { font-size: 16px; font-weight: 800; color: var(--ink); padding-top: 10px; border-top: 1px dashed var(--line); margin-top: 4px; }

    .cart-footer { padding: 18px 22px 22px; border-top: 1px solid var(--line); background: var(--surface); }
    .cart-foot-total { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; font-size: 15px; font-weight: 800; }
    .cart-foot-total .lbl { color: var(--muted); font-weight: 700; }
    .checkout-btn {
      width: 100%; padding: 15px;
      background: var(--ink); color: #fff; border: none;
      border-radius: 14px;
      font-size: 15px; font-weight: 800;
      cursor: pointer;
      transition: transform .12s, background .18s, box-shadow .18s;
      display: inline-flex; align-items: center; justify-content: center; gap: 8px;
      box-shadow: var(--shadow-sm);
    }
    .checkout-btn:hover { background: var(--primary); box-shadow: var(--shadow-md); }
    .checkout-btn:active { transform: scale(.98); }
    .checkout-btn:disabled { background: var(--muted-2); cursor: not-allowed; box-shadow: none; transform: none; }
    .checkout-btn svg { width: 18px; height: 18px; }
    .whatsapp-btn {
      display: none;
      width: 100%; padding: 13px;
      background: #25D366; color: #fff; border: none;
      border-radius: 14px;
      font-size: 14px; font-weight: 800; cursor: pointer;
      text-align: center; text-decoration: none; margin-top: 10px;
      transition: opacity .18s;
    }
    .whatsapp-btn:hover { opacity: .92; }
    .secure-note { display: flex; align-items: center; justify-content: center; gap: 6px; margin-top: 12px; font-size: 11px; color: var(--muted); }
    .secure-note svg { width: 13px; height: 13px; }

    /* Alerts inside drawer */
    .alert { padding: 14px 16px; border-radius: 12px; font-size: 13px; font-weight: 600; display: none; gap: 10px; align-items: flex-start; }
    .alert svg { width: 18px; height: 18px; flex-shrink: 0; margin-top: 1px; }
    .alert-success { background: var(--success-soft); color: #065f46; border: 1px solid #a7f3d0; }
    .alert-error { background: var(--danger-soft); color: #991b1b; border: 1px solid #fecaca; }

    /* Toast */
    .toast-wrap { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); z-index: 200; display: flex; flex-direction: column; gap: 10px; align-items: center; pointer-events: none; }
    .toast {
      background: var(--ink); color: #fff;
      padding: 12px 18px; border-radius: 999px;
      font-size: 13px; font-weight: 600;
      box-shadow: var(--shadow-lg);
      display: inline-flex; align-items: center; gap: 10px;
      opacity: 0; transform: translateY(12px) scale(.96);
      transition: opacity .25s, transform .25s var(--ease);
      max-width: 90vw;
    }
    .toast.show { opacity: 1; transform: translateY(0) scale(1); }
    .toast svg { width: 16px; height: 16px; color: #34d399; }
    .toast.error svg { color: #fca5a5; }

    /* Skeleton shimmer (brief, before init) */
    .skeleton-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 20px; }
    .skel-card { background: var(--surface); border: 1px solid var(--line); border-radius: var(--radius-lg); overflow: hidden; }
    .skel-media { aspect-ratio: 1/1; background: linear-gradient(90deg, #eef0f3 25%, #f6f7f9 37%, #eef0f3 63%); background-size: 400% 100%; animation: shimmer 1.4s infinite; }
    .skel-line { height: 12px; border-radius: 6px; background: #eef0f3; margin: 12px 16px; }
    .skel-line.short { width: 50%; }
    @keyframes shimmer { 0%{background-position:100% 0} 100%{background-position:-100% 0} }

    @media (max-width: 920px) {
      .footer-grid { grid-template-columns: 1fr 1fr; gap: 24px; }
      .trust { grid-template-columns: 1fr 1fr; }
    }
    @media (max-width: 768px) {
      .nav-search { display: none; }
      .mobile-search { display: block; }
      .hero { min-height: 340px; padding: 48px 0 40px; }
      .hero-title { font-size: 30px; }
      .grid { grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 14px; }
      .card-body { padding: 12px; }
      .card-title { font-size: 13px; }
      .price { font-size: 15px; }
      .add-round { width: 34px; height: 34px; }
      .quick-add { transform: translateY(0); opacity: 1; position: static; padding: 0; display: none; }
      .fab-cart { display: inline-flex; }
      .icon-btn.cart-btn { display: none; }
      .section-head h2 { font-size: 20px; }
      .panel { padding: 20px; }
      .track-grid { grid-template-columns: 1fr; }
      .sort-wrap { display: none; }
    }
    @media (max-width: 480px) {
      .footer-grid { grid-template-columns: 1fr; }
      .trust { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>

  <!-- Announcement bar -->
  <div class="announce">
    <span>Free local delivery on orders above a reasonable amount</span><span class="dot">-</span><span>Order now, pay on confirmation</span><span class="dot">-</span><span>Track your order online</span>
  </div>

  <!-- Top stack: navbar + search + categories (one sticky unit) -->
  <div class="top-stack">
    <!-- Navbar -->
    <header class="navbar">
      <div class="wrap nav-inner">
        <a href="#" class="brand-lockup" aria-label="${escapeHtml(businessName)}">
          <div class="logo-mark">
            ${logoUrl ? `<img src="${escapeHtml(logoUrl)}" alt="${escapeHtml(businessName)} logo" />` : escapeHtml(storeInitial)}
          </div>
          <span class="brand-meta">
            <span>${escapeHtml(businessName)}</span>
            <small>Online Store${branchCount > 1 ? ' - ' + escapeHtml(branchName) : ''}</small>
          </span>
        </a>
        <div class="nav-search">
          <svg class="ic" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
          <input type="text" id="search-input" placeholder="Search products, brands..." onkeyup="handleSearch()" />
        </div>
        <div class="nav-actions">
          <button class="icon-btn" onclick="document.getElementById('track-order').scrollIntoView({behavior:'smooth'})" aria-label="Track order">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l5.553 2.776A1 1 0 0021 18.882V8.118a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"></path></svg>
          </button>
          <button class="icon-btn cart-btn" onclick="toggleCart()" aria-label="Open cart">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"></path></svg>
            <span class="cart-badge is-empty" id="nav-cart-count">0</span>
          </button>
        </div>
      </div>
    </header>

    <!-- Mobile search -->
    <div class="mobile-search">
      <div class="wrap">
        <div class="nav-search">
          <svg class="ic" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
          <input type="text" id="search-input-mobile" placeholder="Search products, brands..." onkeyup="handleSearch()" />
        </div>
      </div>
    </div>

    <!-- Toolbar: categories + sort -->
    <div class="toolbar">
      <div class="wrap toolbar-row">
        <div class="categories" id="category-pills">
          <button class="cat-btn active" onclick="setCategory('all', this)">All Items</button>
        </div>
        <div class="sort-wrap">
          <select class="sort-select" id="sort-select" onchange="handleSort()">
            <option value="featured">Featured</option>
            <option value="price-asc">Price: Low to High</option>
            <option value="price-desc">Price: High to Low</option>
            <option value="name-asc">Name: A - Z</option>
            <option value="name-desc">Name: Z - A</option>
          </select>
        </div>
      </div>
    </div>
  </div>

  <!-- Hero -->
  <section class="hero">
    <div class="wrap hero-content">
      <span class="hero-eyebrow"><span class="pulse"></span> Store open - accepting orders</span>
      <h1 class="hero-title">${escapeHtml(businessName)}</h1>
      <p class="hero-subtitle">${escapeHtml(tagline)}</p>
      <div class="hero-stats">
        <span class="hero-stat"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4"></path></svg> <b>${productOnlyCount}</b> products</span>
        ${serviceCount > 0 ? `<span class="hero-stat"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"></path><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"></path></svg> <b>${serviceCount}</b> services</span>` : ''}
        ${branchCount > 1 ? `<span class="hero-stat"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"></path><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"></path></svg> ${escapeHtml(branchName)}</span>` : ''}
        ${whatsappNumber ? `<span class="hero-stat"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"></path></svg> Chat support</span>` : ''}
      </div>
    </div>
  </section>

  <!-- Catalog -->
  <main class="wrap" style="padding-top: 40px;">
    <div class="section-head" id="catalog-head">
      <div>
        <h2 id="section-title">All Items</h2>
        <p>Browse the catalog and add what you love.</p>
      </div>
      <span class="result-count" id="result-count"></span>
    </div>

    <div class="skeleton-grid" id="skeleton">
      ${Array.from({ length: 8 }).map(() => `<div class="skel-card"><div class="skel-media"></div><div class="skel-line"></div><div class="skel-line short"></div></div>`).join('')}
    </div>

    <div class="empty" id="empty-state">
      <div class="emoji"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.6" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"></path></svg></div>
      <h3>No items found</h3>
      <p>Try a different search term or category.</p>
      <button class="btn-ghost" onclick="clearFilters()">Clear filters</button>
    </div>

    <div class="grid" id="product-grid" style="display:none;"></div>

    <!-- Trust badges -->
    <div class="trust">
      <div class="trust-card">
        <div class="trust-ic"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" d="M9 17a2 2 0 11-4 0 2 2 0 014 0zM19 18a2 2 0 11-4 0 2 2 0 014 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 2a2 2 0 104 0m-4 0a2 2 0 114 0"/></svg></div>
        <div><div class="trust-title">Fast delivery</div><div class="trust-sub">Quick turn-around on every order</div></div>
      </div>
      <div class="trust-card">
        <div class="trust-ic"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/></svg></div>
        <div><div class="trust-title">Secure ordering</div><div class="trust-sub">Pay only after confirmation</div></div>
      </div>
      <div class="trust-card">
        <div class="trust-ic"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"/></svg></div>
        <div><div class="trust-title">Direct support</div><div class="trust-sub">Talk to the store on WhatsApp</div></div>
      </div>
      <div class="trust-card">
        <div class="trust-ic"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"/></svg></div>
        <div><div class="trust-title">Easy pickup</div><div class="trust-sub">Choose delivery or in-store pickup</div></div>
      </div>
    </div>

    <!-- Order tracking -->
    <section class="panel" id="track-order" style="margin-top: 40px; scroll-margin-top: 150px;">
      <div class="panel-head">
        <div class="pi"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l5.553 2.776A1 1 0 0021 18.882V8.118a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"/></svg></div>
        <div><h3>Track your order</h3><p>Enter your order number and phone to check status.</p></div>
      </div>
      <form id="tracking-form" class="track-grid" onsubmit="trackOrder(event)">
        <div class="form-group">
          <label>Order Number</label>
          <input id="tracking-order-number" class="form-input" required placeholder="e.g. A1B2C3D4">
        </div>
        <div class="form-group">
          <label>Phone Number</label>
          <input id="tracking-phone" class="form-input" required placeholder="+254...">
        </div>
        <button type="submit" id="track-btn" class="checkout-btn" style="padding: 12px 22px; width: auto;">Track Order</button>
      </form>
      <div id="tracking-result" class="track-result alert" style="display:none;"></div>
    </section>
  </main>

  <!-- Footer -->
  <footer class="site-footer">
    <div class="wrap">
      <div class="footer-grid">
        <div>
          <div class="footer-brand">
            <div class="logo-mark">${logoUrl ? `<img src="${escapeHtml(logoUrl)}" alt="" />` : escapeHtml(storeInitial)}</div>
            <span>${escapeHtml(businessName)}</span>
          </div>
          <p class="footer-text">${escapeHtml(description)}</p>
        </div>
        <div class="footer-col">
          <h4>Shop</h4>
          <a href="#" onclick="setCategoryAll();return false;">All items</a>
          <a href="#track-order">Track order</a>
          <a href="#" onclick="toggleCart();return false;">View cart</a>
        </div>
        <div class="footer-col">
          <h4>Support</h4>
          <a href="#">How ordering works</a>
          <a href="#">Delivery & pickup</a>
          <a href="#">Returns</a>
        </div>
        <div class="footer-col">
          <h4>Contact</h4>
          <div class="footer-contact">
            ${escapeHtml(businessName)}<br>
            ${escapeHtml(branchName)}<br>
            ${whatsappNumber ? `<a href="https://wa.me/${escapeHtml(whatsappNumber.replace(/\\D/g, ''))}" target="_blank" rel="noopener"><svg width="16" height="16" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z"/></svg> Chat on WhatsApp</a>` : ''}
          </div>
        </div>
      </div>
      <div class="footer-bottom">
        <span>&copy; ${new Date().getFullYear()} ${escapeHtml(businessName)}. All rights reserved.</span>
        <span>Powered by <a href="#" rel="noopener">Piki POS</a></span>
      </div>
    </div>
  </footer>

  <!-- Floating cart (mobile) -->
  <button class="fab-cart" onclick="toggleCart()">
    <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"/></svg>
    View Cart <span class="cart-badge is-empty" id="fab-cart-count">0</span>
  </button>

  <!-- Toasts -->
  <div class="toast-wrap" id="toast-wrap"></div>

  <!-- Cart drawer -->
  <div class="cart-backdrop" id="cart-backdrop" onclick="toggleCart()"></div>
  <aside class="cart-drawer" id="cart-drawer" aria-label="Shopping cart">
    <div class="cart-header">
      <div>
        <h2>Your Cart</h2>
        <div class="sub" id="cart-item-count-text">0 items</div>
      </div>
      <button class="close-btn" onclick="toggleCart()" aria-label="Close cart">&times;</button>
    </div>

    <div class="ship-bar" id="ship-bar" style="display:none;">
      <div class="ship-track"><div class="ship-fill" id="ship-fill"></div></div>
      <div class="ship-text" id="ship-text"></div>
    </div>

    <div class="cart-body" id="cart-body">
      <div class="cart-empty-state" id="cart-empty-state">
        <div class="ce-ic"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z"/></svg></div>
        <h4>Your cart is empty</h4>
        <p>Add items from the catalog to get started.</p>
        <button class="btn-ghost" onclick="toggleCart()">Browse catalog</button>
      </div>

      <div id="checkout-section" style="display:none;">
        <div id="alert-success" class="alert alert-success"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg><div id="alert-success-text">Order placed successfully!</div></div>
        <div id="alert-error" class="alert alert-error"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg><div id="alert-error-text">Something went wrong.</div></div>

        <form id="order-form" class="checkout-form" onsubmit="submitOrder(event)" style="margin-top: 4px;">
          <div class="form-group">
            <label>Full name</label>
            <input type="text" id="customer-name" class="form-input" required placeholder="John Doe">
          </div>
          <div class="form-group">
            <label>Phone number</label>
            <input type="tel" id="customer-phone" class="form-input" required placeholder="+254...">
          </div>
          <div class="radio-group">
            <label class="radio-label"><input type="radio" name="fulfillment" value="delivery" checked><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 17a2 2 0 11-4 0 2 2 0 014 0zM19 18a2 2 0 11-4 0 2 2 0 014 0z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1"/></svg> Delivery</label>
            <label class="radio-label"><input type="radio" name="fulfillment" value="pickup"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"/></svg> Pickup</label>
          </div>
          <div class="form-group">
            <label>Address / note</label>
            <textarea id="order-note" class="form-input" placeholder="Delivery instructions, landmark, etc."></textarea>
          </div>
        </form>
      </div>
    </div>

    <div class="cart-footer" id="cart-footer">
      <div class="cart-foot-total"><span class="lbl">Subtotal</span><span id="cart-total-display">0</span></div>
      <button class="checkout-btn" id="checkout-btn" onclick="document.getElementById('order-form').requestSubmit()" disabled>
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
        Place Order
      </button>
      <a href="#" class="whatsapp-btn" id="whatsapp-btn" target="_blank" rel="noopener">Send order via WhatsApp</a>
      <div class="secure-note"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/></svg> You only pay after the store confirms your order.</div>
    </div>
  </aside>

  <!-- Data + logic -->
  <script id="catalog-data" type="application/json">${safeCatalogJson}</script>
  <script>
    const catalog = JSON.parse(document.getElementById('catalog-data').textContent);
    const shopWhatsApp = '${escapeHtml(whatsappNumber)}';
    const FREE_SHIP_THRESHOLD = 0; // informational only; store confirms totals

    const state = {
      cart: new Map(),
      activeCategory: 'all',
      searchQuery: '',
      sort: 'featured',
      isCartOpen: false
    };

    const els = {
      grid: document.getElementById('product-grid'),
      skeleton: document.getElementById('skeleton'),
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
      cartFooter: document.getElementById('cart-footer'),
      checkoutBtn: document.getElementById('checkout-btn'),
      whatsappBtn: document.getElementById('whatsapp-btn'),
      alertSuccess: document.getElementById('alert-success'),
      alertSuccessText: document.getElementById('alert-success-text'),
      alertError: document.getElementById('alert-error'),
      alertErrorText: document.getElementById('alert-error-text'),
      searchInput: document.getElementById('search-input'),
      searchInputMobile: document.getElementById('search-input-mobile'),
      sortSelect: document.getElementById('sort-select'),
      resultCount: document.getElementById('result-count'),
      sectionTitle: document.getElementById('section-title'),
      itemCountText: document.getElementById('cart-item-count-text'),
      shipBar: document.getElementById('ship-bar'),
      shipFill: document.getElementById('ship-fill'),
      shipText: document.getElementById('ship-text'),
      toastWrap: document.getElementById('toast-wrap')
    };

    const currencyCode = catalog.currencyCode || catalog.currency || 'KES';
    const currencySymbol = String(catalog.currencySymbol || '').trim();
    const formatMoney = (amount) => {
      amount = Number(amount || 0);
      if (currencySymbol) {
        return currencySymbol + amount.toLocaleString('en', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      }
      try { return new Intl.NumberFormat('en', { style: 'currency', currency: currencyCode }).format(amount); }
      catch (_) { return currencyCode + ' ' + amount.toLocaleString('en', { minimumFractionDigits: 2 }); }
    };

    const safeHtml = (str) => String(str || '').replace(/[&<>"']/g, m => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' })[m]);

    function showToast(msg, type) {
      const t = document.createElement('div');
      t.className = 'toast' + (type === 'error' ? ' error' : '');
      const ic = type === 'error'
        ? '<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg>'
        : '<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>';
      t.innerHTML = ic + '<span>' + safeHtml(msg) + '</span>';
      els.toastWrap.appendChild(t);
      requestAnimationFrame(() => t.classList.add('show'));
      setTimeout(() => { t.classList.remove('show'); setTimeout(() => t.remove(), 300); }, 2600);
    }

    function init() {
      const cats = new Map();
      catalog.products.forEach(item => {
        const c = (item.category && item.category !== 'Services') ? item.category : (item.type === 'service' ? 'Services' : 'Other');
        cats.set(c, (cats.get(c) || 0) + 1);
      });
      const sortedCats = Array.from(cats.keys()).sort((a, b) => a.localeCompare(b));
      sortedCats.forEach(c => {
        const btn = document.createElement('button');
        btn.className = 'cat-btn';
        btn.innerHTML = safeHtml(c) + '<span class="cat-count">' + cats.get(c) + '</span>';
        btn.onclick = () => setCategory(c, btn);
        els.catPills.appendChild(btn);
      });

      // hide skeleton, show grid
      setTimeout(() => {
        els.skeleton.style.display = 'none';
        els.grid.style.display = 'grid';
        renderGrid();
        renderCart();
      }, 250);
    }

    function handleSearch() {
      const val = (els.searchInput && els.searchInput === document.activeElement ? els.searchInput.value : (els.searchInputMobile ? els.searchInputMobile.value : ''));
      state.searchQuery = (val || '').toLowerCase().trim();
      if (els.searchInput) els.searchInput.value = val;
      if (els.searchInputMobile) els.searchInputMobile.value = val;
      renderGrid();
    }

    function handleSort() {
      state.sort = els.sortSelect.value;
      renderGrid();
    }

    function setCategory(cat, btnElement) {
      state.activeCategory = cat;
      document.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
      if (btnElement) btnElement.classList.add('active');
      else document.querySelectorAll('.cat-btn').forEach(b => { if (b.textContent.replace(/[0-9 ]/g,'').trim() === cat) b.classList.add('active'); });
      els.sectionTitle.textContent = cat === 'all' ? 'All Items' : cat;
      renderGrid();
      document.getElementById('catalog-head').scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
    function setCategoryAll() {
      const first = document.querySelector('.cat-btn');
      if (first) setCategory('all', first);
    }
    function clearFilters() {
      state.searchQuery = '';
      if (els.searchInput) els.searchInput.value = '';
      if (els.searchInputMobile) els.searchInputMobile.value = '';
      setCategoryAll();
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
      let items = catalog.products.filter(item => {
        const cat = (item.category && item.category !== 'Services') ? item.category : (item.type === 'service' ? 'Services' : 'Other');
        const matchCat = state.activeCategory === 'all' || cat === state.activeCategory;
        const matchSearch = !state.searchQuery || item.name.toLowerCase().includes(state.searchQuery) || (item.brand || '').toLowerCase().includes(state.searchQuery) || cat.toLowerCase().includes(state.searchQuery);
        return matchCat && matchSearch;
      });
      switch (state.sort) {
        case 'price-asc': items.sort((a,b) => Number(a.price||0) - Number(b.price||0)); break;
        case 'price-desc': items.sort((a,b) => Number(b.price||0) - Number(a.price||0)); break;
        case 'name-asc': items.sort((a,b) => String(a.name||'').localeCompare(String(b.name||''))); break;
        case 'name-desc': items.sort((a,b) => String(b.name||'').localeCompare(String(a.name||''))); break;
      }
      return items;
    }

    function renderGrid() {
      const items = getItems();
      els.grid.innerHTML = '';
      els.resultCount.textContent = items.length + ' item' + (items.length === 1 ? '' : 's');

      if (items.length === 0) {
        els.empty.style.display = 'block';
        els.grid.style.display = 'none';
        return;
      }
      els.empty.style.display = 'none';
      els.grid.style.display = 'grid';

      items.forEach(item => {
        const isAvailable = item.availability === 'Available';
        const isService = item.type === 'service';
        const cat = (item.category && item.category !== 'Services') ? item.category : (isService ? 'Services' : 'Other');

        const img = item.imageUrl
          ? \`<img src="\${safeHtml(item.imageUrl)}" loading="lazy" alt="\${safeHtml(item.name)}">\`
          : \`<div class="ph-icon"><svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.6" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg></div>\`;

        let variantsHtml = '';
        let primaryPrice = item.price;
        let variantOptions = '';
        if (item.hasVariants && item.variants && item.variants.length > 0) {
          primaryPrice = item.variants[0].price;
          variantOptions = item.variants.map((v, i) => \`<option value="\${v.id}" data-price="\${v.price}" \${i===0?'selected':''}>\${safeHtml(v.name)} - \${formatMoney(v.price)}</option>\`).join('');
          variantsHtml = \`<div class="quick-add" onclick="event.stopPropagation()"><select id="var-\${item.id}" onchange="updatePrice('\${item.id}', this.options[this.selectedIndex].dataset.price)">\${variantOptions}</select></div>\`;
        }

        const priceId = \`price-\${item.id}\`;
        const card = document.createElement('div');
        card.className = 'card' + (isAvailable ? '' : ' is-unavailable');
        card.onclick = (e) => {
          if (e.target.closest('.quick-add') || e.target.closest('.add-round')) return;
          if (item.hasVariants && item.variants && item.variants.length > 0) {
            // require variant choice via quick add on hover devices; on mobile tap the + button
            return;
          }
          addToCart(item, null);
        };

        const tags = [];
        if (isService) tags.push('<span class="chip service">Service</span>');
        else if (item.category) tags.push('<span class="chip cat">' + safeHtml(item.category) + '</span>');
        if (!isAvailable) tags.push('<span class="chip unavailable">Ask for availability</span>');

        card.innerHTML = \`
          <div class="card-media">
            \${img}
            <div class="tag-row">\${tags.join('')}</div>
            \${variantsHtml}
          </div>
          <div class="card-body">
            \${item.brand && item.brand !== 'Service' ? \`<div class="card-brand">\${safeHtml(item.brand)}</div>\` : ''}
            <h3 class="card-title">\${safeHtml(item.name)}</h3>
            \${item.hasVariants && !variantOptions ? '<div class="card-variant-note">Multiple options</div>' : ''}
            <div class="card-foot">
              <div class="price-stack">
                <span class="price" id="\${priceId}">\${formatMoney(primaryPrice)}</span>
                <span class="price-sub">\${isService ? 'per service' : (item.unit ? safeHtml(item.unit) : 'each')}</span>
              </div>
              <button class="add-round" onclick="event.stopPropagation(); quickAdd('\${item.id}')" aria-label="Add to cart">
                <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.2" d="M12 4v16m8-8H4"/></svg>
              </button>
            </div>
          </div>
        \`;
        els.grid.appendChild(card);
      });
    }

    window.updatePrice = (itemId, newPrice) => {
      const priceEl = document.getElementById(\`price-\${itemId}\`);
      if (priceEl) priceEl.textContent = formatMoney(newPrice);
    };

    window.quickAdd = (itemId) => {
      const item = catalog.products.find(p => String(p.id) === String(itemId));
      if (!item) return;
      let variantId = null;
      if (item.hasVariants && item.variants && item.variants.length > 0) {
        const sel = document.getElementById('var-' + item.id);
        if (sel) variantId = sel.value;
      }
      addToCart(item, variantId);
    };

    function cartKey(item, variantId) { return item.id + ':' + (variantId || ''); }

    function addToCart(item, variantId) {
      if (item.availability !== 'Available') {
        showToast('This item is not available right now', 'error');
        return;
      }
      const key = cartKey(item, variantId);
      const existing = state.cart.get(key);
      let variant = null;
      if (variantId && item.variants) variant = item.variants.find(v => v.id === variantId);
      state.cart.set(key, { item, variant, qty: existing ? existing.qty + 1 : 1 });

      els.alertSuccess.style.display = 'none';
      els.alertError.style.display = 'none';
      els.whatsappBtn.style.display = 'none';
      els.checkoutBtn.style.display = 'inline-flex';

      renderCart();
      showToast(variant ? (item.name + ' (' + variant.name + ') added') : (item.name + ' added'));
      if (window.innerWidth <= 768) toggleCart();
    }

    function updateQty(key, delta) {
      const existing = state.cart.get(key);
      if (!existing) return;
      const newQty = existing.qty + delta;
      if (newQty <= 0) state.cart.delete(key);
      else existing.qty = newQty;
      renderCart();
    }
    function removeItem(key) {
      state.cart.delete(key);
      renderCart();
    }
    window.removeItem = removeItem;
    window.updateQty = updateQty;

    function renderCart() {
      const items = Array.from(state.cart.values());
      const totalQty = items.reduce((sum, i) => sum + i.qty, 0);
      els.navCount.textContent = totalQty;
      els.fabCount.textContent = totalQty;
      els.navCount.classList.toggle('is-empty', totalQty === 0);
      els.fabCount.classList.toggle('is-empty', totalQty === 0);
      els.itemCountText.textContent = totalQty + ' item' + (totalQty === 1 ? '' : 's');

      document.querySelectorAll('.cart-item').forEach(n => n.remove());
      let totalValue = 0;

      if (items.length === 0) {
        els.cartEmpty.style.display = 'block';
        els.checkoutSec.style.display = 'none';
        els.cartFooter.style.display = 'none';
        els.shipBar.style.display = 'none';
        els.cartTotal.textContent = formatMoney(0);
        return;
      }
      els.cartEmpty.style.display = 'none';
      els.checkoutSec.style.display = 'block';
      els.cartFooter.style.display = 'block';
      els.checkoutBtn.disabled = false;

      items.forEach(cartEntry => {
        const { item, variant, qty } = cartEntry;
        const key = cartKey(item, variant ? variant.id : null);
        const price = variant ? variant.price : item.price;
        const title = variant ? \`\${item.name} (\${variant.name})\` : item.name;
        totalValue += (price * qty);

        const imgHtml = item.imageUrl
          ? \`<img src="\${safeHtml(item.imageUrl)}" class="cart-item-img" alt="">\`
          : \`<div class="cart-item-img" style="display:grid;place-items:center;color:#c7ccd1"><svg width="26" height="26" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.6" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg></div>\`;

        const row = document.createElement('div');
        row.className = 'cart-item';
        row.innerHTML = \`
          \${imgHtml}
          <div class="cart-item-info">
            <div class="cart-item-title">\${safeHtml(title)}</div>
            <div class="cart-item-price">\${formatMoney(price)}</div>
          </div>
          <div class="cart-item-actions">
            <div class="qty">
              <button class="qty-btn" onclick="updateQty('\${key}', -1)" aria-label="Decrease">&minus;</button>
              <span class="qty-display">\${qty}</span>
              <button class="qty-btn" onclick="updateQty('\${key}', 1)" aria-label="Increase">+</button>
            </div>
            <button class="remove-btn" onclick="removeItem('\${key}')" aria-label="Remove">
              <svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6M1 7h22M9 7V4a1 1 0 011-1h4a1 1 0 011 1v3"/></svg>
            </button>
          </div>
        \`;
        els.cartBody.insertBefore(row, els.checkoutSec);
      });

      els.cartTotal.textContent = formatMoney(totalValue);
      renderShipBar(totalValue);
    }

    function renderShipBar(total) {
      if (FREE_SHIP_THRESHOLD <= 0) { els.shipBar.style.display = 'none'; return; }
      els.shipBar.style.display = 'block';
      const pct = Math.min(100, Math.round((total / FREE_SHIP_THRESHOLD) * 100));
      els.shipFill.style.width = pct + '%';
      if (total >= FREE_SHIP_THRESHOLD) {
        els.shipText.innerHTML = 'You have unlocked <b>free delivery</b>.';
      } else {
        const left = formatMoney(FREE_SHIP_THRESHOLD - total);
        els.shipText.innerHTML = 'Add <b>' + left + '</b> more to unlock free delivery.';
      }
    }

    async function submitOrder(e) {
      e.preventDefault();
      const items = Array.from(state.cart.values());
      if (items.length === 0) return;

      const name = document.getElementById('customer-name').value.trim();
      const phone = document.getElementById('customer-phone').value.trim();
      const method = document.querySelector('input[name="fulfillment"]:checked').value;
      const note = document.getElementById('order-note').value.trim();

      els.checkoutBtn.disabled = true;
      els.checkoutBtn.style.opacity = '.7';
      els.checkoutBtn.innerHTML = 'Processing...';
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

        const res = await fetch('/api/public/catalog/' + encodeURIComponent(catalog.business.id) + '/orders', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || data.error || 'Failed to submit order');

        state.cart.clear();
        renderCart();
        const ref = data.order && data.order.orderNumber ? data.order.orderNumber : '';
        els.alertSuccessText.textContent = 'Order placed successfully! Reference: ' + ref;
        els.alertSuccess.style.display = 'flex';
        els.checkoutBtn.style.display = 'none';
        showToast('Order placed - ' + ref);

        if (shopWhatsApp) {
          const waUrl = new URL('https://wa.me/' + shopWhatsApp.replace(/\\D/g, ''));
          waUrl.searchParams.set('text', \`Hi, I just placed an order (\${ref}) on your online store. Please confirm.\`);
          els.whatsappBtn.href = waUrl.toString();
          els.whatsappBtn.style.display = 'block';
        }
      } catch (err) {
        els.alertErrorText.textContent = err.message || 'Something went wrong.';
        els.alertError.style.display = 'flex';
        els.checkoutBtn.disabled = false;
        els.checkoutBtn.style.opacity = '1';
        els.checkoutBtn.innerHTML = 'Place Order';
      } finally {
        els.checkoutBtn.style.opacity = '1';
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
        const res = await fetch('/api/public/catalog/' + encodeURIComponent(catalog.business.id) + '/orders/' + encodeURIComponent(no) + '?phone=' + encodeURIComponent(ph));
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || data.error || 'Not found');
        const order = data.order || {};
        const status = order.status || 'pending';
        const updated = order.updatedAt ? new Date(order.updatedAt).toLocaleString() : '';
        resDiv.className = 'track-result alert alert-success';
        resDiv.innerHTML = '<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg><div>Order status: <span class="status-pill ' + safeHtml(status) + '">' + safeHtml(status.replace(/_/g,' ')) + '</span>' + (updated ? '<br>Last updated: ' + safeHtml(updated) : '') + '</div>';
        resDiv.style.display = 'flex';
      } catch (err) {
        resDiv.className = 'track-result alert alert-error';
        resDiv.innerHTML = '<svg fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/></svg><div>' + safeHtml(err.message || 'Not found') + '</div>';
        resDiv.style.display = 'flex';
      } finally {
        btn.textContent = 'Track Order';
        btn.disabled = false;
      }
    }

    init();
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
      android_version text NOT NULL DEFAULT '',
      android_minimum_version text NOT NULL DEFAULT '',
      android_url text NOT NULL DEFAULT '',
      windows_version text NOT NULL DEFAULT '',
      windows_minimum_version text NOT NULL DEFAULT '',
      windows_url text NOT NULL DEFAULT '',
      release_notes text NOT NULL DEFAULT '',
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      CONSTRAINT platform_app_version_single_row CHECK (id = 1)
    )
    `,
  );
  await runDbQuery(
    target,
    `
    ALTER TABLE platform_app_version
      ADD COLUMN IF NOT EXISTS android_version text NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS android_minimum_version text NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS android_url text NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS windows_version text NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS windows_minimum_version text NOT NULL DEFAULT '',
      ADD COLUMN IF NOT EXISTS windows_url text NOT NULL DEFAULT ''
    `,
  );
  const initialLatestVersion =
    process.env.APP_LATEST_VERSION || process.env.APP_ANDROID_VERSION || '';
  const initialMinimumVersion =
    process.env.APP_MINIMUM_VERSION ||
    process.env.APP_ANDROID_MINIMUM_VERSION ||
    '';
  const initialApkUrl = process.env.APP_APK_URL || process.env.APP_ANDROID_URL || '';
  await runDbQuery(
    target,
    `
    INSERT INTO platform_app_version (
      id,
      latest_version,
      minimum_version,
      apk_url,
      android_version,
      android_minimum_version,
      android_url,
      windows_version,
      windows_minimum_version,
      windows_url,
      release_notes
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
    ON CONFLICT (id) DO NOTHING
    `,
    [
      1,
      initialLatestVersion,
      initialMinimumVersion,
      initialApkUrl,
      process.env.APP_ANDROID_VERSION || initialLatestVersion,
      process.env.APP_ANDROID_MINIMUM_VERSION || initialMinimumVersion,
      process.env.APP_ANDROID_URL || initialApkUrl,
      process.env.APP_WINDOWS_VERSION || '',
      process.env.APP_WINDOWS_MINIMUM_VERSION || '',
      process.env.APP_WINDOWS_URL || '',
      process.env.APP_RELEASE_NOTES || '',
    ],
  );
}

async function loadAppVersionConfig(target = query) {
  await ensureAppVersionSchema(target);
  const result = await runDbQuery(
    target,
    `
    SELECT
      latest_version,
      minimum_version,
      apk_url,
      android_version,
      android_minimum_version,
      android_url,
      windows_version,
      windows_minimum_version,
      windows_url,
      release_notes,
      updated_at
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
  const androidVersion =
    normalizeOptionalText(input.androidVersion || input.android_version) ||
    latestVersion;
  const androidMinimumVersion =
    normalizeOptionalText(
      input.androidMinimumVersion || input.android_minimum_version,
    ) || minimumVersion;
  const androidUrl =
    normalizeOptionalText(input.androidUrl || input.android_url) || apkUrl;
  const windowsVersion =
    normalizeOptionalText(input.windowsVersion || input.windows_version) || '';
  const windowsMinimumVersion =
    normalizeOptionalText(
      input.windowsMinimumVersion || input.windows_minimum_version,
    ) || '';
  const windowsUrl =
    normalizeOptionalText(input.windowsUrl || input.windows_url) || '';
  const releaseNotes = normalizeOptionalText(input.releaseNotes || input.release_notes) || '';
  for (const [label, url] of [
    ['APK URL', apkUrl],
    ['Android URL', androidUrl],
    ['Windows URL', windowsUrl],
  ]) {
    if (!isAllowedReleaseUrl(url)) {
      throw createHttpError(
        400,
        `${label} must be a hosted release path or a valid HTTPS URL.`,
      );
    }
  }
  const result = await runDbQuery(
    target,
    `
    INSERT INTO platform_app_version (
      id,
      latest_version,
      minimum_version,
      apk_url,
      android_version,
      android_minimum_version,
      android_url,
      windows_version,
      windows_minimum_version,
      windows_url,
      release_notes,
      updated_at
    )
    VALUES (1, $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
    ON CONFLICT (id) DO UPDATE
    SET latest_version = EXCLUDED.latest_version,
        minimum_version = EXCLUDED.minimum_version,
        apk_url = EXCLUDED.apk_url,
        android_version = EXCLUDED.android_version,
        android_minimum_version = EXCLUDED.android_minimum_version,
        android_url = EXCLUDED.android_url,
        windows_version = EXCLUDED.windows_version,
        windows_minimum_version = EXCLUDED.windows_minimum_version,
        windows_url = EXCLUDED.windows_url,
        release_notes = EXCLUDED.release_notes,
        updated_at = NOW()
    RETURNING
      latest_version,
      minimum_version,
      apk_url,
      android_version,
      android_minimum_version,
      android_url,
      windows_version,
      windows_minimum_version,
      windows_url,
      release_notes,
      updated_at
    `,
    [
      latestVersion,
      minimumVersion,
      apkUrl,
      androidVersion,
      androidMinimumVersion,
      androidUrl,
      windowsVersion,
      windowsMinimumVersion,
      windowsUrl,
      releaseNotes,
    ],
  );
  return normalizeAppVersionRow(result.rows[0]);
}

function normalizeAppVersionRow(row) {
  const latestVersion = row.latest_version || '';
  const minimumVersion = row.minimum_version || '';
  const apkUrl = row.apk_url || '';
  return {
    latestVersion,
    minimumVersion,
    apkUrl,
    androidVersion: row.android_version || latestVersion,
    androidMinimumVersion: row.android_minimum_version || minimumVersion,
    androidUrl: row.android_url || apkUrl,
    windowsVersion: row.windows_version || '',
    windowsMinimumVersion: row.windows_minimum_version || '',
    windowsUrl: row.windows_url || '',
    releaseNotes: row.release_notes || '',
    updatedAt: toIsoString(row.updated_at),
  };
}

function appVersionForPlatform(version, platform) {
  const requestedPlatform = normalizeOptionalText(platform);
  if (!requestedPlatform) {
    return version;
  }
  const normalizedPlatform = normalizeReleasePlatform(requestedPlatform);
  if (normalizedPlatform === 'android') {
    const latestVersion = version.androidVersion || version.latestVersion;
    const minimumVersion =
      version.androidMinimumVersion || version.minimumVersion;
    const downloadUrl = version.androidUrl || version.apkUrl;
    return {
      platform: 'android',
      latestVersion,
      minimumVersion,
      apkUrl: downloadUrl,
      downloadUrl,
      releaseNotes: version.releaseNotes,
      updatedAt: version.updatedAt,
    };
  }
  const latestVersion = version.windowsVersion || '';
  const minimumVersion = version.windowsMinimumVersion || '';
  const downloadUrl = version.windowsUrl;
  return {
    platform: 'windows',
    latestVersion,
    minimumVersion,
    apkUrl: version.androidUrl || version.apkUrl,
    downloadUrl,
    releaseNotes: version.releaseNotes,
    updatedAt: version.updatedAt,
  };
}

function normalizeReleasePlatform(value) {
  const platform = normalizeSubscriptionPlatform(value);
  if (platform === 'android' || platform === 'windows') {
    return platform;
  }
  throw createHttpError(400, 'Release platform must be android or windows.');
}

function isAllowedReleaseUrl(value) {
  const clean = normalizeOptionalText(value);
  if (!clean) {
    return true;
  }
  if (clean.startsWith(`${appReleaseUrlPrefix}/`)) {
    return true;
  }
  if (isHttpsUrl(clean)) {
    return true;
  }
  return (
    config.nodeEnv !== 'production' &&
    /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?(\/|$)/i.test(clean)
  );
}

async function saveUploadedAppRelease({
  req,
  platform,
  version,
  originalName,
}) {
  const maxBytes = Math.max(1, Number(config.appReleaseMaxBytes) || 1);
  const contentLength = Number(req.headers['content-length'] || 0);
  if (contentLength > maxBytes) {
    throw createHttpError(413, 'Release file is too large.');
  }

  const extension = releaseFileExtension(platform, originalName);
  const safeVersion = safeReleaseFilePart(version, 'release');
  const filename = `piki-pos-${platform}-${safeVersion}-${Date.now()}${extension}`;
  const platformDir = path.join(config.appReleaseDir, platform);
  const finalPath = path.join(platformDir, filename);
  const tempPath = path.join(
    platformDir,
    `.upload-${crypto.randomUUID()}-${filename}`,
  );

  await fsp.mkdir(platformDir, { recursive: true });
  let bytes = 0;
  const limitStream = new Transform({
    transform(chunk, _encoding, callback) {
      bytes += chunk.length;
      if (bytes > maxBytes) {
        callback(createHttpError(413, 'Release file is too large.'));
        return;
      }
      callback(null, chunk);
    },
  });

  try {
    await pipeline(req, limitStream, fs.createWriteStream(tempPath, { flags: 'wx' }));
    if (bytes === 0) {
      throw createHttpError(400, 'Release file is empty.');
    }
    await fsp.rename(tempPath, finalPath);
  } catch (error) {
    await fsp.rm(tempPath, { force: true }).catch(() => {});
    throw error;
  }

  return {
    platform,
    version,
    fileName: filename,
    bytes,
    url: `${appReleaseUrlPrefix}/${platform}/${filename}`,
  };
}

function releaseFileExtension(platform, originalName) {
  const sourceName = sourceFileName(originalName);
  const extension = path.extname(sourceName).toLowerCase();
  const allowed =
    platform === 'android'
      ? new Set(['.apk'])
      : new Set(['.zip', '.exe', '.msi']);
  if (!extension || !allowed.has(extension)) {
    const label = Array.from(allowed).join(', ');
    throw createHttpError(
      400,
      `${platform === 'android' ? 'Android' : 'Windows'} release must use ${label}.`,
    );
  }
  return extension;
}

function sourceFileName(value) {
  return (normalizeOptionalText(value) || '')
    .replace(/\\/g, '/')
    .split('/')
    .pop();
}

function safeReleaseFilePart(value, fallback) {
  const clean = (normalizeOptionalText(value) || fallback)
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
  return clean || fallback;
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
  const androidReleaseReady = Boolean(
    (appVersion.androidVersion || appVersion.latestVersion) &&
      (appVersion.androidUrl || appVersion.apkUrl),
  );
  const windowsReleaseReady = Boolean(
    appVersion.windowsVersion && appVersion.windowsUrl,
  );
  pushCheck({
    key: 'app_version',
    label: 'App Version Rollout',
    status: androidReleaseReady && windowsReleaseReady ? 'pass' : 'warning',
    severity: 'warning',
    message:
      androidReleaseReady && windowsReleaseReady
        ? `Android ${appVersion.androidVersion || appVersion.latestVersion} and Windows ${appVersion.windowsVersion} releases are configured.`
        : 'Upload Android and Windows app releases before shop rollout.',
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
    const signupConfigId =
      publicConfig.embeddedSignupConfigId ||
      publicConfig.businessLoginConfigurationId ||
      publicConfig.configId;
    const hasEmbeddedSignup =
      publicConfig.appId && signupConfigId && secretConfig.appSecret;
    const hasFallbackSender =
      publicConfig.phoneNumberId && secretConfig.accessToken;
    if (!hasEmbeddedSignup && !hasFallbackSender) {
      errors.push(
        'Embedded Signup App ID, Config ID, and App Secret, or fallback Phone Number ID and access token',
      );
    }
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

function renderWhatsAppConnectPage() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Piki POS WhatsApp Setup</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d111a;
      --panel: #141a27;
      --line: rgba(148, 163, 184, .16);
      --text: #f8fafc;
      --muted: #bfd0e4;
      --primary: #6d5dfc;
      --success: #35d07f;
      --danger: #ff5b6b;
    }
    * { box-sizing: border-box; }
    body {
      min-height: 100vh;
      margin: 0;
      display: grid;
      place-items: center;
      padding: 24px;
      background:
        radial-gradient(circle at top left, rgba(46, 213, 115, .16), transparent 30rem),
        radial-gradient(circle at bottom right, rgba(109, 93, 252, .22), transparent 30rem),
        var(--bg);
      color: var(--text);
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    main {
      width: min(100%, 620px);
      padding: 32px;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: rgba(20, 26, 39, .9);
      box-shadow: 0 24px 80px rgba(0, 0, 0, .32);
    }
    .icon {
      width: 56px;
      height: 56px;
      display: grid;
      place-items: center;
      margin-bottom: 20px;
      border-radius: 14px;
      background: rgba(109, 93, 252, .14);
      color: #d8d3ff;
      font-size: 18px;
      font-weight: 900;
    }
    .icon.success { background: rgba(53, 208, 127, .14); color: var(--success); }
    .icon.error { background: rgba(255, 91, 107, .14); color: var(--danger); }
    .eyebrow {
      margin: 0 0 8px;
      color: #dbe7f5;
      font-size: 12px;
      font-weight: 800;
      letter-spacing: .08em;
      text-transform: uppercase;
    }
    h1 {
      margin: 0;
      font-size: clamp(34px, 6vw, 46px);
      line-height: 1.05;
      letter-spacing: 0;
    }
    p { color: var(--muted); line-height: 1.6; }
    .details {
      display: none;
      gap: 12px;
      margin-top: 24px;
      padding: 16px;
      border: 1px solid var(--line);
      border-radius: 14px;
      background: rgba(6, 10, 18, .32);
    }
    .details.show { display: grid; }
    .detail { display: grid; gap: 4px; }
    .detail span {
      color: #94a3b8;
      font-size: 12px;
      font-weight: 800;
      letter-spacing: .05em;
      text-transform: uppercase;
    }
    .detail strong { overflow-wrap: anywhere; }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 24px;
    }
    button {
      min-height: 44px;
      padding: 0 22px;
      border: 0;
      border-radius: 12px;
      color: white;
      font: inherit;
      font-weight: 800;
      cursor: pointer;
    }
    button:disabled { opacity: .58; cursor: wait; }
    .primary { background: linear-gradient(135deg, #7b61ff, var(--primary)); }
    .secondary { background: #20283a; border: 1px solid var(--line); }
  </style>
</head>
<body>
  <main>
    <div id="icon" class="icon">...</div>
    <p class="eyebrow">Piki POS WhatsApp setup</p>
    <h1 id="title">Connect WhatsApp</h1>
    <p id="message">Loading WhatsApp setup...</p>
    <section id="details" class="details"></section>
    <div class="actions">
      <button id="continue" class="primary" type="button" disabled>Continue with Meta</button>
      <button class="secondary" type="button" onclick="window.close()">Close tab</button>
    </div>
  </main>
  <script>
    (function () {
      var FACEBOOK_ORIGINS = {
        "https://www.facebook.com": true,
        "https://web.facebook.com": true
      };
      var sessionToken = readSessionToken();
      var params = new URLSearchParams(window.location.search);
      var authCode = params.get("code") || "";
      var signupData = null;
      var platform = null;
      var submitted = false;
      var facebookSdk = null;
      var facebookSdkPromise = null;
      var metaWaitTimer = null;
      var directMetaMode = false;
      var continueButton = document.getElementById("continue");

      function readSessionToken() {
        var search = new URLSearchParams(window.location.search);
        return (
          search.get("session") ||
          search.get("connectSession") ||
          search.get("sessionToken") ||
          search.get("state") ||
          ""
        ).trim();
      }

      function setPhase(phase, title, message) {
        document.getElementById("title").textContent = title;
        document.getElementById("message").textContent = message;
        var icon = document.getElementById("icon");
        icon.className = "icon";
        icon.textContent = phase === "success" ? "OK" : phase === "error" ? "!" : "...";
        if (phase === "success") icon.classList.add("success");
        if (phase === "error") icon.classList.add("error");
      }

      function setButton(label, disabled) {
        continueButton.textContent = label;
        continueButton.disabled = disabled;
      }

      function setDetails(data) {
        var details = document.getElementById("details");
        var rows = [];
        function push(label, value) {
          if (!value) return;
          rows.push(
            '<div class="detail"><span>' + escapeHtml(label) + '</span><strong>' +
              escapeHtml(value) + '</strong></div>'
          );
        }
        push("Selected sender", data.displayPhoneNumber || data.whatsappDisplayPhoneNumber);
        push("Phone Number ID", data.phoneNumberId || data.whatsappPhoneNumberId);
        push("WABA ID", data.wabaId || data.whatsappWabaId);
        push("Setup link expires", data.sessionExpiresAt);
        details.innerHTML = rows.join("");
        details.className = rows.length ? "details show" : "details";
      }

      function escapeHtml(value) {
        return String(value || "").replace(/[&<>"']/g, function (char) {
          return {
            "&": "&amp;",
            "<": "&lt;",
            ">": "&gt;",
            '"': "&quot;",
            "'": "&#39;"
          }[char];
        });
      }

      function loadFacebookSdk(appId, apiVersion) {
        if (facebookSdk) {
          return Promise.resolve(facebookSdk);
        }
        if (facebookSdkPromise) {
          return facebookSdkPromise;
        }
        facebookSdkPromise = new Promise(function (resolve, reject) {
          var settled = false;
          var sdkTimer = window.setTimeout(function () {
            if (settled) return;
            settled = true;
            reject(new Error("Meta login is taking too long to load in this browser."));
          }, 8000);

          function settle(callback, value) {
            if (settled) return;
            settled = true;
            window.clearTimeout(sdkTimer);
            callback(value);
          }

          function init() {
            if (!window.FB) {
              settle(reject, new Error("Meta login SDK failed to load."));
              return;
            }
            window.FB.init({
              appId: appId,
              cookie: true,
              xfbml: false,
              version: apiVersion || "v20.0"
            });
            facebookSdk = window.FB;
            settle(resolve, facebookSdk);
          }
          if (window.FB) {
            init();
            return;
          }
          window.fbAsyncInit = init;
          var existing = document.getElementById("facebook-jssdk");
          if (existing) {
            existing.addEventListener("load", init, { once: true });
            existing.addEventListener("error", function () {
              settle(reject, new Error("Meta login SDK failed to load."));
            }, { once: true });
            return;
          }
          var script = document.createElement("script");
          script.id = "facebook-jssdk";
          script.async = true;
          script.defer = true;
          script.crossOrigin = "anonymous";
          script.src = "https://connect.facebook.net/en_US/sdk.js";
          script.onerror = function () {
            settle(reject, new Error("Meta login SDK failed to load."));
          };
          document.body.appendChild(script);
        }).catch(function (error) {
          facebookSdkPromise = null;
          throw error;
        });
        return facebookSdkPromise;
      }

      function enableDirectMetaMode(message) {
        directMetaMode = true;
        setButton("Open Meta directly", false);
        setPhase(
          "ready",
          "Connect WhatsApp",
          message || "Meta login did not load in this browser. Open Meta directly to continue."
        );
      }

      function buildDirectMetaUrl() {
        var version = String(platform.apiVersion || "v20.0").replace(/^\\/+/, "");
        var url = new URL("https://www.facebook.com/" + version + "/dialog/oauth");
        url.searchParams.set("client_id", platform.appId);
        url.searchParams.set("redirect_uri", window.location.origin + "/whatsapp/connect/callback");
        url.searchParams.set("response_type", "code");
        url.searchParams.set("config_id", platform.embeddedSignupConfigId);
        url.searchParams.set("override_default_response_type", "true");
        url.searchParams.set("state", sessionToken);
        return url.toString();
      }

      function normalizeSignupData(data) {
        data = data || {};
        return {
          phoneNumberId:
            data.phone_number_id ||
            data.phoneNumberId ||
            data.whatsapp_phone_number_id ||
            "",
          wabaId:
            data.waba_id ||
            data.wabaId ||
            data.whatsapp_business_account_id ||
            "",
          displayPhoneNumber:
            data.display_phone_number ||
            data.displayPhoneNumber ||
            data.phone_number ||
            "",
          businessName:
            data.business_name ||
            data.businessName ||
            data.verified_name ||
            ""
        };
      }

      function tryComplete() {
        if (submitted || !sessionToken || !platform || !authCode) {
          return;
        }
        var completionData = signupData || {};
        submitted = true;
        clearMetaWaitTimer();
        setButton("Saving connection...", true);
        setPhase("busy", "Connecting WhatsApp", "Saving WhatsApp connection...");
        fetch("/api/business/whatsapp-connect/complete", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            connectSession: sessionToken,
            code: authCode,
            redirectUri: window.location.origin + "/whatsapp/connect/callback",
            phoneNumberId: completionData.phoneNumberId,
            wabaId: completionData.wabaId,
            displayPhoneNumber: completionData.displayPhoneNumber,
            businessName: completionData.businessName
          })
        })
          .then(readJson)
          .then(function (body) {
            if (body.ok !== true) throw new Error(body.error || "WhatsApp connection failed.");
            setPhase("success", "Connection complete", "WhatsApp Business API connected. Return to Piki POS and refresh messaging settings.");
            setDetails(body.data || signupData);
          })
          .catch(function (error) {
            submitted = false;
            setButton("Try again", false);
            setPhase("error", "Connection failed", error.message || "WhatsApp connection failed.");
          });
      }

      function clearMetaWaitTimer() {
        if (metaWaitTimer) {
          window.clearTimeout(metaWaitTimer);
          metaWaitTimer = null;
        }
      }

      function startMetaWaitTimer() {
        clearMetaWaitTimer();
        metaWaitTimer = window.setTimeout(function () {
          if (submitted || authCode || signupData) return;
          setButton("Try again", false);
          setPhase(
            "busy",
            "Still waiting for Meta",
            "If no Meta signup window opened, allow pop-ups for pikipos.com and tap Try again. If Meta is open, finish setup there."
          );
        }, 12000);
      }

      function readJson(response) {
        return response.json().then(function (body) {
          if (!response.ok) throw new Error(body.error || "Request failed.");
          return body;
        });
      }

      window.addEventListener("message", function (event) {
        if (!FACEBOOK_ORIGINS[event.origin]) return;
        var data = null;
        try {
          data = JSON.parse(event.data);
        } catch (_) {
          return;
        }
        if (!data || data.type !== "WA_EMBEDDED_SIGNUP") return;

        if (data.event === "FINISH") {
          clearMetaWaitTimer();
          signupData = normalizeSignupData(data.data);
          if (!signupData.phoneNumberId) {
            setPhase("error", "Connection failed", "Meta finished setup but did not return a phone number ID.");
            continueButton.disabled = false;
            return;
          }
          setDetails(signupData);
          setPhase("busy", "Connecting WhatsApp", "Meta signup finished. Waiting for authorization...");
          tryComplete();
          return;
        }
        if (data.event === "CANCEL") {
          clearMetaWaitTimer();
          setPhase("error", "Connection cancelled", "WhatsApp setup was cancelled before completion.");
          setButton("Try again", false);
          return;
        }
        if (data.event === "ERROR") {
          clearMetaWaitTimer();
          setPhase("error", "Connection failed", (data.data && data.data.error_message) || "Meta could not complete WhatsApp setup.");
          setButton("Try again", false);
        }
      });

      continueButton.addEventListener("click", function () {
        if (!platform) return;
        if (directMetaMode) {
          setButton("Opening Meta...", true);
          window.location.assign(buildDirectMetaUrl());
          return;
        }
        if (!facebookSdk) {
          setButton("Preparing Meta...", true);
          setPhase("busy", "Preparing Meta login", "Loading Meta setup. Try again in a moment...");
          loadFacebookSdk(platform.appId, platform.apiVersion)
            .then(function () {
              setButton("Continue with Meta", false);
              setPhase("ready", "Connect WhatsApp", "Continue with Meta to verify and connect your WhatsApp number.");
            })
            .catch(function (error) {
              enableDirectMetaMode(error.message || "Meta login could not be prepared in this browser.");
            });
          return;
        }

        setButton("Waiting for Meta...", true);
        setPhase("busy", "Connecting WhatsApp", "Continue in the Meta signup window...");
        startMetaWaitTimer();
        try {
          facebookSdk.login(function (response) {
            clearMetaWaitTimer();
            authCode = (response && response.authResponse && response.authResponse.code) || "";
            if (!authCode) {
              setButton("Try again", false);
              setPhase("error", "Connection failed", "Meta login was cancelled before authorization completed.");
              return;
            }
            setPhase("busy", "Connecting WhatsApp", "Meta authorized Piki. Waiting for WhatsApp number details...");
            tryComplete();
          }, {
            config_id: platform.embeddedSignupConfigId,
            response_type: "code",
            override_default_response_type: true,
            state: sessionToken,
            extras: {
              sessionInfoVersion: 2,
              feature: "whatsapp_embedded_signup"
            }
          });
        } catch (error) {
          clearMetaWaitTimer();
          setButton("Try again", false);
          setPhase("error", "Connection failed", error.message || "Meta login could not be opened.");
        }
      });

      if (!sessionToken) {
        setPhase("error", "Connection failed", "This WhatsApp setup link is missing a connection session.");
        return;
      }

      fetch("/api/business/whatsapp-connect/session/" + encodeURIComponent(sessionToken))
        .then(readJson)
        .then(function (body) {
          platform = (body.data && body.data.platform) || {};
          if (!platform.isActive || !platform.setupReady) {
            throw new Error("WhatsApp setup is not enabled yet. Contact Piki support.");
          }
          setDetails(body.data || {});
          if (authCode) {
            setPhase("busy", "Connecting WhatsApp", "Meta authorized Piki. Saving WhatsApp connection...");
            tryComplete();
            return null;
          }
          setButton("Preparing Meta...", true);
          setPhase("busy", "Preparing Meta login", "Loading Meta setup...");
          return loadFacebookSdk(platform.appId, platform.apiVersion);
        })
        .then(function () {
          if (submitted || authCode) {
            return;
          }
          setButton("Continue with Meta", false);
          setPhase("ready", "Connect WhatsApp", "Continue with Meta to verify and connect your WhatsApp number.");
        })
        .catch(function (error) {
          if (platform && platform.appId && platform.embeddedSignupConfigId) {
            enableDirectMetaMode(error.message || "Meta login could not be loaded in this browser.");
            return;
          }
          setButton("Try again", false);
          setPhase("error", "Connection failed", error.message || "WhatsApp setup could not be loaded.");
        });
    })();
  </script>
</body>
</html>`;
}

function buildWhatsAppConnectUrl(req, sessionToken) {
  const cleanSessionToken = normalizeOptionalText(sessionToken);
  const publicBaseUrl = resolvePublicBackendBaseUrl(req);
  if (!publicBaseUrl || !cleanSessionToken) {
    return '';
  }

  try {
    const url = new URL('/whatsapp/connect', publicBaseUrl);
    if (!['http:', 'https:'].includes(url.protocol)) {
      return '';
    }
    url.searchParams.set('session', cleanSessionToken);
    return url.toString();
  } catch (_) {
    return '';
  }
}

function resolvePublicBackendBaseUrl(req) {
  const configured = normalizeOptionalText(config.publicBaseUrl);
  if (configured) {
    return configured;
  }

  const forwardedProto = normalizeOptionalText(req.headers['x-forwarded-proto']);
  const forwardedHost = normalizeOptionalText(req.headers['x-forwarded-host']);
  const proto =
    forwardedProto?.split(',')[0]?.trim() ||
    (req.secure ? 'https' : normalizeOptionalText(req.protocol)) ||
    'http';
  const host =
    forwardedHost?.split(',')[0]?.trim() ||
    normalizeOptionalText(req.headers.host);
  return host ? `${proto}://${host}` : '';
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

  // Same-timestamp conflict detection: if two devices push the same record
  // with the same updated_at but different payloads, we previously silently
  // dropped the incoming write. Now we apply it using server_revision as a
  // deterministic tiebreaker and return a client-visible conflict_applied
  // status so the caller can log/audit it.
  if (existingRow) {
    const timestampComparison = compareTimestamps(
      row.updated_at,
      existingRow.updated_at,
    );
    if (timestampComparison === 0 && !areRecordsEquivalent(tableName, row, existingRow)) {
      const directUpdateAssignments = [
        ...updateColumns.map((column, index) => `${column} = $${index + 1}`),
        "server_revision = nextval('sync_revision_seq')",
      ].join(', ');
      const directUpdateValues = [
        ...updateColumns.map((column) => scopedRow[column]),
        row.id,
        businessId,
      ];
      await client.query(
        `UPDATE ${tableName}
         SET ${directUpdateAssignments}
         WHERE id = $${updateColumns.length + 1}
           AND business_id = $${updateColumns.length + 2}`,
        directUpdateValues,
      );
      const appliedResult = await client.query(
        `SELECT * FROM ${tableName} WHERE id = $1`,
        [row.id],
      );
      const appliedRow = appliedResult.rows[0];
      console.warn(
        `[sync][conflict_applied] table=${tableName} id=${row.id} business_id=${businessId} reason=same_timestamp_different_payload`,
      );
      return {
        status: 'conflict_applied',
        row: appliedRow,
        conflict: {
          reason: 'same_timestamp_different_payload',
          serverRow: canonicalizeRecord(tableName, existingRow, {
            forceSyncedStatus: true,
          }),
        },
      };
    }
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
