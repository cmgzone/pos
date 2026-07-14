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
const JSZip = require('jszip');
const mammoth = require('mammoth');
const { PDFParse } = require('pdf-parse');

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
  sendOtpEmail,
  verifyEmailOtp,
} = require('./authOtp');
const {
  ensurePikiProactiveSchema,
  refreshBusinessInsights,
  startPikiProactiveWorker,
} = require('./pikiProactive');
const { createPikiCloudModule } = require('./pikiCloud');
const {
  createAiJobsModule,
} = require('./aiJobs');
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
  buildCatalogStorefrontSubdomain,
  buildCatalogStorefrontUrl,
  ensureBusinessCatalogSubdomain,
  ensureCatalogSubdomainSchema,
  extractCatalogSubdomain,
  findBusinessCatalogStorefrontBySubdomain,
  initializeCatalogSubdomainSchema,
  normalizeCatalogSubdomain,
} = require('./catalogSubdomains');
const { normalizePublicCatalogBranches } = require('./catalogBranches');
const {
  checkoutForActiveGateways,
  createStorefrontTheme,
  deleteStorefrontTheme,
  duplicateStorefrontTheme,
  ensureStorefrontThemeSchema,
  getStorefrontTheme,
  listStorefrontThemes,
  loadPublishedStorefrontTheme,
  publishStorefrontTheme,
  storefrontThemePresets,
  updateStorefrontTheme,
} = require('./storefrontThemes');

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
  'product_variant_colors',
  'services',
  'stock_batches',
  'sale_items',
  'sales',
  'purchase_invoices',
  'stock_transfers',
]);
const CATALOG_CACHE_CODE_VERSION = '3';
const STOREFRONT_TYPES = Object.freeze({
  retail: Object.freeze({
    type: 'retail',
    label: 'Retail store',
    title: 'Online shop',
    description: 'Browse products, choose variants, and place an order in seconds.',
    browseLabel: 'Shop products',
  }),
  services: Object.freeze({
    type: 'services',
    label: 'Services',
    title: 'Service booking',
    description: 'Explore services, choose what you need, and request a booking.',
    browseLabel: 'Browse services',
  }),
  restaurant: Object.freeze({
    type: 'restaurant',
    label: 'Restaurant',
    title: 'Restaurant menu',
    description: 'Explore the menu, add your favourites, and send your order to the kitchen.',
    browseLabel: 'View menu',
  }),
});
const aiJobs = createAiJobsModule({
  query,
  withTransaction,
  normalizeOptionalText,
});
const pikiCloud = createPikiCloudModule({ query, config });

app.disable('x-powered-by');
app.use(applySecurityHeaders);
app.use(
  cors((req, callback) => {
    callback(null, buildCorsOptions(req));
  }),
);
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

      // One email may own several businesses; each signup creates (or
      // reactivates) a separate business with its own subdomain + storefronts.
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
          custom_role_id: null,
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
      const matchingBusinessIds = [
        ...new Set(matchingUsers.map((candidate) => candidate.business_id)),
      ];
      const requestedBusinessId = normalizeOptionalText(req.body?.businessId);
      if (requestedBusinessId && !matchingBusinessIds.includes(requestedBusinessId)) {
        throw createHttpError(403, 'This account does not have access to the selected business');
      }
      if (matchingBusinessIds.length > 1 && !requestedBusinessId) {
        const bizResult = await client.query(
          `SELECT id, name, public_subdomain
           FROM businesses
           WHERE id = ANY($1) AND deleted_at IS NULL`,
          [matchingBusinessIds],
        );
        return {
          needsBusinessSelection: true,
          businesses: bizResult.rows.map((row) => ({
            id: normalizeText(row.id),
            name: row.name,
            subdomain: normalizeCatalogSubdomain(row.public_subdomain),
          })),
        };
      }
      const selectedBusinessId =
        requestedBusinessId && matchingBusinessIds.includes(requestedBusinessId)
          ? requestedBusinessId
          : matchingBusinessIds[0];
      const user =
        matchingUsers.find((c) => c.business_id === selectedBusinessId) ||
        matchingUsers[0];

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

app.get('/api/reports/tax-summary', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    const { from, to } = normalizeReportDateRange(req.query);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const clauses = [
      's.business_id = $1',
      'DATE(s.created_at) BETWEEN $2::date AND $3::date',
      's.deleted_at IS NULL',
      's.refund_sale_id IS NULL',
    ];
    const params = [businessContext.businessId, from, to];
    addReportBranchFilter(clauses, params, 's', scope);
    const rows = await query(
      `SELECT
         COALESCE(SUM(s.total_amount), 0) AS gross_sales,
         COALESCE(SUM(s.tax), 0) AS output_vat,
         COALESCE(SUM(s.total_amount - s.tax), 0) AS net_sales,
         COALESCE(SUM(s.discount), 0) AS discounts,
         COUNT(s.id)::int AS receipt_count
       FROM sales s
       WHERE ${clauses.join(' AND ')}`,
      params,
    );
    res.json({ ok: true, from, to, summary: rows.rows[0] || {} });
  } catch (error) {
    next(error);
  }
});

app.get('/api/reports/sales-summary', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    const { from, to } = normalizeReportDateRange(req.query);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const clauses = [
      's.business_id = $1',
      'DATE(s.created_at) BETWEEN $2::date AND $3::date',
      's.deleted_at IS NULL',
      's.refund_sale_id IS NULL',
    ];
    const params = [businessContext.businessId, from, to];
    addReportBranchFilter(clauses, params, 's', scope);
    const summary = await query(
      `SELECT
         COUNT(s.id)::int AS sale_count,
         COALESCE(SUM(s.total_amount), 0) AS total_sales,
         COALESCE(SUM(s.tax), 0) AS total_tax,
         COALESCE(SUM(s.discount), 0) AS total_discount,
         COALESCE(AVG(s.total_amount), 0) AS average_sale,
         COALESCE(SUM(s.amount_paid), 0) AS amount_paid,
         COALESCE(SUM(s.balance_due), 0) AS balance_due
       FROM sales s
       WHERE ${clauses.join(' AND ')}`,
      params,
    );
    const byPayment = await query(
      `SELECT
         COALESCE(NULLIF(s.payment_type, ''), 'unknown') AS payment_type,
         COUNT(s.id)::int AS sale_count,
         COALESCE(SUM(s.total_amount), 0) AS amount
       FROM sales s
       WHERE ${clauses.join(' AND ')}
       GROUP BY payment_type
       ORDER BY amount DESC`,
      params,
    );
    res.json({
      ok: true,
      from,
      to,
      summary: summary.rows[0] || {},
      paymentBreakdown: byPayment.rows,
    });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Advanced BI dashboard
// ============================================================================

app.get('/api/bi/customer-lifetime-value', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const limit = Math.max(1, Math.min(100, Number.parseInt(req.query.limit, 10) || 20));
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const salesClauses = [
      's.business_id = $1',
      's.deleted_at IS NULL',
      's.refund_for_sale_id IS NULL',
    ];
    const params = [businessContext.businessId];
    addReportBranchFilter(salesClauses, params, 's', scope);
    params.push(limit);
    const rows = await query(
      `SELECT
         c.id AS customer_id,
         c.name AS customer_name,
         COUNT(s.id)::int AS transaction_count,
         COALESCE(SUM(s.total_amount), 0) AS lifetime_value,
         COALESCE(AVG(s.total_amount), 0) AS average_order_value,
         MIN(s.created_at) AS first_purchase_at,
         MAX(s.created_at) AS last_purchase_at
       FROM customers c
       JOIN sales s ON s.customer_id = c.id AND ${salesClauses.join(' AND ')}
       WHERE c.business_id = $1 AND c.deleted_at IS NULL
       GROUP BY c.id, c.name
       ORDER BY lifetime_value DESC, transaction_count DESC
       LIMIT $${params.length}`,
      params,
    );
    const customers = rows.rows;
    const totalValue = customers.reduce((sum, row) => sum + Number(row.lifetime_value || 0), 0);
    res.json({
      ok: true,
      summary: {
        customerCount: customers.length,
        totalValue,
        averageClv: customers.length ? totalValue / customers.length : 0,
      },
      customers,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/bi/sales-forecast', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const lookbackDays = Math.max(14, Math.min(365, Number.parseInt(req.query.lookbackDays, 10) || 56));
    const forecastDays = Math.max(7, Math.min(90, Number.parseInt(req.query.forecastDays, 10) || 30));
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const clauses = [
      's.business_id = $1',
      's.deleted_at IS NULL',
      's.refund_for_sale_id IS NULL',
      's.created_at >= CURRENT_DATE - ($2::integer - 1)',
    ];
    const params = [businessContext.businessId, lookbackDays];
    addReportBranchFilter(clauses, params, 's', scope);
    const rows = await query(
      `SELECT DATE(s.created_at)::text AS day,
              COALESCE(SUM(s.total_amount), 0) AS revenue,
              COUNT(s.id)::int AS sale_count
       FROM sales s
       WHERE ${clauses.join(' AND ')}
       GROUP BY DATE(s.created_at)
       ORDER BY DATE(s.created_at) ASC`,
      params,
    );
    const revenueByDay = new Map(rows.rows.map((row) => [String(row.day), Number(row.revenue || 0)]));
    const history = [];
    const today = new Date();
    for (let offset = lookbackDays - 1; offset >= 0; offset -= 1) {
      const day = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() - offset));
      const key = day.toISOString().slice(0, 10);
      history.push({ day: key, revenue: revenueByDay.get(key) || 0 });
    }
    const n = history.length;
    const meanX = (n - 1) / 2;
    const meanY = history.reduce((sum, point) => sum + point.revenue, 0) / Math.max(1, n);
    const denominator = history.reduce((sum, _, index) => sum + (index - meanX) ** 2, 0);
    const slope = denominator
      ? history.reduce((sum, point, index) => sum + (index - meanX) * (point.revenue - meanY), 0) / denominator
      : 0;
    const intercept = meanY - slope * meanX;
    const forecast = [];
    for (let index = 0; index < forecastDays; index += 1) {
      const day = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate() + index + 1));
      forecast.push({
        day: day.toISOString().slice(0, 10),
        revenue: Math.max(0, Number((intercept + slope * (n + index)).toFixed(2))),
      });
    }
    res.json({
      ok: true,
      lookbackDays,
      forecastDays,
      summary: {
        averageDailyRevenue: meanY,
        trendPerDay: slope,
        forecastRevenue: forecast.reduce((sum, point) => sum + point.revenue, 0),
      },
      history,
      forecast,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/bi/customer-cohorts', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const months = Math.max(3, Math.min(24, Number.parseInt(req.query.months, 10) || 12));
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId, months];
    const branchFilter = scope.branchIds == null
      ? ''
      : ` AND COALESCE(s.branch_id, 'main_branch') = ANY($3::text[])`;
    if (scope.branchIds != null) params.push(scope.branchIds);
    const rows = await query(
      `WITH first_purchase AS (
         SELECT s.customer_id, DATE_TRUNC('month', MIN(s.created_at)) AS cohort_month
         FROM sales s
         WHERE s.business_id = $1
           AND s.customer_id IS NOT NULL
           AND s.deleted_at IS NULL
           AND s.refund_for_sale_id IS NULL
           ${branchFilter}
         GROUP BY s.customer_id
       ),
       cohort_customers AS (
         SELECT * FROM first_purchase
         WHERE cohort_month >= DATE_TRUNC('month', CURRENT_DATE) - MAKE_INTERVAL(months => ($2::integer - 1))
       ),
       cohort_sizes AS (
         SELECT cohort_month, COUNT(*)::int AS cohort_size
         FROM cohort_customers GROUP BY cohort_month
       ),
       activity AS (
         SELECT cc.customer_id, cc.cohort_month, DATE_TRUNC('month', s.created_at) AS activity_month
         FROM cohort_customers cc
         JOIN sales s ON s.customer_id = cc.customer_id
         WHERE s.business_id = $1
           AND s.deleted_at IS NULL
           AND s.refund_for_sale_id IS NULL
           ${branchFilter}
       )
       SELECT
         TO_CHAR(a.cohort_month, 'YYYY-MM') AS cohort_month,
         (
           EXTRACT(YEAR FROM AGE(a.activity_month, a.cohort_month)) * 12
           + EXTRACT(MONTH FROM AGE(a.activity_month, a.cohort_month))
         )::int AS period_number,
         cs.cohort_size,
         COUNT(DISTINCT a.customer_id)::int AS retained_customers
       FROM activity a
       JOIN cohort_sizes cs ON cs.cohort_month = a.cohort_month
       WHERE a.activity_month >= a.cohort_month
       GROUP BY a.cohort_month, period_number, cs.cohort_size
       ORDER BY a.cohort_month ASC, period_number ASC`,
      params,
    );
    res.json({ ok: true, months, cohorts: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.get('/api/bi/employee-turnover', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const months = Math.max(3, Math.min(24, Number.parseInt(req.query.months, 10) || 12));
    const rows = await query(
      `WITH month_series AS (
         SELECT DATE_TRUNC('month', value)::date AS month_start
         FROM GENERATE_SERIES(
           DATE_TRUNC('month', CURRENT_DATE) - MAKE_INTERVAL(months => ($2::integer - 1)),
           DATE_TRUNC('month', CURRENT_DATE),
           INTERVAL '1 month'
         ) AS value
       )
       SELECT
         TO_CHAR(m.month_start, 'YYYY-MM') AS month,
         COUNT(u.id) FILTER (WHERE DATE_TRUNC('month', u.created_at) = m.month_start)::int AS hires,
         COUNT(u.id) FILTER (WHERE u.deleted_at IS NOT NULL AND DATE_TRUNC('month', u.deleted_at) = m.month_start)::int AS departures,
         COUNT(u.id) FILTER (
           WHERE u.created_at < m.month_start + INTERVAL '1 month'
             AND (u.deleted_at IS NULL OR u.deleted_at >= m.month_start + INTERVAL '1 month')
         )::int AS ending_headcount
       FROM month_series m
       LEFT JOIN users u ON u.business_id = $1
       GROUP BY m.month_start
       ORDER BY m.month_start ASC`,
      [businessContext.businessId, months],
    );
    const data = rows.rows.map((row) => ({
      ...row,
      turnover_rate: Number(row.ending_headcount || 0) > 0
        ? Number(((Number(row.departures || 0) / Number(row.ending_headcount || 0)) * 100).toFixed(1))
        : 0,
    }));
    res.json({
      ok: true,
      months,
      summary: {
        hires: data.reduce((sum, row) => sum + Number(row.hires || 0), 0),
        departures: data.reduce((sum, row) => sum + Number(row.departures || 0), 0),
        currentHeadcount: Number(data[data.length - 1]?.ending_headcount || 0),
      },
      turnover: data,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/reports/inventory-valuation', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const clauses = ['p.business_id = $1', 'p.deleted_at IS NULL'];
    const params = [businessContext.businessId];
    addReportBranchFilter(clauses, params, 'p', scope);
    const rows = await query(
      `SELECT
         COUNT(p.id)::int AS product_count,
         COALESCE(SUM(p.stock), 0) AS stock_units,
         COALESCE(SUM(p.stock * COALESCE(p.cost, 0)), 0) AS cost_value,
         COALESCE(SUM(p.stock * COALESCE(p.price, 0)), 0) AS retail_value,
         COUNT(*) FILTER (WHERE p.stock <= p.low_stock)::int AS low_stock_count
       FROM products p
       WHERE ${clauses.join(' AND ')}`,
      params,
    );
    res.json({ ok: true, valuation: rows.rows[0] || {} });
  } catch (error) {
    next(error);
  }
});

app.get('/api/reports/reorder-suggestions', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    const lookbackDays = Math.max(
      7,
      Math.min(365, Number.parseInt(req.query.lookbackDays, 10) || 30),
    );
    const defaultLeadTimeDays = Math.max(
      1,
      Math.min(90, Number.parseInt(req.query.defaultLeadTimeDays, 10) || 7),
    );
    const limit = Math.max(
      1,
      Math.min(50, Number.parseInt(req.query.limit, 10) || 20),
    );
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const productClauses = [
      'p.business_id = $1',
      'p.deleted_at IS NULL',
      'COALESCE(p.track_stock, 1) <> 0',
      'COALESCE(p.has_variants, 0) = 0',
    ];
    const salesClauses = [
      'si.business_id = $1',
      's.business_id = $1',
      'si.deleted_at IS NULL',
      's.deleted_at IS NULL',
      's.refund_sale_id IS NULL',
      "s.created_at >= NOW() - make_interval(days => $2::integer)",
    ];
    const batchClauses = [
      'sb.business_id = $1',
      'sb.deleted_at IS NULL',
      'sb.received_at IS NOT NULL',
    ];
    const params = [
      businessContext.businessId,
      lookbackDays,
      defaultLeadTimeDays,
    ];
    addReportBranchFilter(productClauses, params, 'p', scope);
    addReportBranchFilter(salesClauses, params, 's', scope);
    addReportBranchFilter(batchClauses, params, 'sb', scope);
    params.push(limit);

    const rows = await query(
      `WITH sales_velocity AS (
         SELECT
           si.product_id,
           COALESCE(SUM(GREATEST(si.quantity, 0)), 0) / $2::double precision
             AS daily_velocity,
           MAX(s.created_at) AS last_sold_at
         FROM sale_items si
         JOIN sales s ON s.id = si.sale_id AND s.business_id = si.business_id
         WHERE ${salesClauses.join(' AND ')}
         GROUP BY si.product_id
       ),
       receipt_gaps AS (
         SELECT
           sb.product_id,
           EXTRACT(
             EPOCH FROM (
               sb.received_at - LAG(sb.received_at) OVER (
                 PARTITION BY sb.product_id
                 ORDER BY sb.received_at
               )
             )
           ) / 86400.0 AS days_between_receipts
         FROM stock_batches sb
         WHERE ${batchClauses.join(' AND ')}
       ),
       lead_times AS (
         SELECT
           product_id,
           LEAST(
             45::double precision,
             GREATEST(3::double precision, AVG(days_between_receipts))
           ) AS lead_time_days
         FROM receipt_gaps
         WHERE days_between_receipts > 0
         GROUP BY product_id
       ),
       inventory AS (
         SELECT
           p.id AS product_id,
           p.name AS item_name,
           p.name AS product_name,
           p.sku,
           p.barcode,
           p.stock,
           p.low_stock,
           p.stock_unit,
           p.cost AS unit_cost,
           COALESCE(sv.daily_velocity, 0) AS daily_velocity,
           COALESCE(lt.lead_time_days, $3::double precision) AS lead_time_days,
           sv.last_sold_at
         FROM products p
         LEFT JOIN sales_velocity sv ON sv.product_id = p.id
         LEFT JOIN lead_times lt ON lt.product_id = p.id
         WHERE ${productClauses.join(' AND ')}
       ),
       computed AS (
         SELECT
           *,
           CASE
             WHEN daily_velocity > 0 THEN stock / daily_velocity
             ELSE NULL
           END AS days_of_cover,
           CASE
             WHEN daily_velocity > 0 THEN GREATEST(
               low_stock * 2,
               daily_velocity * (lead_time_days + 7),
               low_stock + (daily_velocity * 7)
             )
             ELSE low_stock * 2
           END AS target_stock
         FROM inventory
       )
       SELECT
         'product' AS item_type,
         product_id,
         item_name,
         product_name,
         sku,
         barcode,
         stock,
         low_stock,
         stock_unit,
         unit_cost,
         ROUND(daily_velocity::numeric, 2)::double precision AS daily_velocity,
         ROUND(lead_time_days::numeric, 1)::double precision AS lead_time_days,
         CASE
           WHEN days_of_cover IS NULL THEN NULL
           ELSE ROUND(days_of_cover::numeric, 1)::double precision
         END AS days_of_cover,
         ROUND(target_stock::numeric, 2)::double precision AS target_stock,
         ROUND(GREATEST(target_stock - stock, 0)::numeric, 2)::double precision
           AS suggested_qty,
         last_sold_at,
         CASE
           WHEN stock <= 0 THEN 'out'
           WHEN stock <= low_stock THEN 'low'
           ELSE 'soon'
         END AS urgency
       FROM computed
       WHERE (
         stock <= low_stock
         OR (daily_velocity > 0 AND days_of_cover <= lead_time_days + 2)
       )
         AND target_stock - stock > 0.001
       ORDER BY
         CASE
           WHEN stock <= 0 THEN 0
           WHEN stock <= low_stock THEN 1
           ELSE 2
         END,
         days_of_cover NULLS LAST,
         suggested_qty DESC
       LIMIT $${params.length}`,
      params,
    );
    res.json({
      ok: true,
      lookbackDays,
      defaultLeadTimeDays,
      suggestions: rows.rows,
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/reports/profit-loss', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.reports);
    const { from, to } = normalizeReportDateRange(req.query);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const salesClauses = [
      's.business_id = $1',
      'DATE(s.created_at) BETWEEN $2::date AND $3::date',
      's.deleted_at IS NULL',
      's.refund_sale_id IS NULL',
    ];
    const salesParams = [businessContext.businessId, from, to];
    addReportBranchFilter(salesClauses, salesParams, 's', scope);
    const expenseClauses = [
      'e.business_id = $1',
      'DATE(e.incurred_on) BETWEEN $2::date AND $3::date',
      'e.deleted_at IS NULL',
    ];
    const expenseParams = [businessContext.businessId, from, to];
    addReportBranchFilter(expenseClauses, expenseParams, 'e', scope);
    const sales = await query(
      `SELECT
         COALESCE(SUM(s.total_amount), 0) AS revenue,
         COALESCE(SUM(s.discount), 0) AS discounts,
         COALESCE(SUM(s.tax), 0) AS tax_collected,
         COALESCE(SUM((
           SELECT SUM(si.quantity * COALESCE(si.unit_cost, 0))
           FROM sale_items si
           WHERE si.sale_id = s.id AND si.business_id = s.business_id
         )), 0) AS cost_of_goods
       FROM sales s
       WHERE ${salesClauses.join(' AND ')}`,
      salesParams,
    );
    const expenses = await query(
      `SELECT COALESCE(SUM(e.amount), 0) AS operating_expenses
       FROM expenses e
       WHERE ${expenseClauses.join(' AND ')}`,
      expenseParams,
    );
    const row = sales.rows[0] || {};
    const expenseRow = expenses.rows[0] || {};
    const revenue = Number(row.revenue || 0);
    const costOfGoods = Number(row.cost_of_goods || 0);
    const operatingExpenses = Number(expenseRow.operating_expenses || 0);
    const grossProfit = revenue - costOfGoods - Number(row.discounts || 0);
    res.json({
      ok: true,
      from,
      to,
      profitLoss: {
        ...row,
        operating_expenses: operatingExpenses,
        gross_profit: grossProfit,
        net_profit: grossProfit - operatingExpenses,
      },
    });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Supplier Statements / Accounts Payable
// ============================================================================

function supplierBranchFilter(alias, scope, params) {
  if (scope.branchIds == null) {
    return '';
  }
  params.push(scope.branchIds);
  return ` AND COALESCE(${alias}.branch_id, 'main_branch') = ANY($${params.length}::text[])`;
}

function supplierAgingColumns(alias = 'p') {
  const dueDate = `NULLIF(${alias}.due_date, '')::date`;
  return `
    COALESCE(SUM(CASE
      WHEN ${dueDate} IS NULL OR ${dueDate} >= CURRENT_DATE
      THEN ${alias}.balance_due ELSE 0 END), 0) AS current_amount,
    COALESCE(SUM(CASE
      WHEN ${dueDate} < CURRENT_DATE AND CURRENT_DATE - ${dueDate} BETWEEN 1 AND 30
      THEN ${alias}.balance_due ELSE 0 END), 0) AS d1_30_amount,
    COALESCE(SUM(CASE
      WHEN CURRENT_DATE - ${dueDate} BETWEEN 31 AND 60
      THEN ${alias}.balance_due ELSE 0 END), 0) AS d31_60_amount,
    COALESCE(SUM(CASE
      WHEN CURRENT_DATE - ${dueDate} BETWEEN 61 AND 90
      THEN ${alias}.balance_due ELSE 0 END), 0) AS d61_90_amount,
    COALESCE(SUM(CASE
      WHEN CURRENT_DATE - ${dueDate} > 90
      THEN ${alias}.balance_due ELSE 0 END), 0) AS over90_amount,
    COALESCE(SUM(${alias}.balance_due), 0) AS total_outstanding,
    COUNT(CASE WHEN ${alias}.balance_due > 0.009 THEN 1 END)::int AS open_invoice_count
  `;
}

app.get('/api/suppliers/aging', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.purchases);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const supplierParams = [businessContext.businessId];
    const supplierFilter = supplierBranchFilter('s', scope, supplierParams);
    const invoiceFilter =
      scope.branchIds == null
        ? ''
        : ` AND COALESCE(p.branch_id, 'main_branch') = ANY($${supplierParams.length}::text[])`;
    const result = await query(
      `SELECT
         s.id,
         s.name,
         s.phone,
         s.email,
         ${supplierAgingColumns('p')}
       FROM suppliers s
       JOIN purchase_invoices p
         ON p.business_id = s.business_id
        AND p.supplier_id = s.id
        AND p.deleted_at IS NULL
        AND p.balance_due > 0.009
        ${invoiceFilter}
       WHERE s.business_id = $1
         AND s.deleted_at IS NULL
         ${supplierFilter}
       GROUP BY s.id, s.name, s.phone, s.email
       ORDER BY total_outstanding DESC, s.name ASC`,
      supplierParams,
    );
    res.json({ ok: true, suppliers: result.rows });
  } catch (error) {
    next(error);
  }
});

app.get('/api/suppliers/:id/statement', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.purchases);
    const supplierId = normalizeOptionalText(req.params.id);
    if (!supplierId) {
      throw createHttpError(400, 'Supplier id is required.');
    }
    const scope = resolveDataScope(businessContext, req.query.branchId);

    const supplierParams = [businessContext.businessId, supplierId];
    const supplierFilter = supplierBranchFilter('s', scope, supplierParams);
    const supplierResult = await query(
      `SELECT *
       FROM suppliers s
       WHERE s.business_id = $1
         AND s.id = $2
         AND s.deleted_at IS NULL
         ${supplierFilter}
       LIMIT 1`,
      supplierParams,
    );
    const supplier = supplierResult.rows[0];
    if (!supplier) {
      throw createHttpError(404, 'Supplier not found.');
    }

    const ledgerParams = [businessContext.businessId, supplierId];
    const ledgerBranchFilter =
      scope.branchIds == null
        ? ''
        : ` AND COALESCE(branch_id, 'main_branch') = ANY($${ledgerParams.push(scope.branchIds)}::text[])`;
    const ledgerResult = await query(
      `SELECT *
       FROM (
         SELECT
           'purchase' AS entry_type,
           id,
           invoice_number AS reference,
           total_amount AS debit,
           0::double precision AS credit,
           balance_due,
           due_date,
           status,
           created_at AS entry_at,
           note
         FROM purchase_invoices
         WHERE business_id = $1
           AND supplier_id = $2
           AND deleted_at IS NULL
           ${ledgerBranchFilter}
         UNION ALL
         SELECT
           'payment' AS entry_type,
           id,
           reference,
           0::double precision AS debit,
           amount AS credit,
           0::double precision AS balance_due,
           NULL AS due_date,
           'paid' AS status,
           paid_at AS entry_at,
           note
         FROM supplier_payments
         WHERE business_id = $1
           AND supplier_id = $2
           AND deleted_at IS NULL
           ${ledgerBranchFilter}
       ) ledger
       ORDER BY entry_at ASC, entry_type ASC`,
      ledgerParams,
    );
    let runningBalance = 0;
    const ledger = ledgerResult.rows.map((row) => {
      runningBalance += Number(row.debit || 0) - Number(row.credit || 0);
      return { ...row, running_balance: runningBalance };
    });

    const invoiceParams = [businessContext.businessId, supplierId];
    const invoiceFilter = supplierBranchFilter('p', scope, invoiceParams);
    const agingResult = await query(
      `SELECT ${supplierAgingColumns('p')}
       FROM purchase_invoices p
       WHERE p.business_id = $1
         AND p.supplier_id = $2
         AND p.deleted_at IS NULL
         AND p.balance_due > 0.009
         ${invoiceFilter}`,
      invoiceParams,
    );
    const openInvoices = await query(
      `SELECT *
       FROM purchase_invoices p
       WHERE p.business_id = $1
         AND p.supplier_id = $2
         AND p.deleted_at IS NULL
         AND p.balance_due > 0.009
         ${invoiceFilter}
       ORDER BY
         CASE WHEN p.due_date IS NULL OR p.due_date = '' THEN 1 ELSE 0 END,
         p.due_date ASC,
         p.created_at ASC`,
      invoiceParams,
    );

    res.json({
      ok: true,
      supplier,
      aging: agingResult.rows[0] || null,
      ledger,
      openInvoices: openInvoices.rows,
    });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Product Serials / Warranty Tracking
// ============================================================================

function normalizeSerialStatus(value) {
  const clean = normalizeOptionalText(value)?.toLowerCase();
  if (
    clean === 'available' ||
    clean === 'sold' ||
    clean === 'reserved' ||
    clean === 'warranty' ||
    clean === 'returned'
  ) {
    return clean;
  }
  return 'available';
}

app.get('/api/serials', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.serialTracking);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const where = ['ps.business_id = $1', 'ps.deleted_at IS NULL'];
    const params = [businessContext.businessId];
    const productId = normalizeOptionalText(req.query.productId);
    const serial = normalizeOptionalText(req.query.serialNumber || req.query.serial);
    const status = normalizeOptionalText(req.query.status);
    if (productId) {
      where.push(`ps.product_id = $${params.length + 1}`);
      params.push(productId);
    }
    if (serial) {
      where.push(`LOWER(ps.serial_number) = LOWER($${params.length + 1})`);
      params.push(serial);
    }
    if (status) {
      where.push(`ps.status = $${params.length + 1}`);
      params.push(normalizeSerialStatus(status));
    }
    if (scope.branchIds != null) {
      where.push(
        `COALESCE(ps.branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`,
      );
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT
         ps.*,
         p.name AS product_name,
         pv.name AS variant_name
       FROM product_serials ps
       LEFT JOIN products p
         ON p.business_id = ps.business_id AND p.id = ps.product_id
       LEFT JOIN product_variants pv
         ON pv.business_id = ps.business_id AND pv.id = ps.variant_id
       WHERE ${where.join(' AND ')}
       ORDER BY ps.updated_at DESC, ps.serial_number ASC
       LIMIT 500`,
      params,
    );
    res.json({ ok: true, serials: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.post('/api/serials', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.serialTracking);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const productId = normalizeOptionalText(req.body?.productId || req.body?.product_id);
    if (!productId) {
      throw createHttpError(400, 'productId is required.');
    }
    const rawSerials = Array.isArray(req.body?.serialNumbers)
      ? req.body.serialNumbers
      : Array.isArray(req.body?.serial_numbers)
        ? req.body.serial_numbers
        : [req.body?.serialNumber || req.body?.serial_number];
    const serialNumbers = [
      ...new Set(rawSerials.map(normalizeOptionalText).filter(Boolean)),
    ];
    if (!serialNumbers.length) {
      throw createHttpError(400, 'At least one serial number is required.');
    }
    const scope = resolveDataScope(businessContext, req.body?.branchId || req.body?.branch_id);
    const branchId = scope.branchIds?.[0] || 'main_branch';
    const now = new Date().toISOString();
    const inserted = await withTransaction(async (client) => {
      const product = await client.query(
        `SELECT id
         FROM products
         WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL
         LIMIT 1`,
        [businessContext.businessId, productId],
      );
      if (!product.rows.length) {
        throw createHttpError(404, 'Product not found.');
      }
      const rows = [];
      for (const serialNumber of serialNumbers) {
        const duplicate = await client.query(
          `SELECT id
           FROM product_serials
           WHERE business_id = $1
             AND LOWER(serial_number) = LOWER($2)
             AND deleted_at IS NULL
           LIMIT 1`,
          [businessContext.businessId, serialNumber],
        );
        if (duplicate.rows.length) {
          continue;
        }
        const id = crypto.randomUUID();
        const result = await client.query(
          `INSERT INTO product_serials (
             id, business_id, branch_id, product_id, variant_id, stock_batch_id,
             purchase_id, serial_number, status, warranty_expires_at, note,
             created_at, updated_at, sync_status, server_revision
           ) VALUES (
             $1, $2, $3, $4, $5, $6, $7, $8, 'available', $9, $10,
             $11, $11, 'synced', nextval('sync_revision_seq')
           )
           RETURNING *`,
          [
            id,
            businessContext.businessId,
            branchId,
            productId,
            normalizeOptionalText(req.body?.variantId || req.body?.variant_id) ||
              null,
            normalizeOptionalText(
              req.body?.stockBatchId || req.body?.stock_batch_id,
            ) || null,
            normalizeOptionalText(req.body?.purchaseId || req.body?.purchase_id) ||
              null,
            serialNumber,
            normalizeOptionalText(
              req.body?.warrantyExpiresAt || req.body?.warranty_expires_at,
            ) || null,
            normalizeOptionalText(req.body?.note) || null,
            now,
          ],
        );
        rows.push(result.rows[0]);
      }
      return rows;
    });
    res.json({ ok: true, serials: inserted });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Stocktake / Cycle Counting
// ============================================================================

function normalizeStocktakeStatus(value) {
  const clean = normalizeOptionalText(value)?.toLowerCase();
  if (clean === 'completed' || clean === 'cancelled' || clean === 'draft') {
    return clean;
  }
  return 'draft';
}

app.get('/api/stocktakes', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.stocktake);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId];
    const where = ['s.business_id = $1', 's.deleted_at IS NULL'];
    const status = normalizeOptionalText(req.query.status);
    if (status && status !== 'all') {
      where.push(`s.status = $${params.length + 1}`);
      params.push(normalizeStocktakeStatus(status));
    }
    if (scope.branchIds != null) {
      where.push(
        `COALESCE(s.branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`,
      );
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT
         s.*,
         COUNT(i.id)::int AS item_count,
         COUNT(i.id) FILTER (WHERE i.status = 'counted')::int AS counted_count,
         COALESCE(SUM(ABS(COALESCE(i.variance_qty, 0))), 0)::double precision AS total_variance
       FROM stocktake_sessions s
       LEFT JOIN stocktake_items i
         ON i.business_id = s.business_id
        AND i.session_id = s.id
        AND i.deleted_at IS NULL
       WHERE ${where.join(' AND ')}
       GROUP BY s.id
       ORDER BY s.updated_at DESC, s.created_at DESC
       LIMIT 200`,
      params,
    );
    res.json({ ok: true, sessions: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.post('/api/stocktakes', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.stocktake);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const scope = resolveDataScope(businessContext, req.body?.branchId || req.body?.branch_id);
    const branchId = scope.branchIds?.[0] || 'main_branch';
    const name =
      normalizeOptionalText(req.body?.name) ||
      `Stocktake ${new Date().toISOString().slice(0, 10)}`;
    const note = normalizeOptionalText(req.body?.note) || null;
    const now = new Date().toISOString();
    const session = await withTransaction(async (client) => {
      const sessionId = crypto.randomUUID();
      const sessionResult = await client.query(
        `INSERT INTO stocktake_sessions (
           id, business_id, branch_id, name, status, started_by, started_at,
           note, created_at, updated_at, sync_status, server_revision
         ) VALUES (
           $1, $2, $3, $4, 'draft', $5, $6, $7, $6, $6, 'synced',
           nextval('sync_revision_seq')
         )
         RETURNING *`,
        [
          sessionId,
          businessContext.businessId,
          branchId,
          name,
          businessContext.userId || null,
          now,
          note,
        ],
      );
      const products = await client.query(
        `SELECT id, name, stock, stock_unit, unit, cost
         FROM products
         WHERE business_id = $1
           AND deleted_at IS NULL
           AND COALESCE(branch_id, 'main_branch') = $2
           AND COALESCE(track_stock, 1) <> 0
         ORDER BY name ASC`,
        [businessContext.businessId, branchId],
      );
      for (const product of products.rows) {
        await client.query(
          `INSERT INTO stocktake_items (
             id, business_id, branch_id, session_id, product_id, product_name,
             expected_qty, counted_qty, variance_qty, unit, unit_cost, status,
             created_at, updated_at, sync_status, server_revision
           ) VALUES (
             $1, $2, $3, $4, $5, $6, $7, NULL, 0, $8, $9, 'pending',
             $10, $10, 'synced', nextval('sync_revision_seq')
           )`,
          [
            crypto.randomUUID(),
            businessContext.businessId,
            branchId,
            sessionId,
            product.id,
            product.name,
            Number(product.stock || 0),
            product.stock_unit || product.unit || 'pcs',
            Number(product.cost || 0),
            now,
          ],
        );
      }
      return sessionResult.rows[0];
    });
    res.json({ ok: true, session });
  } catch (error) {
    next(error);
  }
});

app.get('/api/stocktakes/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.stocktake);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId, req.params.id];
    let branchFilter = '';
    if (scope.branchIds != null) {
      branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`;
      params.push(scope.branchIds);
    }
    const sessionResult = await query(
      `SELECT *
       FROM stocktake_sessions
       WHERE business_id = $1
         AND id = $2
         AND deleted_at IS NULL
         ${branchFilter}
       LIMIT 1`,
      params,
    );
    if (!sessionResult.rows.length) {
      throw createHttpError(404, 'Stocktake not found.');
    }
    const items = await query(
      `SELECT *
       FROM stocktake_items
       WHERE business_id = $1
         AND session_id = $2
         AND deleted_at IS NULL
       ORDER BY product_name ASC`,
      [businessContext.businessId, req.params.id],
    );
    res.json({ ok: true, session: sessionResult.rows[0], items: items.rows });
  } catch (error) {
    next(error);
  }
});

app.put('/api/stocktakes/:id/items/:itemId', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.stocktake);
    const countedQty = Number(req.body?.countedQty ?? req.body?.counted_qty);
    if (!Number.isFinite(countedQty) || countedQty < 0) {
      throw createHttpError(400, 'countedQty must be zero or greater.');
    }
    const note = normalizeOptionalText(req.body?.note) || null;
    const now = new Date().toISOString();
    const result = await query(
      `UPDATE stocktake_items
       SET counted_qty = $1,
           variance_qty = $1 - COALESCE(expected_qty, 0),
           status = 'counted',
           note = $2,
           counted_at = $3,
           updated_at = $3,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $4
         AND session_id = $5
         AND id = $6
         AND deleted_at IS NULL
       RETURNING *`,
      [countedQty, note, now, businessContext.businessId, req.params.id, req.params.itemId],
    );
    if (!result.rows.length) {
      throw createHttpError(404, 'Stocktake item not found.');
    }
    await query(
      `UPDATE stocktake_sessions
       SET updated_at = $1,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $2 AND id = $3`,
      [now, businessContext.businessId, req.params.id],
    );
    res.json({ ok: true, item: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.post('/api/stocktakes/:id/complete', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.stocktake);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const now = new Date().toISOString();
    const result = await query(
      `UPDATE stocktake_sessions
       SET status = 'completed',
           completed_by = $1,
           completed_at = $2,
           updated_at = $2,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $3
         AND id = $4
         AND deleted_at IS NULL
       RETURNING *`,
      [businessContext.userId || null, now, businessContext.businessId, req.params.id],
    );
    if (!result.rows.length) {
      throw createHttpError(404, 'Stocktake not found.');
    }
    res.json({ ok: true, session: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.post('/api/stocktakes/:id/cancel', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.stocktake);
    const now = new Date().toISOString();
    const result = await query(
      `UPDATE stocktake_sessions
       SET status = 'cancelled',
           updated_at = $1,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $2
         AND id = $3
         AND deleted_at IS NULL
       RETURNING *`,
      [now, businessContext.businessId, req.params.id],
    );
    if (!result.rows.length) {
      throw createHttpError(404, 'Stocktake not found.');
    }
    res.json({ ok: true, session: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// SMS Marketing Campaigns
// ============================================================================

function normalizeCampaignSegment(value) {
  const clean = normalizeOptionalText(value)?.toLowerCase();
  if (clean === 'debtors' || clean === 'loyalty' || clean === 'inactive') {
    return clean;
  }
  return 'all';
}

function personalizeCampaignMessage(message, customer) {
  return String(message || '').replace(
    /\{name\}/gi,
    customer.name || 'Customer',
  );
}

async function loadCampaignRecipients(businessContext, segment, branchId) {
  const params = [businessContext.businessId];
  const where = [
    'business_id = $1',
    'deleted_at IS NULL',
    "COALESCE(phone, '') <> ''",
  ];
  if (branchId) {
    where.push(`COALESCE(branch_id, 'main_branch') = $${params.length + 1}`);
    params.push(branchId);
  }
  if (segment === 'debtors') {
    where.push('COALESCE(balance, 0) > 0');
  } else if (segment === 'loyalty') {
    where.push('COALESCE(loyalty_points, 0) > 0');
  } else if (segment === 'inactive') {
    where.push(
      `id NOT IN (
        SELECT DISTINCT customer_id
        FROM sales
        WHERE business_id = $1
          AND customer_id IS NOT NULL
          AND deleted_at IS NULL
          AND created_at >= NOW() - INTERVAL '60 days'
      )`,
    );
  }
  const rows = await query(
    `SELECT id, name, phone
     FROM customers
     WHERE ${where.join(' AND ')}
     ORDER BY name ASC
     LIMIT 1000`,
    params,
  );
  return rows.rows;
}

app.get('/api/campaigns', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.smsCampaigns);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    if (scope.branchIds != null) {
      where.push(
        `COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`,
      );
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT *
       FROM sms_campaigns
       WHERE ${where.join(' AND ')}
       ORDER BY updated_at DESC, created_at DESC
       LIMIT 200`,
      params,
    );
    res.json({ ok: true, campaigns: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.post('/api/campaigns', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.smsCampaigns);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const scope = resolveDataScope(businessContext, req.body?.branchId || req.body?.branch_id);
    const branchId = scope.branchIds?.[0] || 'main_branch';
    const name = normalizeOptionalText(req.body?.name);
    const message = normalizeOptionalText(req.body?.message || req.body?.body);
    if (!name) throw createHttpError(400, 'Campaign name is required.');
    if (!message) throw createHttpError(400, 'Campaign message is required.');
    const segment = normalizeCampaignSegment(req.body?.segment);
    const recipients = await loadCampaignRecipients(businessContext, segment, branchId);
    const now = new Date().toISOString();
    const id = crypto.randomUUID();
    const result = await query(
      `INSERT INTO sms_campaigns (
         id, business_id, branch_id, name, segment, message, recipient_count,
         sent_count, failed_count, status, recipient_snapshot_json, created_by,
         created_at, updated_at, sync_status, server_revision
       ) VALUES (
         $1, $2, $3, $4, $5, $6, $7, 0, 0, 'draft', $8, $9, $10, $10,
         'synced', nextval('sync_revision_seq')
       )
       RETURNING *`,
      [
        id,
        businessContext.businessId,
        branchId,
        name,
        segment,
        message,
        recipients.length,
        JSON.stringify(recipients),
        businessContext.userId || null,
        now,
      ],
    );
    res.json({ ok: true, campaign: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.put('/api/campaigns/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.smsCampaigns);
    const name = normalizeOptionalText(req.body?.name);
    const message = normalizeOptionalText(req.body?.message || req.body?.body);
    if (!name) throw createHttpError(400, 'Campaign name is required.');
    if (!message) throw createHttpError(400, 'Campaign message is required.');
    const segment = normalizeCampaignSegment(req.body?.segment);
    const branchId = normalizeOptionalText(req.body?.branchId || req.body?.branch_id);
    const recipients = await loadCampaignRecipients(
      businessContext,
      segment,
      branchId || null,
    );
    const now = new Date().toISOString();
    const result = await query(
      `UPDATE sms_campaigns
       SET name = $1,
           segment = $2,
           message = $3,
           recipient_count = $4,
           recipient_snapshot_json = $5,
           updated_at = $6,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $7
         AND id = $8
         AND status = 'draft'
         AND deleted_at IS NULL
       RETURNING *`,
      [
        name,
        segment,
        message,
        recipients.length,
        JSON.stringify(recipients),
        now,
        businessContext.businessId,
        req.params.id,
      ],
    );
    if (!result.rows.length) {
      throw createHttpError(404, 'Draft campaign not found.');
    }
    res.json({ ok: true, campaign: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.delete('/api/campaigns/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.smsCampaigns);
    const now = new Date().toISOString();
    await query(
      `UPDATE sms_campaigns
       SET deleted_at = $1,
           updated_at = $1,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $2 AND id = $3`,
      [now, businessContext.businessId, req.params.id],
    );
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

app.post('/api/campaigns/:id/send', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.smsCampaigns);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const campaignResult = await query(
      `SELECT *
       FROM sms_campaigns
       WHERE business_id = $1
         AND id = $2
         AND deleted_at IS NULL
       LIMIT 1`,
      [businessContext.businessId, req.params.id],
    );
    if (!campaignResult.rows.length) {
      throw createHttpError(404, 'Campaign not found.');
    }
    const campaign = campaignResult.rows[0];
    let recipients = [];
    try {
      recipients = JSON.parse(campaign.recipient_snapshot_json || '[]');
    } catch (_) {
      recipients = [];
    }
    if (!Array.isArray(recipients) || !recipients.length) {
      recipients = await loadCampaignRecipients(
        businessContext,
        normalizeCampaignSegment(campaign.segment),
        campaign.branch_id || null,
      );
    }
    let sent = 0;
    let failed = 0;
    let lastError = null;
    for (const customer of recipients) {
      try {
        await sendBusinessMessage({
          businessContext,
          userId: businessContext.userId,
          channel: 'sms',
          recipient: customer.phone,
          body: personalizeCampaignMessage(campaign.message, customer),
          metadata: {
            campaignId: campaign.id,
            campaignName: campaign.name,
            customerId: customer.id,
          },
        });
        sent += 1;
      } catch (error) {
        failed += 1;
        lastError = error.message || 'Message failed';
      }
    }
    const now = new Date().toISOString();
    const updated = await query(
      `UPDATE sms_campaigns
       SET status = $1,
           recipient_count = $2,
           sent_count = $3,
           failed_count = $4,
           last_error = $5,
           sent_at = $6,
           updated_at = $6,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $7 AND id = $8
       RETURNING *`,
      [
        failed > 0 && sent === 0 ? 'failed' : 'sent',
        recipients.length,
        sent,
        failed,
        lastError,
        now,
        businessContext.businessId,
        campaign.id,
      ],
    );
    res.json({ ok: true, campaign: updated.rows[0] });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Exchange Rates / Multi-Currency
// ============================================================================

app.get('/api/exchange-rates', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.multiCurrency);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    if (scope.branchIds != null) {
      where.push(
        `COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`,
      );
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT *
       FROM exchange_rates
       WHERE ${where.join(' AND ')}
       ORDER BY is_active DESC, updated_at DESC
       LIMIT 100`,
      params,
    );
    res.json({ ok: true, rates: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.post('/api/exchange-rates', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.multiCurrency);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const baseCurrency = normalizeOptionalText(
      req.body?.baseCurrency || req.body?.base_currency,
    );
    const quoteCurrency = normalizeOptionalText(
      req.body?.quoteCurrency || req.body?.quote_currency,
    );
    const rate = Number(req.body?.rate);
    if (!baseCurrency) throw createHttpError(400, 'baseCurrency is required.');
    if (!quoteCurrency) throw createHttpError(400, 'quoteCurrency is required.');
    if (!Number.isFinite(rate) || rate <= 0) {
      throw createHttpError(400, 'rate must be greater than zero.');
    }
    const scope = resolveDataScope(businessContext, req.body?.branchId || req.body?.branch_id);
    const branchId = scope.branchIds?.[0] || 'main_branch';
    const isActive = req.body?.isActive ?? req.body?.is_active ?? true;
    const now = new Date().toISOString();
    const id = crypto.randomUUID();
    const row = await withTransaction(async (client) => {
      if (isActive) {
        await client.query(
          `UPDATE exchange_rates
           SET is_active = 0,
               updated_at = $1,
               sync_status = 'synced',
               server_revision = nextval('sync_revision_seq')
           WHERE business_id = $2
             AND COALESCE(branch_id, 'main_branch') = $3
             AND deleted_at IS NULL`,
          [now, businessContext.businessId, branchId],
        );
      }
      const result = await client.query(
        `INSERT INTO exchange_rates (
           id, business_id, branch_id, base_currency, quote_currency, rate,
           is_active, updated_by, created_at, updated_at, sync_status,
           server_revision
         ) VALUES (
           $1, $2, $3, $4, $5, $6, $7, $8, $9, $9, 'synced',
           nextval('sync_revision_seq')
         )
         RETURNING *`,
        [
          id,
          businessContext.businessId,
          branchId,
          baseCurrency,
          quoteCurrency,
          rate,
          isActive ? 1 : 0,
          businessContext.userId || null,
          now,
        ],
      );
      return result.rows[0];
    });
    res.json({ ok: true, rate: row });
  } catch (error) {
    next(error);
  }
});

app.delete('/api/exchange-rates/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.multiCurrency);
    const now = new Date().toISOString();
    await query(
      `UPDATE exchange_rates
       SET deleted_at = $1,
           updated_at = $1,
           sync_status = 'synced',
           server_revision = nextval('sync_revision_seq')
       WHERE business_id = $2 AND id = $3`,
      [now, businessContext.businessId, req.params.id],
    );
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Wastage / Spoilage
// ============================================================================

app.get('/api/wastage', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.wastage);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    if (scope.branchIds != null) {
      where.push(`COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`);
      params.push(scope.branchIds);
    }
    const limit = Math.max(1, Math.min(500, Number.parseInt(req.query.limit, 10) || 100));
    params.push(limit);
    const rows = await query(
      `SELECT * FROM wastage_logs WHERE ${where.join(' AND ')}
       ORDER BY recorded_at DESC, created_at DESC LIMIT $${params.length}`,
      params,
    );
    res.json({ ok: true, logs: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.post('/api/wastage', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.wastage);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const productId = normalizeOptionalText(req.body?.productId || req.body?.product_id);
    const quantity = Number(req.body?.quantity);
    if (!productId) throw createHttpError(400, 'productId is required.');
    if (!Number.isFinite(quantity) || quantity <= 0) throw createHttpError(400, 'quantity must be greater than zero.');
    const scope = resolveDataScope(businessContext, req.body?.branchId || req.body?.branch_id);
    const branchId = scope.branchIds?.[0] || 'main_branch';
    const reason = ['wastage', 'spoilage', 'damage', 'expiry', 'theft', 'other'].includes(req.body?.reason)
      ? req.body.reason : 'wastage';
    const now = new Date().toISOString();
    const log = await withTransaction(async (client) => {
      const product = await client.query(
        `SELECT * FROM products WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL
         AND COALESCE(branch_id, 'main_branch') = $3 FOR UPDATE`,
        [businessContext.businessId, productId, branchId],
      );
      if (product.rows.length === 0) throw createHttpError(404, 'Product not found.');
      const item = product.rows[0];
      if (Number(item.stock || 0) + 0.001 < quantity) throw createHttpError(400, 'Wastage quantity exceeds available stock.');
      await client.query(
        `UPDATE products SET stock = stock - $1, updated_at = $2, sync_status = 'synced',
         server_revision = nextval('sync_revision_seq') WHERE business_id = $3 AND id = $4`,
        [quantity, now, businessContext.businessId, productId],
      );
      const result = await client.query(
        `INSERT INTO wastage_logs (id, business_id, branch_id, product_id, product_name, quantity,
           unit, unit_cost, reason, note, recorded_by, recorded_at, created_at, updated_at,
           sync_status, server_revision)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$12,$12,'synced',nextval('sync_revision_seq'))
         RETURNING *`,
        [crypto.randomUUID(), businessContext.businessId, branchId, productId, item.name,
          quantity, item.stock_unit || item.unit || 'pcs', item.cost || 0, reason,
          normalizeOptionalText(req.body?.note), businessContext.userId || null, now],
      );
      return result.rows[0];
    });
    res.status(201).json({ ok: true, log });
  } catch (error) {
    next(error);
  }
});

app.put('/api/wastage/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.wastage);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const reason = ['wastage', 'spoilage', 'damage', 'expiry', 'theft', 'other'].includes(req.body?.reason)
      ? req.body.reason : 'other';
    const now = new Date().toISOString();
    const result = await query(
      `UPDATE wastage_logs SET reason = $1, note = $2, updated_at = $3, sync_status = 'synced',
       server_revision = nextval('sync_revision_seq') WHERE business_id = $4 AND id = $5 AND deleted_at IS NULL RETURNING *`,
      [reason, normalizeOptionalText(req.body?.note), now, businessContext.businessId, req.params.id],
    );
    if (result.rows.length === 0) throw createHttpError(404, 'Wastage record not found.');
    res.json({ ok: true, log: result.rows[0] });
  } catch (error) { next(error); }
});

app.delete('/api/wastage/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.wastage);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const now = new Date().toISOString();
    const log = await withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE wastage_logs SET deleted_at = $1, updated_at = $1, sync_status = 'synced',
         server_revision = nextval('sync_revision_seq') WHERE business_id = $2 AND id = $3 AND deleted_at IS NULL RETURNING *`,
        [now, businessContext.businessId, req.params.id],
      );
      if (result.rows.length === 0) throw createHttpError(404, 'Wastage record not found.');
      const row = result.rows[0];
      await client.query(`UPDATE products SET stock = stock + $1, updated_at = $2, sync_status = 'synced',
        server_revision = nextval('sync_revision_seq') WHERE business_id = $3 AND id = $4`,
        [row.quantity, now, businessContext.businessId, row.product_id]);
      return row;
    });
    res.json({ ok: true, log });
  } catch (error) { next(error); }
});

// ============================================================================
// Loyalty & Rewards
// ============================================================================

// ============================================================================
// Restaurant / Hospitality
// ============================================================================

app.post('/api/online-orders', async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.body?.businessId || req.body?.business_id);
    if (!businessId) throw createHttpError(400, 'businessId is required.');
    const paymentMethod = ['manual', 'mpesa'].includes(req.body?.paymentMethod)
      ? req.body.paymentMethod : 'manual';
    let mpesaBusinessContext = null;
    if (paymentMethod === 'mpesa') {
      const businessResult = await query(
        `SELECT country_code FROM businesses WHERE id = $1 AND deleted_at IS NULL LIMIT 1`,
        [businessId],
      );
      const business = businessResult.rows[0];
      if (!business) throw createHttpError(404, 'Catalog not found.');
      mpesaBusinessContext = {
        businessId,
        countryCode: business.country_code || 'KE',
      };
      const mpesaStatus = await loadPosMpesaConfig(mpesaBusinessContext);
      if (!mpesaStatus.active) {
        throw createHttpError(400, mpesaStatus.message || 'M-Pesa is not ready for this storefront.');
      }
    }
    const order = await createPublicCatalogOrder(businessId, req.body || {});
    const trackingCode = `DLV-${order.id.replace(/-/g, '').slice(0, 8).toUpperCase()}`;
    const deliveryStatus = order.fulfillmentMethod === 'delivery' ? 'pending' : null;
    let checkoutUrl = null;
    let paymentRequestId = null;
    await withTransaction(async (client) => {
      await client.query(`UPDATE public_catalog_orders SET payment_method = $1, payment_status = $2, delivery_status = $3, tracking_code = $4, updated_at = NOW() WHERE id = $5`, [paymentMethod, paymentMethod === 'manual' ? 'pending' : 'initiated', deliveryStatus, trackingCode, order.id]);
      if (deliveryStatus) {
        await client.query(`INSERT INTO deliveries (id,business_id,branch_id,order_id,status,tracking_code,created_at,updated_at) VALUES ($1,$2,$3,$4,'pending',$5,NOW(),NOW())`, [crypto.randomUUID(), businessId, order.branchId, order.id, trackingCode]);
      }
    });
    if (paymentMethod === 'mpesa') {
      const payment = await createMpesaPosCheckout({
        businessContext: mpesaBusinessContext,
        amountMinor: Math.round(Number(order.subtotal || 0) * 100),
        phoneNumber: order.phone,
        metadata: {
          publicCatalogOrder: {
            orderId: order.id,
            orderNumber: order.orderNumber,
          },
        },
      });
      paymentRequestId = payment.id;
      await query(
        `UPDATE public_catalog_orders SET payment_reference = $1, updated_at = NOW() WHERE id = $2`,
        [payment.id, order.id],
      );
    }
    if (paymentMethod === 'paypal') {
      const gateway = await loadPaymentGateway('paypal');
      if (!gateway?.isActive) throw createHttpError(400, 'PayPal is not active.');
      assertPublicPaymentReturnUrl();
      const paypalConfig = resolvePayPalGatewayConfig(gateway);
      const accessToken = await getPayPalAccessToken(paypalConfig);
      const fetch = (await import('node-fetch')).default;
      const response = await fetch(`${paypalConfig.baseUrl}/v2/checkout/orders`, {
        method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json', 'PayPal-Request-Id': order.id },
        body: JSON.stringify({ intent: 'CAPTURE', purchase_units: [{ reference_id: order.id, description: `Online order ${order.orderNumber}`, amount: { currency_code: 'USD', value: Number(order.subtotal).toFixed(2) } }], application_context: { brand_name: 'Piki POS', user_action: 'PAY_NOW', return_url: `${config.publicBaseUrl}/api/online-orders/paypal/return?orderId=${encodeURIComponent(order.id)}`, cancel_url: `${config.publicBaseUrl}/?order=${encodeURIComponent(order.orderNumber)}&payment=cancelled` } }),
      });
      const body = await readMaybeJson(response);
      checkoutUrl = (body.links || []).find((link) => link.rel === 'approve')?.href || null;
      if (!response.ok || !body.id || !checkoutUrl) throw createHttpError(502, body.message || 'PayPal checkout could not be created.');
      await query(`UPDATE public_catalog_orders SET payment_reference = $1, updated_at = NOW() WHERE id = $2`, [body.id, order.id]);
    }
    res.status(201).json({
      ok: true,
      order: {
        ...order,
        paymentMethod,
        paymentStatus: paymentMethod === 'manual' ? 'pending' : 'initiated',
        paymentRequestId,
        trackingCode,
        deliveryStatus,
        checkoutUrl,
      },
    });
  } catch (error) { next(error); }
});

app.get('/api/delivery/zones', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.delivery);
    const scope = resolveDataScope(context, req.query.branchId);
    const params = [context.businessId];
    let branchFilter = '';
    if (scope.branchIds != null) { branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`; params.push(scope.branchIds); }
    const rows = await query(`SELECT * FROM delivery_zones WHERE business_id = $1 AND deleted_at IS NULL ${branchFilter} ORDER BY name`, params);
    res.json({ ok: true, zones: rows.rows });
  } catch (error) { next(error); }
});

app.post('/api/delivery/zones', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.delivery);
    ensureRoleAtLeast(context, 'MANAGER');
    const name = normalizeOptionalText(req.body?.name);
    if (!name) throw createHttpError(400, 'Zone name is required.');
    const scope = resolveDataScope(context, req.body?.branchId);
    const result = await query(`INSERT INTO delivery_zones (id,business_id,branch_id,name,fee,minimum_order,is_active,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,$7,NOW(),NOW()) RETURNING *`, [crypto.randomUUID(), context.businessId, scope.branchIds?.[0] || 'main_branch', name, Math.max(0, Number(req.body?.fee) || 0), Math.max(0, Number(req.body?.minimumOrder) || 0), req.body?.isActive === false ? 0 : 1]);
    res.status(201).json({ ok: true, zone: result.rows[0] });
  } catch (error) { next(error); }
});

app.put('/api/delivery/:id/status', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.delivery);
    const status = ['pending', 'assigned', 'out_for_delivery', 'delivered', 'failed', 'cancelled'].includes(req.body?.status) ? req.body.status : null;
    if (!status) throw createHttpError(400, 'Invalid delivery status.');
    const result = await query(`UPDATE deliveries SET status = $1, rider_name = COALESCE($2, rider_name), rider_phone = COALESCE($3, rider_phone), delivered_at = CASE WHEN $1 = 'delivered' THEN NOW() ELSE delivered_at END, updated_at = NOW() WHERE business_id = $4 AND id = $5 RETURNING *`, [status, normalizeOptionalText(req.body?.riderName), normalizeOptionalText(req.body?.riderPhone), context.businessId, req.params.id]);
    if (result.rows.length === 0) throw createHttpError(404, 'Delivery not found.');
    await query(`UPDATE public_catalog_orders SET delivery_status = $1, updated_at = NOW() WHERE business_id = $2 AND id = $3`, [status, context.businessId, result.rows[0].order_id]);
    res.json({ ok: true, delivery: result.rows[0] });
  } catch (error) { next(error); }
});

app.get('/api/online-orders/paypal/return', async (req, res, next) => {
  try {
    const orderId = normalizeOptionalText(req.query?.orderId);
    const paypalOrderId = normalizeOptionalText(req.query?.token);
    if (!orderId || !paypalOrderId) throw createHttpError(400, 'PayPal order is missing.');
    const orderResult = await query(`SELECT * FROM public_catalog_orders WHERE id = $1 AND payment_reference = $2 LIMIT 1`, [orderId, paypalOrderId]);
    const order = orderResult.rows[0];
    if (!order) throw createHttpError(404, 'Online order not found.');
    const gateway = await loadPaymentGateway('paypal');
    if (!gateway?.isActive) throw createHttpError(400, 'PayPal is not active.');
    const paypalConfig = resolvePayPalGatewayConfig(gateway);
    const accessToken = await getPayPalAccessToken(paypalConfig);
    const fetch = (await import('node-fetch')).default;
    const response = await fetch(`${paypalConfig.baseUrl}/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}/capture`, { method: 'POST', headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: '{}' });
    const body = await readMaybeJson(response);
    if (!response.ok || body.status !== 'COMPLETED') throw createHttpError(400, body.message || 'PayPal payment was not completed.');
    await query(`UPDATE public_catalog_orders SET payment_status = 'paid', status = CASE WHEN status = 'pending' THEN 'accepted' ELSE status END, updated_at = NOW() WHERE id = $1`, [orderId]);
    res.redirect(`${config.publicBaseUrl}/?order=${encodeURIComponent(shortOrderNumber(orderId))}&payment=success`);
  } catch (error) { next(error); }
});

// ============================================================================
// Customer self-service portal
// ============================================================================

app.post('/api/customer-portal/request-code', async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.body?.businessId);
    const email = normalizeCustomerPortalEmail(req.body?.email);
    if (!businessId || !email) {
      throw createHttpError(400, 'businessId and a valid email address are required.');
    }
    const result = await requestCustomerPortalEmailCode({ businessId, email });
    // Keep the response generic to avoid exposing whether an email is a customer account.
    res.json({ ok: true, ...result });
  } catch (error) { next(error); }
});

app.post('/api/customer-portal/login', async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.body?.businessId);
    const email = normalizeCustomerPortalEmail(req.body?.email);
    const code = String(req.body?.code || '').replace(/\D/g, '');
    if (!businessId || !email || !/^\d{6}$/.test(code)) {
      throw createHttpError(400, 'businessId, email, and a 6-digit verification code are required.');
    }
    const customer = await verifyCustomerPortalEmailCode({ businessId, email, code });
    const token = jwt.sign(
      { type: 'customer_portal', businessId, customerId: customer.id },
      config.platformJwtSecret,
      { expiresIn: '2h' },
    );
    res.json({ ok: true, token, customer: { id: customer.id, name: customer.name, balance: customer.balance } });
  } catch (error) { next(error); }
});

app.get('/api/customer-portal/statement', async (req, res, next) => {
  try {
    const portal = requireCustomerPortalSession(req);
    const customer = await query(`SELECT id,name,email,balance FROM customers WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL LIMIT 1`, [portal.businessId, portal.customerId]);
    if (!customer.rows[0]) throw createHttpError(404, 'Customer account not found.');
    const sales = await query(`SELECT id,created_at,total_amount,amount_paid,balance_due,due_date,status FROM sales WHERE business_id = $1 AND customer_id = $2 AND deleted_at IS NULL AND balance_due > 0 ORDER BY created_at DESC`, [portal.businessId, portal.customerId]);
    res.json({ ok: true, customer: customer.rows[0], sales: sales.rows });
  } catch (error) { next(error); }
});

app.post('/api/customer-portal/payments/mpesa', async (req, res, next) => {
  try {
    const portal = requireCustomerPortalSession(req);
    const amount = Number(req.body?.amount);
    const amountMinor = Math.round(amount * 100);
    const phoneNumber = normalizeOptionalText(req.body?.phoneNumber);
    if (!Number.isFinite(amount) || amountMinor <= 0 || !phoneNumber) {
      throw createHttpError(400, 'A positive payment amount and M-Pesa phone number are required.');
    }
    const account = await query(
      `SELECT c.balance, b.country_code
       FROM customers c JOIN businesses b ON b.id = c.business_id
       WHERE c.business_id = $1 AND c.id = $2 AND c.deleted_at IS NULL
       LIMIT 1`,
      [portal.businessId, portal.customerId],
    );
    const customer = account.rows[0];
    if (!customer) throw createHttpError(404, 'Customer account not found.');
    if (amount - Number(customer.balance || 0) > 0.009) {
      throw createHttpError(400, 'Payment cannot be greater than the current outstanding balance.');
    }
    const payment = await createMpesaPosCheckout({
      businessContext: { businessId: portal.businessId, countryCode: customer.country_code || 'KE' },
      amountMinor,
      phoneNumber,
      metadata: { customerPortal: { customerId: portal.customerId } },
    });
    res.json({ ok: true, payment: customerPortalPaymentResponse(payment) });
  } catch (error) { next(normalizeRouteError(error)); }
});

app.get('/api/customer-portal/payments/:id', async (req, res, next) => {
  try {
    const portal = requireCustomerPortalSession(req);
    const payment = await loadPosPayment({ businessId: portal.businessId, paymentId: req.params.id });
    if (!payment || payment.metadata?.customerPortal?.customerId !== portal.customerId) {
      throw createHttpError(404, 'Payment request not found.');
    }
    res.json({ ok: true, payment: customerPortalPaymentResponse(payment) });
  } catch (error) { next(normalizeRouteError(error)); }
});

app.get('/api/purchase-orders/approvals', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req);
    ensureRoleAtLeast(context, 'MANAGER');
    const scope = resolveDataScope(context, req.query.branchId);
    const params = [context.businessId];
    let branchFilter = '';
    if (scope.branchIds != null) { branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`; params.push(scope.branchIds); }
    const rows = await query(`SELECT * FROM purchase_orders WHERE business_id = $1 AND status = 'pending_approval' AND deleted_at IS NULL ${branchFilter} ORDER BY submitted_at ASC`, params);
    res.json({ ok: true, orders: rows.rows });
  } catch (error) { next(error); }
});

app.post('/api/purchase-orders/:id/submit', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    const threshold = Math.max(0, Number(req.body?.threshold) || 50000);
    const now = new Date().toISOString();
    const result = await query(`UPDATE purchase_orders SET approval_required = CASE WHEN total_amount >= $1 THEN 1 ELSE 0 END, status = CASE WHEN total_amount >= $1 THEN 'pending_approval' ELSE 'approved' END, submitted_by = $2, submitted_at = $3, approved_by = CASE WHEN total_amount >= $1 THEN NULL ELSE $2 END, approved_at = CASE WHEN total_amount >= $1 THEN NULL ELSE $3 END, updated_at = $3, sync_status = 'synced', server_revision = nextval('sync_revision_seq') WHERE business_id = $4 AND id = $5 AND status = 'draft' AND deleted_at IS NULL RETURNING *`, [threshold, context.userId || null, now, context.businessId, req.params.id]);
    if (!result.rows.length) throw createHttpError(409, 'Only draft purchase orders can be submitted.');
    res.json({ ok: true, order: result.rows[0] });
  } catch (error) { next(error); }
});

app.post('/api/purchase-orders/:id/approval', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensureRoleAtLeast(context, 'MANAGER');
    const decision = req.body?.decision === 'reject' ? 'rejected' : req.body?.decision === 'approve' ? 'approved' : null;
    if (!decision) throw createHttpError(400, 'decision must be approve or reject.');
    const result = await query(`UPDATE purchase_orders SET status = $1, approved_by = $2, approved_at = NOW(), approval_note = $3, updated_at = NOW(), sync_status = 'synced', server_revision = nextval('sync_revision_seq') WHERE business_id = $4 AND id = $5 AND status = 'pending_approval' AND deleted_at IS NULL RETURNING *`, [decision, context.userId || null, normalizeOptionalText(req.body?.note), context.businessId, req.params.id]);
    if (!result.rows.length) throw createHttpError(404, 'Pending purchase order not found.');
    res.json({ ok: true, order: result.rows[0] });
  } catch (error) { next(error); }
});

app.get('/api/customer-groups', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.customerSegments);
    const scope = resolveDataScope(context, req.query.branchId);
    const params = [context.businessId];
    let filter = '';
    if (scope.branchIds != null) { filter = `AND COALESCE(g.branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`; params.push(scope.branchIds); }
    const rows = await query(`SELECT g.*, COUNT(m.id)::int AS member_count FROM customer_groups g LEFT JOIN customer_group_members m ON m.group_id = g.id AND m.deleted_at IS NULL WHERE g.business_id = $1 AND g.deleted_at IS NULL ${filter} GROUP BY g.id ORDER BY g.name`, params);
    res.json({ ok: true, groups: rows.rows });
  } catch (error) { next(error); }
});

app.post('/api/customer-groups', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.customerSegments);
    const name = normalizeOptionalText(req.body?.name);
    if (!name) throw createHttpError(400, 'Group name is required.');
    const scope = resolveDataScope(context, req.body?.branchId);
    const now = new Date().toISOString();
    const result = await query(`INSERT INTO customer_groups (id,business_id,branch_id,name,description,color,created_by,created_at,updated_at,sync_status,server_revision) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$8,'synced',nextval('sync_revision_seq')) RETURNING *`, [crypto.randomUUID(), context.businessId, scope.branchIds?.[0] || 'main_branch', name, normalizeOptionalText(req.body?.description), normalizeOptionalText(req.body?.color), context.userId || null, now]);
    res.status(201).json({ ok: true, group: result.rows[0] });
  } catch (error) { next(error); }
});

app.put('/api/customer-groups/:id/members/:customerId', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.customerSegments);
    const scope = resolveDataScope(context, req.body?.branchId);
    const now = new Date().toISOString();
    await query(`INSERT INTO customer_group_members (id,business_id,branch_id,group_id,customer_id,created_at,updated_at,sync_status) VALUES ($1,$2,$3,$4,$5,$6,$6,'synced') ON CONFLICT (group_id,customer_id) DO UPDATE SET deleted_at = NULL, updated_at = EXCLUDED.updated_at`, [crypto.randomUUID(), context.businessId, scope.branchIds?.[0] || 'main_branch', req.params.id, req.params.customerId, now]);
    res.json({ ok: true });
  } catch (error) { next(error); }
});

app.delete('/api/customer-groups/:id/members/:customerId', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.customerSegments);
    await query(`UPDATE customer_group_members SET deleted_at = NOW(), updated_at = NOW(), sync_status = 'synced' WHERE business_id = $1 AND group_id = $2 AND customer_id = $3`, [context.businessId, req.params.id, req.params.customerId]);
    res.json({ ok: true });
  } catch (error) { next(error); }
});

app.get('/api/attendance', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.attendance);
    const scope = resolveDataScope(context, req.query.branchId);
    const params = [context.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    const userId = normalizeOptionalText(req.query.userId);
    if (userId) { where.push(`user_id = $${params.length + 1}`); params.push(userId); }
    if (scope.branchIds != null) { where.push(`COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`); params.push(scope.branchIds); }
    const rows = await query(`SELECT * FROM employee_attendance WHERE ${where.join(' AND ')} ORDER BY clock_in_at DESC LIMIT 500`, params);
    res.json({ ok: true, records: rows.rows });
  } catch (error) { next(error); }
});

app.post('/api/attendance/clock-in', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.attendance);
    const scope = resolveDataScope(context, req.body?.branchId);
    const branchId = scope.branchIds?.[0] || 'main_branch';
    const now = new Date().toISOString();
    const record = await withTransaction(async (client) => {
      const open = await client.query(`SELECT id FROM employee_attendance WHERE business_id = $1 AND user_id = $2 AND status = 'open' AND deleted_at IS NULL FOR UPDATE`, [context.businessId, context.userId]);
      if (open.rows.length) throw createHttpError(409, 'You are already clocked in.');
      const result = await client.query(`INSERT INTO employee_attendance (id,business_id,branch_id,user_id,user_name,clock_in_at,note,status,created_at,updated_at,sync_status,server_revision) VALUES ($1,$2,$3,$4,$5,$6,$7,'open',$6,$6,'synced',nextval('sync_revision_seq')) RETURNING *`, [crypto.randomUUID(), context.businessId, branchId, context.userId, context.userName || null, now, normalizeOptionalText(req.body?.note)]);
      return result.rows[0];
    });
    res.status(201).json({ ok: true, record });
  } catch (error) { next(error); }
});

app.post('/api/attendance/:id/clock-out', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.attendance);
    const result = await query(`UPDATE employee_attendance SET clock_out_at = NOW(), note = COALESCE($1, note), status = 'closed', updated_at = NOW(), sync_status = 'synced', server_revision = nextval('sync_revision_seq') WHERE business_id = $2 AND id = $3 AND user_id = $4 AND status = 'open' AND deleted_at IS NULL RETURNING *`, [normalizeOptionalText(req.body?.note), context.businessId, req.params.id, context.userId]);
    if (!result.rows.length) throw createHttpError(404, 'Open attendance record not found.');
    res.json({ ok: true, record: result.rows[0] });
  } catch (error) { next(error); }
});

app.get('/api/attendance/report', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.attendance);
    ensureRoleAtLeast(context, 'MANAGER');
    const scope = resolveDataScope(context, req.query.branchId);
    const params = [context.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    if (scope.branchIds != null) { where.push(`COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`); params.push(scope.branchIds); }
    const rows = await query(`SELECT user_id, MAX(user_name) AS user_name, COUNT(*)::int AS shifts, COALESCE(SUM(EXTRACT(EPOCH FROM (COALESCE(clock_out_at, NOW()) - clock_in_at)) / 3600),0)::double precision AS hours_worked FROM employee_attendance WHERE ${where.join(' AND ')} GROUP BY user_id ORDER BY hours_worked DESC`, params);
    res.json({ ok: true, report: rows.rows });
  } catch (error) { next(error); }
});

app.get('/api/restaurant/tables', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.restaurantMode);
    const scope = resolveDataScope(context, req.query.branchId);
    const params = [context.businessId];
    let branchFilter = '';
    if (scope.branchIds != null) { branchFilter = `AND COALESCE(t.branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`; params.push(scope.branchIds); }
    const rows = await query(`SELECT t.*, o.id AS order_id, o.order_no, o.status AS order_status, o.guest_count, o.items_json, o.total, o.split_count FROM restaurant_tables t LEFT JOIN table_orders o ON o.id = t.current_order_id AND o.deleted_at IS NULL WHERE t.business_id = $1 AND t.deleted_at IS NULL ${branchFilter} ORDER BY COALESCE(t.area, ''), t.name`, params);
    res.json({ ok: true, tables: rows.rows });
  } catch (error) { next(error); }
});

app.post('/api/restaurant/tables', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.restaurantMode);
    ensureRoleAtLeast(context, 'MANAGER');
    const name = normalizeOptionalText(req.body?.name);
    if (!name) throw createHttpError(400, 'Table name is required.');
    const scope = resolveDataScope(context, req.body?.branchId);
    const now = new Date().toISOString();
    const result = await query(`INSERT INTO restaurant_tables (id,business_id,branch_id,name,area,seats,status,position_x,position_y,created_at,updated_at,sync_status,server_revision) VALUES ($1,$2,$3,$4,$5,$6,'available',0,0,$7,$7,'synced',nextval('sync_revision_seq')) RETURNING *`, [crypto.randomUUID(), context.businessId, scope.branchIds?.[0] || 'main_branch', name, normalizeOptionalText(req.body?.area), Math.max(1, Math.min(50, Number(req.body?.seats) || 2)), now]);
    res.status(201).json({ ok: true, table: result.rows[0] });
  } catch (error) { next(error); }
});

app.post('/api/restaurant/tables/:id/orders', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.restaurantMode);
    const now = new Date().toISOString();
    const order = await withTransaction(async (client) => {
      const table = await client.query(`SELECT * FROM restaurant_tables WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL FOR UPDATE`, [context.businessId, req.params.id]);
      if (table.rows.length === 0) throw createHttpError(404, 'Table not found.');
      if (table.rows[0].current_order_id) throw createHttpError(409, 'Table already has an open order.');
      const id = crypto.randomUUID();
      const result = await client.query(`INSERT INTO table_orders (id,business_id,branch_id,table_id,order_no,status,guest_count,items_json,subtotal,tax,discount,total,split_count,opened_by,opened_at,created_at,updated_at,sync_status,server_revision) VALUES ($1,$2,$3,$4,$5,'open',$6,'[]',0,0,0,0,1,$7,$8,$8,$8,'synced',nextval('sync_revision_seq')) RETURNING *`, [id, context.businessId, table.rows[0].branch_id || 'main_branch', req.params.id, `T${Date.now().toString().slice(-6)}`, Math.max(1, Number(req.body?.guestCount) || 1), context.userId || null, now]);
      await client.query(`UPDATE restaurant_tables SET status = 'occupied', current_order_id = $1, updated_at = $2, sync_status = 'synced', server_revision = nextval('sync_revision_seq') WHERE id = $3`, [id, now, req.params.id]);
      return result.rows[0];
    });
    res.status(201).json({ ok: true, order });
  } catch (error) { next(error); }
});

app.put('/api/restaurant/orders/:id', async (req, res, next) => {
  try {
    const context = await requireBusinessContext(req, { requireWrite: true });
    ensurePlanFeatureAllowed(context, FEATURE_KEYS.restaurantMode);
    const items = Array.isArray(req.body?.items) ? req.body.items : null;
    if (!items) throw createHttpError(400, 'items is required.');
    const subtotal = items.reduce((sum, item) => sum + Math.max(0, Number(item.quantity) || 0) * Math.max(0, Number(item.unit_price) || 0), 0);
    const now = new Date().toISOString();
    const result = await query(`UPDATE table_orders SET items_json = $1, subtotal = $2, total = $2, notes = $3, split_count = $4, updated_at = $5, sync_status = 'synced', server_revision = nextval('sync_revision_seq') WHERE business_id = $6 AND id = $7 AND deleted_at IS NULL RETURNING *`, [JSON.stringify(items), subtotal, normalizeOptionalText(req.body?.notes), Math.max(1, Math.min(20, Number(req.body?.splitCount) || 1)), now, context.businessId, req.params.id]);
    if (result.rows.length === 0) throw createHttpError(404, 'Table order not found.');
    res.json({ ok: true, order: result.rows[0] });
  } catch (error) { next(error); }
});

app.get('/api/loyalty/rules', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.loyalty);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId];
    let branchFilter = '';
    if (scope.branchIds != null) {
      branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`;
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT * FROM loyalty_rules
       WHERE business_id = $1 AND deleted_at IS NULL ${branchFilter}
       ORDER BY updated_at DESC LIMIT 1`,
      params,
    );
    res.json({ ok: true, rule: rows.rows[0] ?? null });
  } catch (error) {
    next(error);
  }
});

app.get('/api/loyalty/ledger', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.loyalty);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const customerId = normalizeOptionalText(req.query.customerId);
    const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    const params = [businessContext.businessId];
    if (customerId) {
      where.push(`customer_id = $${params.length + 1}`);
      params.push(customerId);
    }
    if (scope.branchIds != null) {
      where.push(
        `COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`,
      );
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT * FROM loyalty_ledger
       WHERE ${where.join(' AND ')}
       ORDER BY created_at DESC LIMIT ${limit}`,
      params,
    );
    res.json({ ok: true, ledger: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.get('/api/loyalty/points/:customerId', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.loyalty);
    const customerId = req.params.customerId;
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId, customerId];
    let branchFilter = '';
    if (scope.branchIds != null) {
      branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`;
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT loyalty_points FROM customers
       WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL ${branchFilter}
       LIMIT 1`,
      params,
    );
    const points = rows.rows.length
      ? Number(rows.rows[0].loyalty_points) || 0
      : 0;
    res.json({ ok: true, customerId, points });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Gift Cards / Vouchers
// ============================================================================

app.get('/api/gift-cards', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.giftCards);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    if (req.query.code) {
      where.push(`code ILIKE $${params.length + 1}`);
      params.push(`%${normalizeOptionalText(req.query.code)}%`);
    }
    if (req.query.activeOnly === 'true') {
      where.push('is_active = true');
    }
    if (req.query.customerId) {
      where.push(`customer_id = $${params.length + 1}`);
      params.push(normalizeOptionalText(req.query.customerId));
    }
    let branchFilter = '';
    if (scope.branchIds != null) {
      branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`;
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT * FROM gift_cards
       WHERE ${where.join(' AND ')} ${branchFilter}
       ORDER BY created_at DESC LIMIT 500`,
      params,
    );
    res.json({ ok: true, giftCards: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.post('/api/gift-cards', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.giftCards);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const scope = resolveDataScope(businessContext, req.body.branchId);
    const branchId = scope.branchId || 'main_branch';
    const code = normalizeText(req.body.code);
    if (!code) {
      throw createHttpError(400, 'A gift card code is required.');
    }
    const amount = Number(req.body.initialBalance || req.body.balance || 0);
    if (!Number.isFinite(amount) || amount < 0) {
      throw createHttpError(400, 'Initial balance must be zero or greater.');
    }
    const existing = await query(
      'SELECT id FROM gift_cards WHERE business_id = $1 AND code = $2 AND deleted_at IS NULL',
      [businessContext.businessId, code],
    );
    if (existing.rows.length) {
      throw createHttpError(409, 'A gift card with this code already exists.');
    }
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    await query(
      `INSERT INTO gift_cards (
        id, business_id, branch_id, code, customer_id, initial_balance,
        balance, currency, is_active, expires_at, note, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, $9, $10, $11, $11)`,
      [
        id,
        businessContext.businessId,
        branchId,
        code,
        normalizeOptionalText(req.body.customerId) || null,
        amount,
        amount,
        normalizeOptionalText(req.body.currency) || null,
        req.body.expiresAt ? toIsoString(req.body.expiresAt) : null,
        normalizeOptionalText(req.body.note) || null,
        now,
      ],
    );
    const row = await query('SELECT * FROM gift_cards WHERE id = $1', [id]);
    res.json({ ok: true, giftCard: row.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.get('/api/gift-cards/code/:code', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.giftCards);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId, normalizeText(req.params.code)];
    let branchFilter = '';
    if (scope.branchIds != null) {
      branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`;
      params.push(scope.branchIds);
    }
    const row = await query(
      `SELECT * FROM gift_cards
       WHERE business_id = $1 AND code = $2 AND deleted_at IS NULL ${branchFilter}
       LIMIT 1`,
      params,
    );
    if (!row.rows.length) {
      throw createHttpError(404, 'Gift card not found.');
    }
    res.json({ ok: true, giftCard: row.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.put('/api/gift-cards/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.giftCards);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const id = req.params.id;
    const row = await query(
      'SELECT * FROM gift_cards WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL',
      [id, businessContext.businessId],
    );
    if (!row.rows.length) {
      throw createHttpError(404, 'Gift card not found.');
    }
    const current = row.rows[0];
    const topUp = Number(req.body.topUp || 0);
    const fields = [];
    const params = [];
    let idx = 1;
    if (req.body.note !== undefined) {
      fields.push(`note = $${idx++}`);
      params.push(normalizeOptionalText(req.body.note) || null);
    }
    if (req.body.isActive !== undefined) {
      fields.push(`is_active = $${idx++}`);
      params.push(req.body.isActive ? true : false);
    }
    if (req.body.expiresAt !== undefined) {
      fields.push(`expires_at = $${idx++}`);
      params.push(req.body.expiresAt ? toIsoString(req.body.expiresAt) : null);
    }
    if (req.body.customerId !== undefined) {
      fields.push(`customer_id = $${idx++}`);
      params.push(normalizeOptionalText(req.body.customerId) || null);
    }
    if (topUp > 0) {
      fields.push(`balance = balance + $${idx++}`);
      params.push(topUp);
      fields.push(`initial_balance = initial_balance + $${idx++}`);
      params.push(topUp);
    } else if (topUp < 0) {
      throw createHttpError(400, 'Top-up amount must be positive.');
    }
    if (fields.isEmpty) {
      return res.json({ ok: true, giftCard: current });
    }
    fields.push(`updated_at = $${idx++}`);
    params.push(new Date().toISOString());
    params.push(id);
    await query(
      `UPDATE gift_cards SET ${fields.join(', ')} WHERE id = $${idx}`,
      params,
    );
    const updated = await query('SELECT * FROM gift_cards WHERE id = $1', [id]);
    res.json({ ok: true, giftCard: updated.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.post('/api/gift-cards/:id/redeem', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.giftCards);
    const id = req.params.id;
    const amount = Number(req.body.amount || 0);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw createHttpError(400, 'Redemption amount must be greater than zero.');
    }
    const row = await query(
      'SELECT * FROM gift_cards WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL',
      [id, businessContext.businessId],
    );
    if (!row.rows.length) {
      throw createHttpError(404, 'Gift card not found.');
    }
    const card = row.rows[0];
    if (!card.is_active) {
      throw createHttpError(400, 'This gift card is not active.');
    }
    if (card.expires_at && new Date(card.expires_at).getTime() < Date.now()) {
      throw createHttpError(400, 'This gift card has expired.');
    }
    const balance = Number(card.balance || 0);
    if (amount > balance) {
      throw createHttpError(400, 'The gift card balance is insufficient.');
    }
    const now = new Date().toISOString();
    await query(
      'UPDATE gift_cards SET balance = balance - $1, updated_at = $2 WHERE id = $3',
      [amount, now, id],
    );
    const updated = await query('SELECT * FROM gift_cards WHERE id = $1', [id]);
    res.json({ ok: true, giftCard: updated.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.delete('/api/gift-cards/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.giftCards);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const id = req.params.id;
    const now = new Date().toISOString();
    const result = await query(
      `UPDATE gift_cards SET deleted_at = $1, updated_at = $1
       WHERE id = $2 AND business_id = $3 AND deleted_at IS NULL`,
      [now, id, businessContext.businessId],
    );
    if (result.rowCount === 0) {
      throw createHttpError(404, 'Gift card not found.');
    }
    res.json({ ok: true, id });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Custom Roles / Granular Permissions
// ============================================================================

function normalizeCustomRoleBaseRole(value) {
  const role = normalizeBusinessRole(value);
  return role === 'ADMIN' ? 'MANAGER' : role;
}

function normalizeCustomRolePosMode(value) {
  const clean = normalizeOptionalText(value)?.toLowerCase();
  if (clean === 'products' || clean === 'services' || clean === 'both') {
    return clean;
  }
  return 'both';
}

function normalizeCustomRoleServiceOrderScope(value) {
  const clean = normalizeOptionalText(value)?.toLowerCase();
  if (clean === 'assigned_only') {
    return 'assigned_only';
  }
  return 'all_visible_services';
}

function normalizeJsonStringList(value) {
  const values = Array.isArray(value) ? value : parseJsonStringList(value);
  return JSON.stringify([...new Set(values.map(normalizeOptionalText).filter(Boolean))]);
}

function normalizeCustomRolePayload(body, existing = {}) {
  const has = (key) => Object.prototype.hasOwnProperty.call(body || {}, key);
  const read = (camel, snake) =>
    has(camel) ? body[camel] : has(snake) ? body[snake] : existing[snake];
  const name = has('name')
    ? normalizeText(body.name)
    : normalizeText(existing.name || '');
  const featureSource = read('featureAccess', 'feature_access_json');
  const allowedServicesSource = read(
    'allowedServiceIds',
    'allowed_service_ids_json',
  );
  const allowedBranchesSource = read(
    'allowedBranchIds',
    'allowed_branch_ids_json',
  );
  return {
    name,
    description:
      has('description') || existing.description !== undefined
        ? normalizeOptionalText(
            has('description') ? body.description : existing.description,
          ) || null
        : null,
    baseRole: normalizeCustomRoleBaseRole(read('baseRole', 'base_role')),
    featureAccessJson: normalizeJsonStringList(featureSource),
    allowedServiceIdsJson: normalizeJsonStringList(allowedServicesSource),
    allowedBranchIdsJson: normalizeJsonStringList(allowedBranchesSource),
    posMode: normalizeCustomRolePosMode(read('posMode', 'pos_mode')),
    serviceOrderScope: normalizeCustomRoleServiceOrderScope(
      read('serviceOrderScope', 'service_order_scope'),
    ),
    isActive: has('isActive')
      ? body.isActive !== false
      : has('is_active')
        ? body.is_active !== false
        : Number(existing.is_active ?? 1) !== 0,
  };
}

async function propagateCustomRoleToUsers(client, role, businessId, now) {
  await client.query(
    `UPDATE users
     SET role = $3,
         feature_access_json = $4,
         allowed_service_ids_json = NULLIF($5, '[]'),
         allowed_branch_ids_json = NULLIF($6, '[]'),
         pos_mode = $7,
         service_order_scope = $8,
         updated_at = $9,
         sync_status = 'synced',
         server_revision = nextval('sync_revision_seq')
     WHERE business_id = $1
       AND custom_role_id = $2
       AND deleted_at IS NULL`,
    [
      businessId,
      role.id,
      role.base_role,
      role.feature_access_json,
      role.allowed_service_ids_json || '[]',
      role.allowed_branch_ids_json || '[]',
      role.pos_mode,
      role.service_order_scope,
      now,
    ],
  );
}

app.get('/api/roles', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.customRoles);
    requireAdmin(businessContext);
    const activeOnly = req.query.activeOnly === 'true';
    const params = [businessContext.businessId];
    const where = ['cr.business_id = $1', 'cr.deleted_at IS NULL'];
    if (activeOnly) {
      where.push('COALESCE(cr.is_active, 1) <> 0');
    }
    const rows = await query(
      `SELECT cr.*,
              COUNT(u.id)::int AS assigned_count
       FROM custom_roles cr
       LEFT JOIN users u
         ON u.business_id = cr.business_id
        AND u.custom_role_id = cr.id
        AND u.deleted_at IS NULL
       WHERE ${where.join(' AND ')}
       GROUP BY cr.id
       ORDER BY COALESCE(cr.is_active, 1) DESC, cr.name ASC`,
      params,
    );
    res.json({ ok: true, roles: rows.rows });
  } catch (error) {
    next(error);
  }
});

app.post('/api/roles', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.customRoles);
    requireAdmin(businessContext);
    const role = normalizeCustomRolePayload(req.body || {});
    if (!role.name) {
      throw createHttpError(400, 'Role name is required.');
    }
    const now = new Date().toISOString();
    const id = crypto.randomUUID();
    const result = await query(
      `INSERT INTO custom_roles (
         id, business_id, branch_id, name, description, base_role,
         feature_access_json, allowed_service_ids_json, allowed_branch_ids_json,
         pos_mode, service_order_scope, is_active, created_at, updated_at,
         sync_status, server_revision
       ) VALUES (
         $1, $2, $3, $4, $5, $6, $7, NULLIF($8, '[]'), NULLIF($9, '[]'),
         $10, $11, $12, $13, $13, 'synced', nextval('sync_revision_seq')
       )
       RETURNING *`,
      [
        id,
        businessContext.businessId,
        normalizeOptionalText(req.body?.branchId || req.body?.branch_id) ||
          'main_branch',
        role.name,
        role.description,
        role.baseRole,
        role.featureAccessJson,
        role.allowedServiceIdsJson,
        role.allowedBranchIdsJson,
        role.posMode,
        role.serviceOrderScope,
        role.isActive ? 1 : 0,
        now,
      ],
    );
    res.json({ ok: true, role: result.rows[0] });
  } catch (error) {
    next(error);
  }
});

app.put('/api/roles/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.customRoles);
    requireAdmin(businessContext);
    const existing = await query(
      `SELECT *
       FROM custom_roles
       WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL
       LIMIT 1`,
      [businessContext.businessId, req.params.id],
    );
    if (!existing.rows.length) {
      throw createHttpError(404, 'Role was not found.');
    }
    const role = normalizeCustomRolePayload(req.body || {}, existing.rows[0]);
    if (!role.name) {
      throw createHttpError(400, 'Role name is required.');
    }
    const now = new Date().toISOString();
    const updated = await withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE custom_roles
         SET name = $3,
             description = $4,
             base_role = $5,
             feature_access_json = $6,
             allowed_service_ids_json = NULLIF($7, '[]'),
             allowed_branch_ids_json = NULLIF($8, '[]'),
             pos_mode = $9,
             service_order_scope = $10,
             is_active = $11,
             updated_at = $12,
             sync_status = 'synced',
             server_revision = nextval('sync_revision_seq')
         WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL
         RETURNING *`,
        [
          businessContext.businessId,
          req.params.id,
          role.name,
          role.description,
          role.baseRole,
          role.featureAccessJson,
          role.allowedServiceIdsJson,
          role.allowedBranchIdsJson,
          role.posMode,
          role.serviceOrderScope,
          role.isActive ? 1 : 0,
          now,
        ],
      );
      const row = result.rows[0];
      await propagateCustomRoleToUsers(client, row, businessContext.businessId, now);
      return row;
    });
    res.json({ ok: true, role: updated });
  } catch (error) {
    next(error);
  }
});

app.delete('/api/roles/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.customRoles);
    requireAdmin(businessContext);
    const now = new Date().toISOString();
    const deleted = await withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE custom_roles
         SET deleted_at = $3,
             updated_at = $3,
             is_active = 0,
             sync_status = 'synced',
             server_revision = nextval('sync_revision_seq')
         WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL
         RETURNING *`,
        [businessContext.businessId, req.params.id, now],
      );
      await client.query(
        `UPDATE users
         SET custom_role_id = NULL,
             updated_at = $3,
             sync_status = 'synced',
             server_revision = nextval('sync_revision_seq')
         WHERE business_id = $1
           AND custom_role_id = $2
           AND deleted_at IS NULL`,
        [businessContext.businessId, req.params.id, now],
      );
      return result.rows[0] || null;
    });
    if (!deleted) {
      throw createHttpError(404, 'Role was not found.');
    }
    res.json({ ok: true });
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// Promotions
// ============================================================================

function normalizePromotionRule(rule = {}) {
  return {
    id: normalizeOptionalText(rule.id) || crypto.randomUUID(),
    ruleType: normalizeOptionalText(rule.ruleType || rule.rule_type) || 'cart',
    productId: normalizeOptionalText(rule.productId || rule.product_id) || null,
    categoryId:
      normalizeOptionalText(rule.categoryId || rule.category_id) || null,
    minQuantity: Number(rule.minQuantity ?? rule.min_quantity ?? 0) || 0,
    freeQuantity: Number(rule.freeQuantity ?? rule.free_quantity ?? 0) || 0,
    bundleQuantity:
      Number(rule.bundleQuantity ?? rule.bundle_quantity ?? 0) || 0,
    minSubtotal: Number(rule.minSubtotal ?? rule.min_subtotal ?? 0) || 0,
    ruleJson:
      typeof rule.ruleJson === 'string'
        ? normalizeOptionalText(rule.ruleJson)
        : rule.ruleJson || rule.rule_json
          ? JSON.stringify(rule.ruleJson || rule.rule_json)
          : null,
  };
}

async function loadPromotionRules(businessId, promotionIds, target = query) {
  if (!promotionIds.length) return new Map();
  const rows = await target(
    `SELECT * FROM promotion_rules
     WHERE business_id = $1
       AND promotion_id = ANY($2::text[])
       AND deleted_at IS NULL
     ORDER BY created_at ASC`,
    [businessId, promotionIds],
  );
  const byPromotion = new Map();
  for (const rule of rows.rows) {
    const list = byPromotion.get(rule.promotion_id) || [];
    list.push(rule);
    byPromotion.set(rule.promotion_id, list);
  }
  return byPromotion;
}

app.get('/api/promotions', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.promotions);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId];
    const where = ['business_id = $1', 'deleted_at IS NULL'];
    if (req.query.activeOnly === 'true') {
      where.push('is_active = true');
    }
    let branchFilter = '';
    if (scope.branchIds != null) {
      branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`;
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT * FROM promotions
       WHERE ${where.join(' AND ')} ${branchFilter}
       ORDER BY priority DESC, updated_at DESC
       LIMIT 500`,
      params,
    );
    const rules = await loadPromotionRules(
      businessContext.businessId,
      rows.rows.map((row) => row.id),
    );
    res.json({
      ok: true,
      promotions: rows.rows.map((row) => ({
        ...row,
        rules: rules.get(row.id) || [],
      })),
    });
  } catch (error) {
    next(error);
  }
});

app.get('/api/promotions/active', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.promotions);
    const scope = resolveDataScope(businessContext, req.query.branchId);
    const params = [businessContext.businessId, new Date().toISOString()];
    let branchFilter = '';
    if (scope.branchIds != null) {
      branchFilter = `AND COALESCE(branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`;
      params.push(scope.branchIds);
    }
    const rows = await query(
      `SELECT * FROM promotions
       WHERE business_id = $1
         AND deleted_at IS NULL
         AND is_active = true
         AND (starts_at IS NULL OR starts_at <= $2)
         AND (ends_at IS NULL OR ends_at >= $2)
         ${branchFilter}
       ORDER BY priority DESC, updated_at DESC`,
      params,
    );
    const rules = await loadPromotionRules(
      businessContext.businessId,
      rows.rows.map((row) => row.id),
    );
    res.json({
      ok: true,
      promotions: rows.rows.map((row) => ({
        ...row,
        rules: rules.get(row.id) || [],
      })),
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/promotions', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.promotions);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const scope = resolveDataScope(businessContext, req.body.branchId);
    const branchId = scope.branchId || 'main_branch';
    const name = normalizeText(req.body.name);
    if (!name) {
      throw createHttpError(400, 'Promotion name is required.');
    }
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    const rules = Array.isArray(req.body.rules)
      ? req.body.rules.map(normalizePromotionRule)
      : [];
    const result = await withTransaction(async (client) => {
      await client.query(
        `INSERT INTO promotions (
          id, business_id, branch_id, name, description, promotion_type,
          discount_type, discount_value, priority, starts_at, ends_at,
          days_of_week, start_time, end_time, is_active, created_at, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $16
        )`,
        [
          id,
          businessContext.businessId,
          branchId,
          name,
          normalizeOptionalText(req.body.description) || null,
          normalizeOptionalText(
            req.body.promotionType || req.body.promotion_type,
          ) || 'amount_off',
          normalizeOptionalText(
            req.body.discountType || req.body.discount_type,
          ) || 'amount',
          Number(req.body.discountValue ?? req.body.discount_value ?? 0) || 0,
          Number(req.body.priority ?? 0) || 0,
          req.body.startsAt || req.body.starts_at
            ? toIsoString(req.body.startsAt || req.body.starts_at)
            : null,
          req.body.endsAt || req.body.ends_at
            ? toIsoString(req.body.endsAt || req.body.ends_at)
            : null,
          normalizeOptionalText(req.body.daysOfWeek || req.body.days_of_week) ||
            null,
          normalizeOptionalText(req.body.startTime || req.body.start_time) ||
            null,
          normalizeOptionalText(req.body.endTime || req.body.end_time) || null,
          req.body.isActive === undefined ? true : req.body.isActive !== false,
          now,
        ],
      );
      for (const rule of rules) {
        await client.query(
          `INSERT INTO promotion_rules (
            id, business_id, branch_id, promotion_id, rule_type, product_id,
            category_id, min_quantity, free_quantity, bundle_quantity,
            min_subtotal, rule_json, created_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $13)`,
          [
            rule.id,
            businessContext.businessId,
            branchId,
            id,
            rule.ruleType,
            rule.productId,
            rule.categoryId,
            rule.minQuantity,
            rule.freeQuantity,
            rule.bundleQuantity,
            rule.minSubtotal,
            rule.ruleJson,
            now,
          ],
        );
      }
      const promotion = await client.query(
        'SELECT * FROM promotions WHERE id = $1',
        [id],
      );
      return promotion.rows[0];
    });
    res.json({ ok: true, promotion: result });
  } catch (error) {
    next(error);
  }
});

app.put('/api/promotions/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.promotions);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const id = req.params.id;
    const existing = await query(
      'SELECT * FROM promotions WHERE id = $1 AND business_id = $2 AND deleted_at IS NULL',
      [id, businessContext.businessId],
    );
    if (!existing.rows.length) {
      throw createHttpError(404, 'Promotion not found.');
    }
    const now = new Date().toISOString();
    const rules = Array.isArray(req.body.rules)
      ? req.body.rules.map(normalizePromotionRule)
      : null;
    const updated = await withTransaction(async (client) => {
      const fields = [];
      const params = [];
      let idx = 1;
      const addField = (column, value) => {
        fields.push(`${column} = $${idx++}`);
        params.push(value);
      };
      if (req.body.name !== undefined) {
        addField('name', normalizeText(req.body.name));
      }
      if (req.body.description !== undefined) {
        addField('description', normalizeOptionalText(req.body.description) || null);
      }
      if (
        req.body.promotionType !== undefined ||
        req.body.promotion_type !== undefined
      ) {
        addField(
          'promotion_type',
          normalizeOptionalText(req.body.promotionType || req.body.promotion_type) ||
            'amount_off',
        );
      }
      if (
        req.body.discountType !== undefined ||
        req.body.discount_type !== undefined
      ) {
        addField(
          'discount_type',
          normalizeOptionalText(req.body.discountType || req.body.discount_type) ||
            'amount',
        );
      }
      if (
        req.body.discountValue !== undefined ||
        req.body.discount_value !== undefined
      ) {
        addField(
          'discount_value',
          Number(req.body.discountValue ?? req.body.discount_value ?? 0) || 0,
        );
      }
      if (req.body.priority !== undefined) {
        addField('priority', Number(req.body.priority ?? 0) || 0);
      }
      if (req.body.startsAt !== undefined || req.body.starts_at !== undefined) {
        const value = req.body.startsAt ?? req.body.starts_at;
        addField('starts_at', value ? toIsoString(value) : null);
      }
      if (req.body.endsAt !== undefined || req.body.ends_at !== undefined) {
        const value = req.body.endsAt ?? req.body.ends_at;
        addField('ends_at', value ? toIsoString(value) : null);
      }
      if (
        req.body.daysOfWeek !== undefined ||
        req.body.days_of_week !== undefined
      ) {
        addField(
          'days_of_week',
          normalizeOptionalText(req.body.daysOfWeek || req.body.days_of_week) ||
            null,
        );
      }
      if (req.body.startTime !== undefined || req.body.start_time !== undefined) {
        addField(
          'start_time',
          normalizeOptionalText(req.body.startTime || req.body.start_time) ||
            null,
        );
      }
      if (req.body.endTime !== undefined || req.body.end_time !== undefined) {
        addField(
          'end_time',
          normalizeOptionalText(req.body.endTime || req.body.end_time) || null,
        );
      }
      if (req.body.isActive !== undefined || req.body.is_active !== undefined) {
        addField('is_active', (req.body.isActive ?? req.body.is_active) !== false);
      }
      if (fields.length) {
        addField('updated_at', now);
        params.push(id);
        await client.query(
          `UPDATE promotions SET ${fields.join(', ')} WHERE id = $${idx}`,
          params,
        );
      }
      if (rules != null) {
        await client.query(
          `UPDATE promotion_rules
           SET deleted_at = $1, updated_at = $1
           WHERE promotion_id = $2 AND business_id = $3 AND deleted_at IS NULL`,
          [now, id, businessContext.businessId],
        );
        for (const rule of rules) {
          await client.query(
            `INSERT INTO promotion_rules (
              id, business_id, branch_id, promotion_id, rule_type, product_id,
              category_id, min_quantity, free_quantity, bundle_quantity,
              min_subtotal, rule_json, created_at, updated_at
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $13)`,
            [
              rule.id,
              businessContext.businessId,
              existing.rows[0].branch_id || 'main_branch',
              id,
              rule.ruleType,
              rule.productId,
              rule.categoryId,
              rule.minQuantity,
              rule.freeQuantity,
              rule.bundleQuantity,
              rule.minSubtotal,
              rule.ruleJson,
              now,
            ],
          );
        }
      }
      const promotion = await client.query(
        'SELECT * FROM promotions WHERE id = $1',
        [id],
      );
      return promotion.rows[0];
    });
    res.json({ ok: true, promotion: updated });
  } catch (error) {
    next(error);
  }
});

app.delete('/api/promotions/:id', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      requireWrite: true,
    });
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.promotions);
    ensureRoleAtLeast(businessContext, 'MANAGER');
    const now = new Date().toISOString();
    const id = req.params.id;
    const result = await withTransaction(async (client) => {
      const deleted = await client.query(
        `UPDATE promotions SET deleted_at = $1, updated_at = $1
         WHERE id = $2 AND business_id = $3 AND deleted_at IS NULL`,
        [now, id, businessContext.businessId],
      );
      if (deleted.rowCount > 0) {
        await client.query(
          `UPDATE promotion_rules SET deleted_at = $1, updated_at = $1
           WHERE promotion_id = $2 AND business_id = $3 AND deleted_at IS NULL`,
          [now, id, businessContext.businessId],
        );
      }
      return deleted.rowCount;
    });
    if (result === 0) {
      throw createHttpError(404, 'Promotion not found.');
    }
    res.json({ ok: true, id });
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
      const deviceRes = await client.query('SELECT COUNT(*) FROM devices');
      const trialRes = await client.query(`
        SELECT COUNT(*) FROM subscriptions
        WHERE plan = 'trial' AND status IN ('active', 'grace')
      `);
      const expiringRes = await client.query(`
        SELECT COUNT(*) FROM subscriptions
        WHERE status IN ('active', 'grace')
          AND expires_at BETWEEN NOW() AND NOW() + INTERVAL '7 days'
      `);
      return {
        totalBusinesses: parseInt(bizRes.rows[0].count, 10),
        activeSubscriptions: parseInt(subRes.rows[0].count, 10),
        totalUsers: parseInt(usrRes.rows[0].count, 10),
        totalDevices: parseInt(deviceRes.rows[0].count, 10),
        trialSubscriptions: parseInt(trialRes.rows[0].count, 10),
        expiringSubscriptions: parseInt(expiringRes.rows[0].count, 10),
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
             owner.phone AS owner_phone,
             (SELECT COUNT(*)::int FROM branches br
              WHERE br.business_id = b.id AND br.deleted_at IS NULL) AS branch_count,
             (SELECT COUNT(*)::int FROM devices d WHERE d.business_id = b.id) AS device_count,
             (SELECT MAX(d.last_seen_at) FROM devices d WHERE d.business_id = b.id) AS last_seen_at,
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
      LEFT JOIN LATERAL (
        SELECT u.phone
        FROM users u
        WHERE u.business_id = b.id
          AND u.deleted_at IS NULL
          AND UPPER(u.role) = 'ADMIN'
        ORDER BY u.created_at ASC
        LIMIT 1
      ) owner ON true
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
      SELECT u.id, u.business_id, u.name, u.email, u.phone, u.role,
             u.created_at, u.last_seen_at, b.name as business_name
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

// ── Platform Admin: Delete All Businesses, Users & Data ─────────────────────

app.delete('/api/platform/all-data', requirePlatformAdmin, async (req, res, next) => {
  try {
    const confirm = normalizeOptionalText(req.body?.confirm);
    if (confirm !== 'DELETE EVERYTHING') {
      throw createHttpError(400, 'Confirmation required. Send { "confirm": "DELETE EVERYTHING" } in the request body.');
    }

    const businessCountResult = await query('SELECT COUNT(*)::int AS count FROM businesses WHERE deleted_at IS NULL');
    const userCountResult = await query('SELECT COUNT(*)::int AS count FROM users WHERE deleted_at IS NULL');
    const businessCount = businessCountResult.rows[0]?.count || 0;
    const userCount = userCountResult.rows[0]?.count || 0;

    if (businessCount === 0 && userCount === 0) {
      res.json({ ok: true, data: { businesses: 0, users: 0, message: 'Nothing to delete.' } });
      return;
    }

    const businessDataTables = [
      'customer_invoice_items',
      'customer_invoices',
      'stock_transfers',
      'audit_logs',
      'branches',
      'payment_methods',
      'product_variant_colors',
      'product_variants',
      'service_sale_items',
      'service_field_values',
      'service_orders',
      'service_fields',
      'services',
      'expenses',
      'credit_payments',
      'cash_movements',
      'sale_items',
      'sales',
      'shifts',
      'stock_batches',
      'purchase_order_items',
      'purchase_orders',
      'supplier_payments',
      'purchase_invoices',
      'products',
      'suppliers',
      'customers',
      'expense_categories',
      'categories',
    ];

    for (const table of businessDataTables) {
      try {
        await query(`DELETE FROM ${table}`);
      } catch (_) {
        // table may not exist yet on some deployments
      }
    }

    try { await query('DELETE FROM users'); } catch (_) {}
    try { await query('DELETE FROM email_otps'); } catch (_) {}

    try { await query('DELETE FROM businesses'); } catch (_) {}

    try { await query('DELETE FROM platform_app_version WHERE id != 1'); } catch (_) {}

    res.json({
      ok: true,
      data: {
        businesses: businessCount,
        users: userCount,
        message: `Deleted ${businessCount} business(es) and ${userCount} user(s). All associated data has been removed.`,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
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

app.get('/api/app/releases/status', async (req, res, next) => {
  try {
    const releasesDir = config.appReleaseDir;
    const platforms = ['android', 'windows'];
    const result = {};
    for (const platform of platforms) {
      const platformDir = path.join(releasesDir, platform);
      let files = [];
      try {
        const entries = await fsp.readdir(platformDir);
        files = await Promise.all(
          entries
            .filter((name) => !name.startsWith('.'))
            .map(async (name) => {
              const filePath = path.join(platformDir, name);
              const stat = await fsp.stat(filePath);
              return {
                name,
                size: stat.size,
                url: `${appReleaseUrlPrefix}/${platform}/${name}`,
                modified: stat.mtime.toISOString(),
              };
            }),
        );
      } catch (_) {
        // directory doesn't exist yet
      }
      result[platform] = {
        dir: platformDir,
        count: files.length,
        files: files.sort((a, b) => b.modified.localeCompare(a.modified)),
      };
    }
    res.json({ ok: true, data: result });
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
      throw createHttpError(400, 'Choose products, services, restaurant, or combo for the business type.');
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
        await applyCustomerPortalMpesaPayment(paymentResult);
        await applyPublicCatalogMpesaPayment(paymentResult);
        notifyBusinessRealtimeChange({
          businessId: paymentResult.businessId,
          reason: 'payment',
          tables: paymentResult.saleId ? ['sales'] : ['sales', 'customers', 'credit_payments'],
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
    const previewOnly = req.body?.previewOnly === true;
    const payment = await matchManualPayment({
      businessId: businessContext.businessId,
      referenceCode: req.body?.referenceCode,
      phoneNumber: req.body?.phoneNumber,
      amount,
      checkoutCode: req.body?.checkoutCode,
      saleId: req.body?.saleId,
      previewOnly,
    });
    if (!previewOnly && payment) {
      notifyBusinessRealtimeChange({
        businessId: businessContext.businessId,
        sourceDeviceId: businessContext.deviceId,
        reason: 'payment',
        tables: ['sales'],
      });
    }
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
        platform.setupBlockedReason ||
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

const PRODUCT_IMPORT_FILE_MAX_BYTES = 7 * 1024 * 1024;
const PRODUCT_IMPORT_TEXT_LIMIT = 42000;
const PRODUCT_IMPORT_MAX_ROWS = 150;
const PRODUCT_IMPORT_MAX_EMBEDDED_IMAGES = 40;
const PRODUCT_IMPORT_FIELDS = [
  'product_id',
  'variant_id',
  'parent_product_id',
  'parent_product_name',
  'variant_name',
  'name',
  'price',
  'cost',
  'sku',
  'barcode',
  'category',
  'stock',
  'stock_received',
  'low_stock',
  'unit',
  'stock_unit',
  'sale_unit',
  'purchase_unit',
  'sale_to_stock_factor',
  'purchase_to_stock_factor',
  'track_stock',
  'brand',
  'description',
  'image_url',
  'image_urls_json',
  'show_online',
  'is_featured',
  'expiry_date',
  'batch_number',
];
const PRODUCT_IMPORT_FIELD_SET = new Set(PRODUCT_IMPORT_FIELDS);
const SALES_IMPORT_MAX_ROWS = 250;
const SALES_IMPORT_FIELDS = [
  'date',
  'total',
  'payment_type',
  'tax',
  'discount',
  'customer_name',
  'phone',
  'due_date',
  'reference',
  'note',
  'line_type',
  'product_id',
  'variant_id',
  'sku',
  'barcode',
  'product',
  'service_id',
  'service',
  'quantity',
  'unit_price',
  'unit_cost',
  'unit',
];
const SALES_IMPORT_FIELD_SET = new Set(SALES_IMPORT_FIELDS);
const CUSTOMER_IMPORT_MAX_ROWS = 300;
const CUSTOMER_IMPORT_FIELDS = [
  'customer_id',
  'name',
  'phone',
  'email',
];
const CUSTOMER_IMPORT_FIELD_SET = new Set(CUSTOMER_IMPORT_FIELDS);
const EXPENSE_IMPORT_MAX_ROWS = 300;
const EXPENSE_IMPORT_FIELDS = [
  'title',
  'amount',
  'date',
  'category',
  'note',
];
const EXPENSE_IMPORT_FIELD_SET = new Set(EXPENSE_IMPORT_FIELDS);
const SMART_IMPORT_TARGETS = {
  products: {
    label: 'products',
    fields: PRODUCT_IMPORT_FIELDS,
    fieldSet: PRODUCT_IMPORT_FIELD_SET,
    maxRows: PRODUCT_IMPORT_MAX_ROWS,
  },
  sales: {
    label: 'sales',
    fields: SALES_IMPORT_FIELDS,
    fieldSet: SALES_IMPORT_FIELD_SET,
    maxRows: SALES_IMPORT_MAX_ROWS,
  },
  customers: {
    label: 'customers',
    fields: CUSTOMER_IMPORT_FIELDS,
    fieldSet: CUSTOMER_IMPORT_FIELD_SET,
    maxRows: CUSTOMER_IMPORT_MAX_ROWS,
  },
  expenses: {
    label: 'expenses',
    fields: EXPENSE_IMPORT_FIELDS,
    fieldSet: EXPENSE_IMPORT_FIELD_SET,
    maxRows: EXPENSE_IMPORT_MAX_ROWS,
  },
};

function normalizeProductFileExtension(input, fileName) {
  const clean = normalizeOptionalText(input)
    ?.toLowerCase()
    .replace(/^\./, '');
  if (clean) return clean;
  const name = normalizeOptionalText(fileName) || '';
  const match = name.toLowerCase().match(/\.([a-z0-9]+)$/);
  return match ? match[1] : '';
}

function decodeProductImportFile(body = {}) {
  const fileBase64 = normalizeOptionalText(body.fileBase64 || body.file_base64);
  if (!fileBase64) {
    throw createHttpError(400, 'fileBase64 is required');
  }
  const normalizedBase64 = fileBase64.replace(/^data:[^,]+,/, '').replace(/\s/g, '');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(normalizedBase64)) {
    throw createHttpError(400, 'The product file is not valid base64');
  }
  const bytes = Buffer.from(normalizedBase64, 'base64');
  if (bytes.length === 0) {
    throw createHttpError(400, 'The product file is empty');
  }
  if (bytes.length > PRODUCT_IMPORT_FILE_MAX_BYTES) {
    throw createHttpError(413, 'Choose a product file below 7 MB.');
  }
  const fileName = limitText(body.fileName || body.file_name || 'product-file', 180);
  return {
    bytes,
    fileName,
    extension: normalizeProductFileExtension(body.extension, fileName),
    mimeType: normalizeOptionalText(body.mimeType || body.mime_type),
  };
}

function importSourceTextFromBody(body = {}) {
  return normalizeOptionalText(body.sourceText || body.source_text);
}

async function extractTextFromProductImportFile(file) {
  switch (file.extension) {
    case 'pdf':
      return extractPdfText(file.bytes);
    case 'docx':
      return extractDocxText(file.bytes);
    case 'txt':
    case 'csv':
    case 'tsv':
    case 'json':
      return file.bytes.toString('utf8');
    case 'xlsx': {
      const workbook = await extractXlsxProductImport(file.bytes);
      return workbook.text;
    }
    case 'xls':
      throw createHttpError(400, 'Legacy .xls files are not supported yet. Save the workbook as .xlsx, CSV, or PDF and upload again.');
    default:
      throw createHttpError(
        400,
        'Unsupported product file type. Use Excel, CSV, PDF, DOCX, TXT, or JSON.',
      );
  }
}

function isProductImportImageFile(file) {
  const extension = String(file?.extension || '').toLowerCase();
  const mimeType = String(file?.mimeType || '').toLowerCase();
  return (
    mimeType.startsWith('image/') ||
    ['png', 'jpg', 'jpeg', 'webp'].includes(extension)
  );
}

function productImportImageMimeType(file) {
  const mimeType = normalizeOptionalText(file?.mimeType);
  if (mimeType && mimeType.toLowerCase().startsWith('image/')) {
    return mimeType;
  }
  switch (String(file?.extension || '').toLowerCase()) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}

function productImportImageDataUrl(file) {
  return `data:${productImportImageMimeType(file)};base64,${file.bytes.toString('base64')}`;
}

async function extractPdfText(bytes) {
  const parser = new PDFParse({ data: bytes });
  try {
    const result = await parser.getText();
    return result?.text || '';
  } finally {
    await parser.destroy();
  }
}

async function extractDocxText(bytes) {
  const result = await mammoth.extractRawText({ buffer: bytes });
  return result?.value || '';
}

async function extractXlsxProductImport(bytes) {
  let zip;
  try {
    zip = await JSZip.loadAsync(bytes);
  } catch (_) {
    throw createHttpError(400, 'Piki could not read this Excel workbook. Save it as .xlsx and try again.');
  }

  const sharedStrings = await readXlsxSharedStrings(zip);
  const sheetEntries = await readXlsxSheetEntries(zip);
  const sheets = [];
  const images = [];

  for (const entry of sheetEntries) {
    const sheetXml = await xlsxZipText(zip, entry.path);
    if (!sheetXml) continue;
    const rows = readXlsxSheetRows(sheetXml, sharedStrings);
    sheets.push({ name: entry.name, path: entry.path, rows });
    const sheetImages = await readXlsxSheetImages({
      zip,
      sheetXml,
      sheetPath: entry.path,
      sheetName: entry.name,
      rows,
    });
    images.push(...sheetImages);
  }

  if (sheets.length === 0) {
    throw createHttpError(400, 'Piki could not find readable sheets in this Excel workbook.');
  }

  return {
    text: xlsxWorkbookPreviewText(sheets, images),
    sheets,
    images: images.slice(0, PRODUCT_IMPORT_MAX_EMBEDDED_IMAGES),
  };
}

async function xlsxZipText(zip, filePath) {
  const file = zip.file(filePath);
  if (!file) return null;
  return file.async('string');
}

async function xlsxZipBuffer(zip, filePath) {
  const file = zip.file(filePath);
  if (!file) return null;
  return file.async('nodebuffer');
}

async function readXlsxSharedStrings(zip) {
  const content = await xlsxZipText(zip, 'xl/sharedStrings.xml');
  if (!content) return [];
  const strings = [];
  for (const match of content.matchAll(/<si\b[\s\S]*?<\/si>/g)) {
    const textParts = [...match[0].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((part) => decodeXmlText(part[1]));
    strings.push(textParts.join(''));
  }
  return strings;
}

async function readXlsxSheetEntries(zip) {
  const workbook = await xlsxZipText(zip, 'xl/workbook.xml');
  const relationships = await xlsxZipText(zip, 'xl/_rels/workbook.xml.rels');
  if (!workbook || !relationships) {
    return zip
      .file(/xl\/worksheets\/sheet\d+\.xml$/)
      .map((file, index) => ({ name: `Sheet ${index + 1}`, path: file.name }));
  }

  const rels = parseXlsxRelationships(relationships, 'xl/workbook.xml');
  const entries = [];
  for (const match of workbook.matchAll(/<sheet\b([^>]*)\/?>(?:<\/sheet>)?/g)) {
    const attrs = parseXmlAttributes(match[1]);
    const relationshipId = attrs.id || attrs['r:id'];
    const target = rels.get(relationshipId)?.target;
    if (!target) continue;
    entries.push({
      name: normalizeOptionalText(attrs.name) || `Sheet ${entries.length + 1}`,
      path: target,
    });
  }
  return entries;
}

function readXlsxSheetRows(sheetXml, sharedStrings) {
  const rows = [];
  let fallbackRow = 0;
  for (const rowMatch of sheetXml.matchAll(/<row\b([^>]*)>([\s\S]*?)<\/row>/g)) {
    const rowAttrs = parseXmlAttributes(rowMatch[1]);
    const declaredRow = Number(rowAttrs.r);
    const rowIndex = Number.isFinite(declaredRow) && declaredRow > 0 ? declaredRow - 1 : fallbackRow;
    const row = [];
    let fallbackColumn = 0;
    for (const cellMatch of rowMatch[2].matchAll(/<c\b([^>]*)>([\s\S]*?)<\/c>/g)) {
      const attrs = parseXmlAttributes(cellMatch[1]);
      const columnIndex = xlsxColumnIndex(attrs.r, fallbackColumn);
      while (row.length < columnIndex) row.push('');
      row[columnIndex] = xlsxCellValue(attrs, cellMatch[2], sharedStrings);
      fallbackColumn = columnIndex + 1;
    }
    while (rows.length <= rowIndex) rows.push([]);
    rows[rowIndex] = row.map((cell) => normalizeOptionalText(cell) || '');
    fallbackRow = rowIndex + 1;
  }
  return rows;
}

function xlsxCellValue(attrs, cellXml, sharedStrings) {
  const inlineText = [...cellXml.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)]
    .map((part) => decodeXmlText(part[1]))
    .join('');
  if (attrs.t === 'inlineStr' || inlineText) {
    return inlineText.trim();
  }
  const value = (cellXml.match(/<v\b[^>]*>([\s\S]*?)<\/v>/) || [])[1];
  const clean = decodeXmlText(value || '').trim();
  if (!clean) return '';
  if (attrs.t === 's') {
    const index = Number(clean);
    return Number.isInteger(index) && index >= 0 && index < sharedStrings.length
      ? String(sharedStrings[index] || '').trim()
      : '';
  }
  if (attrs.t === 'b') return clean === '1' ? 'true' : 'false';
  return clean;
}

async function readXlsxSheetImages({ zip, sheetXml, sheetPath, sheetName, rows }) {
  const sheetRelsXml = await xlsxZipText(zip, xlsxRelsPath(sheetPath));
  if (!sheetRelsXml) return [];
  const sheetRels = parseXlsxRelationships(sheetRelsXml, sheetPath);
  const images = [];
  for (const drawingMatch of sheetXml.matchAll(/<drawing\b([^>]*)\/?>(?:<\/drawing>)?/g)) {
    const attrs = parseXmlAttributes(drawingMatch[1]);
    const relationshipId = attrs.id || attrs['r:id'];
    const drawingPath = sheetRels.get(relationshipId)?.target;
    if (!drawingPath) continue;
    const drawingXml = await xlsxZipText(zip, drawingPath);
    const drawingRelsXml = await xlsxZipText(zip, xlsxRelsPath(drawingPath));
    if (!drawingXml || !drawingRelsXml) continue;
    const drawingRels = parseXlsxRelationships(drawingRelsXml, drawingPath);
    for (const anchorMatch of drawingXml.matchAll(/<(?:xdr:)?(?:twoCellAnchor|oneCellAnchor)\b[\s\S]*?<\/(?:xdr:)?(?:twoCellAnchor|oneCellAnchor)>/g)) {
      const anchor = anchorMatch[0];
      const embedId = (anchor.match(/<(?:a:)?blip\b[^>]*(?:r:embed|embed)="([^"]+)"/) || [])[1];
      const media = drawingRels.get(embedId);
      if (!media?.target || !isXlsxImagePath(media.target)) continue;
      const bytes = await xlsxZipBuffer(zip, media.target);
      if (!bytes || bytes.length === 0) continue;
      const rowIndex = xlsxAnchorNumber(anchor, 'row');
      const columnIndex = xlsxAnchorNumber(anchor, 'col');
      const rowInfo = closestXlsxRowText(rows, rowIndex);
      images.push({
        id: `xlsx-image-${images.length + 1}`,
        sheetName,
        path: media.target,
        rowIndex: rowInfo.rowIndex,
        originalRowIndex: rowIndex,
        columnIndex,
        rowText: rowInfo.text,
        uncertain: rowInfo.uncertain,
        bytes,
        mimeType: xlsxImageMimeType(media.target),
        extension: xlsxImageExtension(media.target),
      });
    }
  }
  return images;
}

function xlsxWorkbookPreviewText(sheets, images) {
  const imagesBySheetRow = new Map();
  for (const image of images) {
    const key = `${image.sheetName}:${image.rowIndex}`;
    const list = imagesBySheetRow.get(key) || [];
    list.push(image.id);
    imagesBySheetRow.set(key, list);
  }

  const buffer = [];
  for (const sheet of sheets) {
    const rows = sheet.rows
      .map((row, index) => ({ row, index }))
      .filter((entry) => entry.row.some((cell) => normalizeOptionalText(cell)));
    if (rows.length === 0) continue;
    if (buffer.length > 0) buffer.push('');
    buffer.push(`Sheet: ${sheet.name}`);
    const rowLimit = Math.min(rows.length, 160);
    for (let index = 0; index < rowLimit; index += 1) {
      const entry = rows[index];
      const cells = entry.row.slice(0, 24).map((cell) => limitText(String(cell || '').trim(), 120));
      const markers = imagesBySheetRow.get(`${sheet.name}:${entry.index}`) || [];
      if (markers.length > 0) {
        cells.push(`embedded_image=${markers.join(',')}`);
      }
      buffer.push(`Row ${entry.index + 1}: ${cells.join(' | ')}`);
    }
    if (rows.length > rowLimit) buffer.push(`... ${rows.length - rowLimit} more row(s)`);
  }
  if (images.length > 0) {
    buffer.push('', `Embedded images found: ${images.length}. Piki will attach images when it can confidently match them to product rows.`);
  }
  return buffer.join('\n').trim();
}

function parseXlsxRelationships(xmlText, basePath) {
  const rels = new Map();
  if (!xmlText) return rels;
  for (const match of xmlText.matchAll(/<Relationship\b([^>]*)\/?>(?:<\/Relationship>)?/g)) {
    const attrs = parseXmlAttributes(match[1]);
    if (!attrs.id || !attrs.target || String(attrs.targetMode || '').toLowerCase() === 'external') continue;
    rels.set(attrs.id, {
      type: attrs.type || '',
      target: normalizeXlsxRelationshipPath(basePath, attrs.target),
    });
  }
  return rels;
}

function parseXmlAttributes(input) {
  const attrs = {};
  for (const match of String(input || '').matchAll(/([A-Za-z_][A-Za-z0-9_:.-]*)\s*=\s*"([^"]*)"/g)) {
    const full = match[1];
    const value = decodeXmlText(match[2]);
    attrs[full] = value;
    const local = full.includes(':') ? full.split(':').pop() : full;
    attrs[local] = value;
  }
  return attrs;
}

function decodeXmlText(value) {
  return String(value || '')
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&');
}

function normalizeXlsxRelationshipPath(basePath, target) {
  const cleanTarget = String(target || '').replace(/\\/g, '/');
  const source = cleanTarget.startsWith('/')
    ? cleanTarget.slice(1)
    : `${String(basePath || '').split('/').slice(0, -1).join('/')}/${cleanTarget}`;
  const parts = [];
  for (const part of source.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') parts.pop();
    else parts.push(part);
  }
  return parts.join('/');
}

function xlsxRelsPath(partPath) {
  const clean = String(partPath || '').replace(/\\/g, '/');
  const segments = clean.split('/');
  const fileName = segments.pop();
  return [...segments, '_rels', `${fileName}.rels`].join('/');
}

function xlsxColumnIndex(cellReference, fallback = 0) {
  const ref = normalizeOptionalText(cellReference);
  if (!ref) return fallback;
  let column = 0;
  let sawLetter = false;
  for (const char of ref) {
    const code = char.toUpperCase().charCodeAt(0);
    if (code < 65 || code > 90) break;
    sawLetter = true;
    column = column * 26 + (code - 64);
  }
  return sawLetter ? column - 1 : fallback;
}

function xlsxAnchorNumber(anchor, tagName) {
  const from = anchor.match(/<(?:xdr:)?from>[\s\S]*?<\/(?:xdr:)?from>/);
  const source = from ? from[0] : anchor;
  const match = source.match(new RegExp(`<(?:xdr:)?${tagName}>(\\d+)<\\/(?:xdr:)?${tagName}>`));
  return match ? Number(match[1]) : null;
}

function closestXlsxRowText(rows, rowIndex) {
  const offsets = [0, 1, -1, 2, -2];
  for (const offset of offsets) {
    const index = Number.isInteger(rowIndex) ? rowIndex + offset : null;
    if (index == null || index < 0 || index >= rows.length) continue;
    const text = (rows[index] || [])
      .map((cell) => normalizeOptionalText(cell))
      .filter(Boolean)
      .join(' | ');
    if (text) return { rowIndex: index, text, uncertain: offset !== 0 };
  }
  return { rowIndex: Number.isInteger(rowIndex) ? rowIndex : -1, text: '', uncertain: true };
}

function isXlsxImagePath(filePath) {
  return /\.(png|jpe?g|webp|gif)$/i.test(String(filePath || ''));
}

function xlsxImageExtension(filePath) {
  const match = String(filePath || '').toLowerCase().match(/\.([a-z0-9]+)$/);
  const extension = match ? match[1] : 'jpg';
  return extension === 'jpeg' ? 'jpg' : extension;
}

function xlsxImageMimeType(filePath) {
  switch (xlsxImageExtension(filePath)) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    default:
      return 'image/jpeg';
  }
}
async function uploadEmbeddedXlsxProductImages({ fetchImpl, job, images }) {
  if (!Array.isArray(images) || images.length === 0) return [];
  const uploaded = [];
  for (const image of images.slice(0, PRODUCT_IMPORT_MAX_EMBEDDED_IMAGES)) {
    try {
      const upload = await uploadProductImageToBunny({
        fetchImpl,
        businessContext: { businessId: job.business_id },
        branchId: job.branch_id,
        productId: image.id,
        productName: image.rowText || image.id,
        image: {
          bytes: image.bytes,
          mimeType: image.mimeType,
          extension: image.extension,
        },
      });
      uploaded.push({
        ...image,
        imageUrl: upload.imageUrl,
        imageMatchStatus: image.uncertain ? 'uncertain_anchor' : 'uploaded',
      });
    } catch (error) {
      console.warn('Embedded Excel product image upload failed', {
        jobId: job.id,
        imageId: image.id,
        message: error?.message || error,
      });
      uploaded.push({
        ...image,
        uploadError: error?.message || 'Image upload failed',
      });
    }
  }
  return uploaded;
}

function attachUploadedProductImagesToImportResult(result, uploadedImages) {
  const imageCandidates = (Array.isArray(uploadedImages) ? uploadedImages : [])
    .filter((image) => image?.imageUrl);
  if (imageCandidates.length === 0) {
    return {
      result,
      summary: { embeddedImages: Array.isArray(uploadedImages) ? uploadedImages.length : 0, uploadedImages: 0, attachedImages: 0 },
    };
  }

  const headers = Array.isArray(result?.headers)
    ? result.headers.map((header) => String(header || '').trim())
    : [];
  const rows = Array.isArray(result?.rows)
    ? result.rows.map((row) => (Array.isArray(row) ? [...row] : []))
    : [];
  const warnings = Array.isArray(result?.warnings) ? [...result.warnings] : [];
  const imageUrlIndex = ensureProductImportHeader(headers, rows, 'image_url');
  const imageStatusIndex = ensureProductImportHeader(headers, rows, 'image_match_status');
  const matchedRows = new Set();
  let attachedImages = 0;
  let uncertainImages = 0;

  imageCandidates.forEach((image, imageIndex) => {
    let best = { index: -1, score: 0 };
    for (let rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
      if (matchedRows.has(rowIndex)) continue;
      const rowMap = productRowMap(headers, rows[rowIndex]);
      const score = scoreEmbeddedImageForProductRow(image, rowMap);
      if (score > best.score) best = { index: rowIndex, score };
    }

    let rowIndex = best.index;
    let status = image.uncertain || best.score < 5 ? 'uncertain' : 'matched';
    if (rowIndex < 0 || best.score < 2.25) {
      const fallbackIndex = imageCandidates.length === rows.length ? imageIndex : -1;
      if (fallbackIndex >= 0 && !matchedRows.has(fallbackIndex)) {
        rowIndex = fallbackIndex;
        status = 'uncertain';
      }
    }

    if (rowIndex < 0 || matchedRows.has(rowIndex)) {
      warnings.push(`Piki found an embedded image near "${limitText(image.rowText || image.id, 80)}" but could not safely match it to a product row.`);
      return;
    }

    while (rows[rowIndex].length <= imageStatusIndex) rows[rowIndex].push('');
    rows[rowIndex][imageUrlIndex] = image.imageUrl;
    rows[rowIndex][imageStatusIndex] = status;
    matchedRows.add(rowIndex);
    attachedImages += 1;
    if (status !== 'matched') {
      uncertainImages += 1;
      warnings.push(`Review the image attached to "${limitText(productRowMap(headers, rows[rowIndex]).name || image.rowText || 'this product', 80)}" because Piki matched it from nearby Excel content.`);
    }
  });

  return {
    result: {
      ...result,
      headers,
      rows,
      warnings: [...new Set(warnings.filter(Boolean))],
    },
    summary: {
      embeddedImages: uploadedImages.length,
      uploadedImages: imageCandidates.length,
      attachedImages,
      uncertainImages,
      uploadErrors: uploadedImages.filter((image) => image?.uploadError).length,
    },
  };
}

function ensureProductImportHeader(headers, rows, field) {
  let index = headers.findIndex((header) => String(header || '').trim().toLowerCase() === field);
  if (index >= 0) return index;
  headers.push(field);
  index = headers.length - 1;
  for (const row of rows) {
    while (row.length <= index) row.push('');
  }
  return index;
}

function productRowMap(headers, row) {
  const map = {};
  headers.forEach((header, index) => {
    const key = String(header || '').trim().toLowerCase();
    if (key) map[key] = row[index] == null ? '' : String(row[index]).trim();
  });
  return map;
}

function scoreEmbeddedImageForProductRow(image, rowMap) {
  const imageText = normalizeMatchText([image.rowText, image.id].filter(Boolean).join(' '));
  const rowText = normalizeMatchText([
    rowMap.name,
    rowMap.product_name,
    rowMap.item,
    rowMap.parent_product_name,
    rowMap.variant_name,
    rowMap.unit,
    rowMap.sku,
    rowMap.barcode,
  ].filter(Boolean).join(' '));
  if (!imageText || !rowText) return 0;

  let score = 0;
  const name = normalizeMatchText(rowMap.name || rowMap.product_name || rowMap.item || rowMap.parent_product_name);
  if (name && (imageText.includes(name) || rowText.includes(name))) score += 4;
  for (const key of ['sku', 'barcode']) {
    const value = normalizeMatchText(rowMap[key]);
    if (value && imageText.includes(value)) score += 6;
  }
  const imageTokens = new Set(imageText.split(' ').filter((token) => token.length > 2));
  const rowTokens = new Set(rowText.split(' ').filter((token) => token.length > 2));
  let overlap = 0;
  for (const token of rowTokens) {
    if (imageTokens.has(token)) overlap += 1;
  }
  score += overlap / Math.max(rowTokens.size || 1, 1) * 4;
  return score;
}

function normalizeMatchText(value) {
  return normalizeOptionalText(value)
    ?.toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim() || '';
}
function normalizeProductImportText(rawText) {
  const text = normalizeOptionalText(rawText);
  if (!text) {
    throw createHttpError(
      400,
      'Piki could not read text from this file. If it is a scanned PDF, export it to Excel/CSV or text first.',
    );
  }
  const cleaned = text.replace(/\u0000/g, '').replace(/[ \t]+/g, ' ').trim();
  return {
    text: cleaned.slice(0, PRODUCT_IMPORT_TEXT_LIMIT),
    truncated: cleaned.length > PRODUCT_IMPORT_TEXT_LIMIT,
  };
}

function normalizeProductImportHeaders(headers) {
  const normalized = [];
  if (Array.isArray(headers)) {
    for (const header of headers) {
      const key = String(header || '')
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '');
      if (PRODUCT_IMPORT_FIELD_SET.has(key) && !normalized.includes(key)) {
        normalized.push(key);
      }
    }
  }
  return normalized;
}

function flattenProductImportRows(rawRows) {
  if (!Array.isArray(rawRows)) return [];
  const flattened = [];
  for (const raw of rawRows) {
    if (
      raw &&
      typeof raw === 'object' &&
      !Array.isArray(raw) &&
      Array.isArray(raw.variants) &&
      raw.variants.length > 0
    ) {
      const parent = { ...raw };
      delete parent.variants;
      const parentName = normalizeOptionalText(
        valueForProductImportField(parent, 'name') ||
          parent.product_name ||
          parent.productName ||
          parent.item ||
          parent.item_name,
      );
      flattened.push(parent);
      for (const variant of raw.variants) {
        if (!variant || typeof variant !== 'object' || Array.isArray(variant)) {
          continue;
        }
        const variantName = normalizeOptionalText(
          valueForProductImportField(variant, 'variant_name') ||
            variant.variant ||
            variant.variation ||
            variant.option ||
            variant.size ||
            variant.color ||
            variant.colour ||
            variant.flavor ||
            variant.flavour ||
            variant.name,
        );
        flattened.push({
          ...parent,
          ...variant,
          name: parentName || valueForProductImportField(parent, 'name'),
          parent_product_id:
            valueForProductImportField(parent, 'product_id') ||
            parent.parent_product_id ||
            parent.parentProductId,
          parent_product_name:
            parentName || valueForProductImportField(parent, 'parent_product_name'),
          variant_name: variantName,
        });
      }
      continue;
    }
    flattened.push(raw);
  }
  return flattened;
}
function normalizeProductImportRows(parsed) {
  const sourceRows =
    (Array.isArray(parsed?.rows) && parsed.rows) ||
    (Array.isArray(parsed?.products) && parsed.products) ||
    (Array.isArray(parsed?.items) && parsed.items) ||
    [];
  const rawRows = flattenProductImportRows(sourceRows);
  let headers = normalizeProductImportHeaders(parsed?.headers);

  if (headers.length === 0 && rawRows.some((row) => row && typeof row === 'object' && !Array.isArray(row))) {
    headers = PRODUCT_IMPORT_FIELDS.filter((field) =>
      rawRows.some((row) => valueForProductImportField(row, field) != null),
    );
  }
  if (headers.length === 0) {
    headers = PRODUCT_IMPORT_FIELDS;
  }

  const rows = [];
  for (const raw of rawRows.slice(0, PRODUCT_IMPORT_MAX_ROWS)) {
    let row;
    if (Array.isArray(raw)) {
      row = headers.map((_, index) => normalizeProductImportCell(raw[index]));
    } else if (raw && typeof raw === 'object') {
      row = headers.map((field) => normalizeProductImportCell(valueForProductImportField(raw, field)));
    } else {
      continue;
    }
    const rowMap = Object.fromEntries(headers.map((field, index) => [field, row[index]]));
    if (
      normalizeOptionalText(rowMap.name) ||
      normalizeOptionalText(rowMap.sku) ||
      normalizeOptionalText(rowMap.barcode) ||
      normalizeOptionalText(rowMap.product_id) ||
      normalizeOptionalText(rowMap.variant_id) ||
      normalizeOptionalText(rowMap.parent_product_id) ||
      normalizeOptionalText(rowMap.parent_product_name) ||
      normalizeOptionalText(rowMap.variant_name)
    ) {
      rows.push(row);
    }
  }

  if (rows.length === 0) {
    throw createHttpError(422, 'Piki could not find usable product rows in this file.');
  }
  return { headers, rows };
}

function valueForProductImportField(row, field) {
  if (!row || typeof row !== 'object') return null;
  const aliases = {
    product_id: ['productId', 'id'],
    variant_id: ['variantId', 'product_variant_id', 'option_id'],
    parent_product_id: ['parentProductId', 'parent_id', 'base_product_id', 'main_product_id'],
    parent_product_name: ['parentProductName', 'parent_product', 'base_product', 'main_product', 'product_family'],
    variant_name: ['variantName', 'variant', 'variation', 'variety', 'option', 'option_name', 'size', 'color', 'colour', 'flavor', 'flavour', 'pack_size'],
    stock_received: ['stockReceived', 'received_qty', 'quantity_received'],
    low_stock: ['lowStock', 'reorder_level', 'minimum_stock'],
    stock_unit: ['stockUnit', 'inventory_unit'],
    sale_unit: ['saleUnit', 'selling_unit'],
    purchase_unit: ['purchaseUnit', 'buying_unit'],
    sale_to_stock_factor: ['saleToStockFactor', 'stock_factor', 'conversion'],
    purchase_to_stock_factor: ['purchaseToStockFactor', 'purchase_factor'],
    track_stock: ['trackStock', 'tracks_stock', 'stock_tracking'],
    image_url: ['imageUrl', 'image', 'photo'],
    image_urls_json: ['imageUrlsJson', 'imageUrls', 'images', 'photos'],
    show_online: ['showOnline', 'online', 'catalog', 'publish'],
    is_featured: ['isFeatured', 'featured'],
    expiry_date: ['expiryDate', 'expires_on', 'expiry'],
    batch_number: ['batchNumber', 'batch'],
  };
  for (const key of [field, ...(aliases[field] || [])]) {
    if (row[key] != null) {
      return row[key];
    }
  }
  return null;
}

function normalizeProductImportCell(value) {
  if (value == null) return '';
  if (Array.isArray(value)) {
    return JSON.stringify(value.map((item) => String(item || '').trim()).filter(Boolean));
  }
  if (typeof value === 'object') {
    return JSON.stringify(value);
  }
  return String(value).trim();
}

function productImportWarnings(parsed, sourceTextTruncated) {
  const warnings = [];
  if (Array.isArray(parsed?.warnings)) {
    warnings.push(
      ...parsed.warnings
        .map((item) => normalizeOptionalText(item))
        .filter(Boolean)
        .slice(0, 6),
    );
  }
  if (sourceTextTruncated) {
    warnings.push('The file was long, so Piki reviewed the first part of the extracted text.');
  }
  return warnings;
}

function normalizeSalesImportHeaders(headers) {
  const normalized = [];
  if (Array.isArray(headers)) {
    for (const header of headers) {
      const key = String(header || '')
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '');
      if (SALES_IMPORT_FIELD_SET.has(key) && !normalized.includes(key)) {
        normalized.push(key);
      }
    }
  }
  return normalized;
}

function normalizeSalesImportRows(parsed) {
  const rawRows =
    (Array.isArray(parsed?.rows) && parsed.rows) ||
    (Array.isArray(parsed?.sales) && parsed.sales) ||
    (Array.isArray(parsed?.items) && parsed.items) ||
    [];
  let headers = normalizeSalesImportHeaders(parsed?.headers);

  if (headers.length === 0 && rawRows.some((row) => row && typeof row === 'object' && !Array.isArray(row))) {
    headers = SALES_IMPORT_FIELDS.filter((field) =>
      rawRows.some((row) => valueForSalesImportField(row, field) != null),
    );
  }
  if (headers.length === 0) {
    headers = SALES_IMPORT_FIELDS;
  }

  const rows = [];
  for (const raw of rawRows.slice(0, SALES_IMPORT_MAX_ROWS)) {
    let row;
    if (Array.isArray(raw)) {
      row = headers.map((_, index) => normalizeProductImportCell(raw[index]));
    } else if (raw && typeof raw === 'object') {
      row = headers.map((field) => normalizeProductImportCell(valueForSalesImportField(raw, field)));
    } else {
      continue;
    }
    const rowMap = Object.fromEntries(headers.map((field, index) => [field, row[index]]));
    if (
      normalizeOptionalText(rowMap.total) ||
      normalizeOptionalText(rowMap.product) ||
      normalizeOptionalText(rowMap.service) ||
      normalizeOptionalText(rowMap.sku) ||
      normalizeOptionalText(rowMap.barcode) ||
      normalizeOptionalText(rowMap.product_id) ||
      normalizeOptionalText(rowMap.service_id)
    ) {
      rows.push(row);
    }
  }

  if (rows.length === 0) {
    throw createHttpError(422, 'Piki could not find usable sales rows in this file.');
  }
  return { headers, rows };
}

function valueForSalesImportField(row, field) {
  if (!row || typeof row !== 'object') return null;
  const aliases = {
    payment_type: ['paymentType', 'payment_method', 'paymentMethod', 'method'],
    customer_name: ['customerName', 'customer', 'client', 'client_name'],
    due_date: ['dueDate', 'credit_due_date', 'kopesha_due_date'],
    line_type: ['lineType', 'type', 'item_type'],
    product_id: ['productId'],
    variant_id: ['variantId'],
    product: ['productName', 'product_name', 'item', 'item_name', 'name'],
    service_id: ['serviceId'],
    service: ['serviceName', 'service_name'],
    unit_price: ['unitPrice', 'price', 'rate', 'selling_price'],
    unit_cost: ['unitCost', 'cost'],
  };
  for (const key of [field, ...(aliases[field] || [])]) {
    if (row[key] != null) {
      return row[key];
    }
  }
  return null;
}

function salesImportWarnings(parsed, sourceTextTruncated) {
  const warnings = [];
  if (Array.isArray(parsed?.warnings)) {
    warnings.push(
      ...parsed.warnings
        .map((item) => normalizeOptionalText(item))
        .filter(Boolean)
        .slice(0, 6),
    );
  }
  if (sourceTextTruncated) {
    warnings.push('The file was long, so Piki reviewed the first part of the extracted text.');
  }
  return warnings;
}

function normalizeSmartImportTarget(value) {
  const clean = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!clean) return '';
  if (['product', 'products', 'catalog', 'inventory', 'stock', 'items', 'item_list'].includes(clean)) {
    return 'products';
  }
  if (['sale', 'sales', 'sales_records', 'transactions', 'receipts', 'receipt', 'pos_sales'].includes(clean)) {
    return 'sales';
  }
  if (['customer', 'customers', 'contacts', 'contact', 'clients', 'client'].includes(clean)) {
    return 'customers';
  }
  if (['expense', 'expenses', 'spend', 'spending', 'costs', 'operating_costs'].includes(clean)) {
    return 'expenses';
  }
  return SMART_IMPORT_TARGETS[clean] ? clean : '';
}

function normalizeSmartImportHeaders(headers, config) {
  const normalized = [];
  if (Array.isArray(headers)) {
    for (const header of headers) {
      const key = String(header || '')
        .trim()
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '');
      if (config.fieldSet.has(key) && !normalized.includes(key)) {
        normalized.push(key);
      }
    }
  }
  return normalized;
}

function valueForCustomerImportField(row, field) {
  if (!row || typeof row !== 'object') return null;
  const aliases = {
    customer_id: ['customerId', 'client_id', 'id'],
    name: ['customerName', 'customer_name', 'client', 'client_name', 'contact_name', 'full_name'],
    phone: ['customerPhone', 'customer_phone', 'mobile', 'phone_number', 'tel', 'telephone'],
    email: ['customerEmail', 'customer_email', 'email_address', 'mail'],
  };
  for (const key of [field, ...(aliases[field] || [])]) {
    if (row[key] != null) {
      return row[key];
    }
  }
  return null;
}

function valueForExpenseImportField(row, field) {
  if (!row || typeof row !== 'object') return null;
  const aliases = {
    title: ['expense', 'expense_title', 'description', 'details', 'item', 'name'],
    amount: ['total', 'cost', 'value', 'paid', 'expense_amount'],
    date: ['incurred_on', 'expense_date', 'paid_on', 'transaction_date'],
    category: ['category_name', 'type', 'expense_type'],
    note: ['notes', 'remarks', 'comment'],
  };
  for (const key of [field, ...(aliases[field] || [])]) {
    if (row[key] != null) {
      return row[key];
    }
  }
  return null;
}

function valueForSmartImportField(row, target, field) {
  switch (target) {
    case 'products':
      return valueForProductImportField(row, field);
    case 'sales':
      return valueForSalesImportField(row, field);
    case 'customers':
      return valueForCustomerImportField(row, field);
    case 'expenses':
      return valueForExpenseImportField(row, field);
    default:
      return null;
  }
}

function smartImportRowIsUsable(target, rowMap) {
  switch (target) {
    case 'products':
      return (
        normalizeOptionalText(rowMap.name) ||
        normalizeOptionalText(rowMap.sku) ||
        normalizeOptionalText(rowMap.barcode) ||
        normalizeOptionalText(rowMap.product_id) ||
        normalizeOptionalText(rowMap.variant_id) ||
        normalizeOptionalText(rowMap.parent_product_id) ||
        normalizeOptionalText(rowMap.parent_product_name) ||
        normalizeOptionalText(rowMap.variant_name)
      );
    case 'sales':
      return (
        normalizeOptionalText(rowMap.total) ||
        normalizeOptionalText(rowMap.product) ||
        normalizeOptionalText(rowMap.service) ||
        normalizeOptionalText(rowMap.sku) ||
        normalizeOptionalText(rowMap.barcode) ||
        normalizeOptionalText(rowMap.product_id) ||
        normalizeOptionalText(rowMap.service_id)
      );
    case 'customers':
      return normalizeOptionalText(rowMap.name);
    case 'expenses':
      return normalizeOptionalText(rowMap.title) && normalizeOptionalText(rowMap.amount);
    default:
      return false;
  }
}

function normalizeSmartImportRows(parsed) {
  const target = normalizeSmartImportTarget(
    parsed?.target || parsed?.importTarget || parsed?.import_type || parsed?.type,
  );
  if (!target || !SMART_IMPORT_TARGETS[target]) {
    throw createHttpError(
      422,
      'Piki could not decide where this file belongs. Try a file with clearer product, sales, customer, or expense headings.',
    );
  }

  const config = SMART_IMPORT_TARGETS[target];
  const sourceRows =
    (Array.isArray(parsed?.rows) && parsed.rows) ||
    (Array.isArray(parsed?.[target]) && parsed[target]) ||
    (Array.isArray(parsed?.items) && parsed.items) ||
    [];
  const rawRows = target === 'products' ? flattenProductImportRows(sourceRows) : sourceRows;
  let headers = normalizeSmartImportHeaders(parsed?.headers, config);

  if (headers.length === 0 && rawRows.some((row) => row && typeof row === 'object' && !Array.isArray(row))) {
    headers = config.fields.filter((field) =>
      rawRows.some((row) => valueForSmartImportField(row, target, field) != null),
    );
  }
  if (headers.length === 0) {
    headers = config.fields;
  }

  const rows = [];
  for (const raw of rawRows.slice(0, config.maxRows)) {
    let row;
    if (Array.isArray(raw)) {
      row = headers.map((_, index) => normalizeProductImportCell(raw[index]));
    } else if (raw && typeof raw === 'object') {
      row = headers.map((field) => normalizeProductImportCell(valueForSmartImportField(raw, target, field)));
    } else {
      continue;
    }
    const rowMap = Object.fromEntries(headers.map((field, index) => [field, row[index]]));
    if (smartImportRowIsUsable(target, rowMap)) {
      rows.push(row);
    }
  }

  if (rows.length === 0) {
    throw createHttpError(422, `Piki classified this as ${config.label}, but could not find usable rows.`);
  }
  return { target, headers, rows };
}

function smartImportWarnings(parsed, sourceTextTruncated) {
  const warnings = [];
  if (Array.isArray(parsed?.warnings)) {
    warnings.push(
      ...parsed.warnings
        .map((item) => normalizeOptionalText(item))
        .filter(Boolean)
        .slice(0, 6),
    );
  }
  const confidence = Number(parsed?.confidence);
  if (Number.isFinite(confidence) && confidence < 0.65) {
    warnings.push('Piki was not fully confident about the destination, so review the preview carefully.');
  }
  if (sourceTextTruncated) {
    warnings.push('The file was long, so Piki reviewed the first part of the extracted text.');
  }
  return warnings;
}

async function requestOpenRouterSmartFileExtraction({
  fetchImpl,
  aiConfig,
  fileName,
  extension,
  sourceText,
  sourceTextTruncated,
  instruction = null,
}) {
  const ownerInstruction = normalizeOptionalText(instruction);
  const prompt = `You are Piki cloud AI helping a POS owner upload any business file and route it to the correct Piki POS import area.

Classify the file as exactly one target and extract rows for that target.
Return JSON only, no markdown.

JSON shape:
{
  "target": "products" | "sales" | "customers" | "expenses" | "unknown",
  "confidence": 0.0,
  "summary": "short practical summary",
  "headers": ["canonical_field"],
  "rows": [["cell value"]],
  "warnings": ["short warning for the cashier"]
}

Targets and allowed headers:
- products: ${PRODUCT_IMPORT_FIELDS.join(', ')}
- sales: ${SALES_IMPORT_FIELDS.join(', ')}
- customers: ${CUSTOMER_IMPORT_FIELDS.join(', ')}
- expenses: ${EXPENSE_IMPORT_FIELDS.join(', ')}

Routing rules:
- products: catalog items, stock lists, price lists, product spreadsheets, supplier product catalogs, inventory lists.
- sales: receipts, POS exports, historical sales, paid invoices, transaction lists, service/product sale records.
- customers: customer/contact/client lists with names and optional phone/email.
- expenses: spending, bills, operating costs, expense ledgers with title/description and amount.
- If several targets appear, choose the dominant rows that the owner likely wants imported and add a warning.
- If the destination is unclear, return target "unknown" with no rows.
${ownerInstruction ? `- Owner correction/instruction: ${ownerInstruction}` : ''}

Extraction rules:
- Use only facts visible in the file. Do not invent names, prices, contacts, dates, totals, or categories.
- Keep values as strings. Use numeric strings for quantities, prices, totals, amounts, tax, discount, stock, and costs.
- For product variants/varieties such as size, color, flavor, or pack, use product headers name, parent_product_name, and variant_name instead of creating duplicate full-name products.
- Do not turn totals, terms, addresses, headers, payment instructions, or notes into item rows.
- Limit products to ${PRODUCT_IMPORT_MAX_ROWS}, sales to ${SALES_IMPORT_MAX_ROWS}, customers to ${CUSTOMER_IMPORT_MAX_ROWS}, and expenses to ${EXPENSE_IMPORT_MAX_ROWS}.

FILE:
Name: ${fileName || 'business file'}
Type: ${extension || 'unknown'}
${sourceTextTruncated ? 'Note: source text was truncated before model review.' : ''}

EXTRACTED TEXT:
${sourceText}`;

  const response = await fetchImpl(`${OPENROUTER_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${aiConfig.api_key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://pikipos.com',
      'X-Title': 'Piki POS Smart File Import',
    },
    body: JSON.stringify({
      model: aiConfig.model || 'openai/gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 4096,
      temperature: 0.05,
    }),
  });

  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'OpenRouter smart import failed',
    );
  }

  const content = extractOpenRouterTextContent(body);
  const parsed = parseJsonObjectFromText(content);
  if (!parsed) {
    throw createHttpError(502, 'Piki AI did not return a valid smart import plan.');
  }
  const normalized = normalizeSmartImportRows(parsed);
  return {
    target: normalized.target,
    confidence: Number(parsed.confidence) || null,
    summary:
      normalizeOptionalText(parsed.summary) ||
      `Piki classified the file as ${SMART_IMPORT_TARGETS[normalized.target].label} and found ${normalized.rows.length} row${normalized.rows.length === 1 ? '' : 's'}.`,
    headers: normalized.headers,
    rows: normalized.rows,
    warnings: smartImportWarnings(parsed, sourceTextTruncated),
    usage: body?.usage || {},
    model: aiConfig.model || 'openai/gpt-4o-mini',
  };
}

async function requestOpenRouterStorefrontTheme({
  fetchImpl,
  aiConfig,
  instruction,
  theme,
}) {
  const currentTheme = {
    name: theme.name,
    storefrontType: theme.storefrontType,
    design: theme.design,
    checkout: theme.checkout,
  };
  const prompt = `You are Piki's storefront design agent. Customize a safe ecommerce theme for a real business.

Return JSON only, with no markdown or commentary:
{
  "name": "short theme name",
  "summary": "one sentence explaining the changes",
  "design": {
    "backgroundColor": "#RRGGBB",
    "textColor": "#RRGGBB",
    "mutedColor": "#RRGGBB",
    "surfaceColor": "#RRGGBB",
    "surfaceElevatedColor": "#RRGGBB",
    "borderColor": "#RRGGBB",
    "accentColor": "#RRGGBB",
    "fontFamily": "inter|modern|serif|rounded|system",
    "heroStyle": "cover|split|minimal",
    "cardStyle": "bordered|elevated|minimal",
    "imageRatio": "square|portrait|landscape",
    "density": "comfortable|compact",
    "cornerStyle": "sharp|soft|rounded|pill"
  },
  "checkout": {
    "paymentMethods": ["manual", "mpesa"],
    "defaultPaymentMethod": "manual|mpesa",
    "fulfillmentMethods": ["pickup", "delivery"],
    "defaultFulfillmentMethod": "pickup|delivery",
    "showDeliveryAddress": true,
    "showOrderNote": true,
    "showOrderTracking": true,
    "checkoutTitle": "short title",
    "checkoutButtonLabel": "short action label",
    "successMessage": "short confirmation message"
  }
}

Rules:
- Return a complete design and checkout object.
- Use accessible contrast between text, backgrounds, surfaces, and the accent.
- Do not output CSS, HTML, JavaScript, URLs, credentials, analytics, pixels, or scripts.
- Do not add payment providers outside manual and mpesa.
- Customer name and phone always remain required and cannot be removed.
- Preserve values that the owner did not ask to change.

CURRENT THEME:
${JSON.stringify(currentTheme)}

OWNER REQUEST:
${instruction}`;

  const response = await fetchImpl(`${OPENROUTER_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${aiConfig.api_key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://pikipos.com',
      'X-Title': 'Piki Storefront Designer',
    },
    body: JSON.stringify({
      model: aiConfig.model || 'openai/gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 1800,
      temperature: 0.25,
    }),
  });
  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'Piki storefront customization failed',
    );
  }
  const parsed = parseJsonObjectFromText(extractOpenRouterTextContent(body));
  if (!parsed || typeof parsed !== 'object') {
    throw createHttpError(502, 'Piki did not return a valid storefront theme.');
  }
  return {
    name: limitText(parsed.name, 80) || theme.name,
    summary:
      limitText(parsed.summary, 240) ||
      'Piki prepared a storefront theme draft for review.',
    design:
      parsed.design && typeof parsed.design === 'object' ? parsed.design : {},
    checkout:
      parsed.checkout && typeof parsed.checkout === 'object'
        ? parsed.checkout
        : {},
  };
}

async function requestOpenRouterProductFileExtraction({
  fetchImpl,
  aiConfig,
  fileName,
  extension,
  sourceText,
  sourceTextTruncated,
}) {
  const prompt = `You are Piki cloud AI helping a POS owner import products from a catalog, invoice, quote, PDF, document, or product list.

Extract products and map them to Piki POS product import fields.
Return JSON only, no markdown.

JSON shape:
{
  "summary": "short practical summary",
  "headers": ["name", "parent_product_name", "variant_name", "price", "cost", "sku", "barcode", "category", "stock"],
  "rows": [
    ["Fresh Milk", "Fresh Milk", "500ml", "60", "45", "MILK-500", "123456789", "Dairy", "12"]
  ],
  "warnings": ["Only include facts visible in the file."]
}

Allowed headers:
${PRODUCT_IMPORT_FIELDS.join(', ')}

Rules:
- Each row must represent one real product line from the file.
- Include name whenever visible. Do not invent product names.
- If a row is a variant/variety (size, color, flavor, pack), put the parent product in name and parent_product_name, and put only the option text in variant_name.
- Example: Fresh Milk 500ml should use name Fresh Milk and variant_name 500ml; do not save the full text as a separate product when it is clearly a variant.
- If you return products with nested variants, each variant must include a visible variant_name and only facts from the file.
- Do not invent prices, cost, stock, barcode, SKU, expiry, or images. Leave unknown cells blank.
- Use numeric strings for price, cost, stock, stock_received, low_stock, and conversion factors.
- Use true/false for track_stock, show_online, and is_featured when visible or strongly implied.
- Use category when a section, department, or product group is visible.
- Use description for short useful details that are not the product name.
- Use image_url only for visible direct image URLs; use image_urls_json only for multiple image URLs.
- Limit to the most relevant ${PRODUCT_IMPORT_MAX_ROWS} products.
- If the file contains notes, totals, payment lines, customer details, supplier details, or terms, do not turn those into products.

FILE:
Name: ${fileName || 'product file'}
Type: ${extension || 'unknown'}
${sourceTextTruncated ? 'Note: source text was truncated before model review.' : ''}

EXTRACTED TEXT:
${sourceText}`;

  const response = await fetchImpl(`${OPENROUTER_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${aiConfig.api_key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://pikipos.com',
      'X-Title': 'Piki POS Product File Import',
    },
    body: JSON.stringify({
      model: aiConfig.model || 'openai/gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 4096,
      temperature: 0.1,
    }),
  });

  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'OpenRouter product import failed',
    );
  }

  const content = extractOpenRouterTextContent(body);
  const parsed = parseJsonObjectFromText(content);
  if (!parsed) {
    throw createHttpError(502, 'Piki AI did not return a valid product import plan.');
  }
  const normalized = normalizeProductImportRows(parsed);
  return {
    summary:
      normalizeOptionalText(parsed.summary) ||
      `Piki found ${normalized.rows.length} product row${normalized.rows.length === 1 ? '' : 's'} in the file.`,
    headers: normalized.headers,
    rows: normalized.rows,
    warnings: productImportWarnings(parsed, sourceTextTruncated),
    usage: body?.usage || {},
    model: aiConfig.model || 'openai/gpt-4o-mini',
  };
}

async function requestOpenRouterProductImageFileExtraction({
  fetchImpl,
  aiConfig,
  fileName,
  extension,
  imageDataUrl,
}) {
  const prompt = `You are Piki cloud AI helping a POS owner import products from an image, screenshot, supplier invoice photo, receipt photo, or WhatsApp price list screenshot.

Extract visible product rows and map them to Piki POS product import fields.
Return JSON only, no markdown.

JSON shape:
{
  "summary": "short practical summary",
  "headers": ["name", "parent_product_name", "variant_name", "price", "cost", "sku", "barcode", "category", "stock"],
  "rows": [
    ["Fresh Milk", "Fresh Milk", "500ml", "60", "45", "MILK-500", "123456789", "Dairy", "12"]
  ],
  "warnings": ["Review blurry or low-confidence rows."]
}

Allowed headers:
${PRODUCT_IMPORT_FIELDS.join(', ')}

Rules:
- Use only facts visible in the image. Do not invent product names, prices, stock, barcode, SKU, or categories.
- Each row must represent one real product line from the image.
- If a visible line is a variant/variety (size, color, flavor, pack), put the parent product in name and parent_product_name, and put only the option text in variant_name.
- Example: Fresh Milk 500ml should use name Fresh Milk and variant_name 500ml; do not save the full text as a separate product when it is clearly a variant.
- If text is blurry or partially hidden, include the row only when the product name is reasonably clear and add a warning.
- Use numeric strings for price, cost, stock, stock_received, low_stock, and conversion factors.
- If the image is a receipt/invoice, extract product lines, not totals, taxes, payment lines, or customer details.
- Limit to the most relevant ${PRODUCT_IMPORT_MAX_ROWS} products.

FILE:
Name: ${fileName || 'product image'}
Type: ${extension || 'image'}`;

  const response = await fetchImpl(`${OPENROUTER_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${aiConfig.api_key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://pikipos.com',
      'X-Title': 'Piki POS Product Image Import',
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
      max_tokens: 4096,
      temperature: 0.1,
    }),
  });

  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'OpenRouter product image import failed',
    );
  }

  const content = extractOpenRouterTextContent(body);
  const parsed = parseJsonObjectFromText(content);
  if (!parsed) {
    throw createHttpError(502, 'Piki AI did not return a valid product image import plan.');
  }
  const normalized = normalizeProductImportRows(parsed);
  return {
    summary:
      normalizeOptionalText(parsed.summary) ||
      `Piki found ${normalized.rows.length} product row${normalized.rows.length === 1 ? '' : 's'} in the image.`,
    headers: normalized.headers,
    rows: normalized.rows,
    warnings: [
      'Piki used cloud vision to read this image. Review blurry or unclear rows before importing.',
      ...productImportWarnings(parsed, false),
    ],
    usage: body?.usage || {},
    model: aiConfig.model || 'openai/gpt-4o-mini',
  };
}

async function requestOpenRouterSalesFileExtraction({
  fetchImpl,
  aiConfig,
  fileName,
  extension,
  sourceText,
  sourceTextTruncated,
}) {
  const prompt = `You are Piki cloud AI helping a POS owner import historical sales records from a receipt, invoice, POS export, PDF, document, or sales list.

Extract sales rows and map them to Piki POS sales import fields.
Return JSON only, no markdown.

JSON shape:
{
  "summary": "short practical summary",
  "headers": ["date", "total", "payment_type", "product", "quantity", "unit_price"],
  "rows": [
    ["2026-06-20", "120", "Cash", "Milk 500ml", "2", "60"]
  ],
  "warnings": ["Only include facts visible in the file."]
}

Allowed headers:
${SALES_IMPORT_FIELDS.join(', ')}

Rules:
- Use one row per sale line when products/services are visible.
- Use summary sale rows only when the file gives a sale total but not line items.
- Do not invent products, services, customers, totals, prices, payment type, dates, or references.
- Use line_type as product or service when known.
- Use product, sku, barcode, product_id, or variant_id for product lines.
- Use service or service_id for service lines.
- Use customer_name and phone only when visible.
- Use payment_type values like Cash, M-Pesa, Card, Kopesha, or the visible method.
- Kopesha/credit rows need customer_name and due_date if visible.
- Use numeric strings for total, tax, discount, quantity, unit_price, and unit_cost.
- Do not turn subtotals, totals, terms, balances, addresses, or payment instructions into product lines.
- Limit to the most relevant ${SALES_IMPORT_MAX_ROWS} rows.

FILE:
Name: ${fileName || 'sales file'}
Type: ${extension || 'unknown'}
${sourceTextTruncated ? 'Note: source text was truncated before model review.' : ''}

EXTRACTED TEXT:
${sourceText}`;

  const response = await fetchImpl(`${OPENROUTER_BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${aiConfig.api_key}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://pikipos.com',
      'X-Title': 'Piki POS Sales File Import',
    },
    body: JSON.stringify({
      model: aiConfig.model || 'openai/gpt-4o-mini',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 4096,
      temperature: 0.1,
    }),
  });

  const body = await readMaybeJson(response);
  if (!response.ok) {
    throw createHttpError(
      response.status === 401 ? 502 : response.status,
      body?.error?.message || body?.message || 'OpenRouter sales import failed',
    );
  }

  const content = extractOpenRouterTextContent(body);
  const parsed = parseJsonObjectFromText(content);
  if (!parsed) {
    throw createHttpError(502, 'Piki AI did not return a valid sales import plan.');
  }
  const normalized = normalizeSalesImportRows(parsed);
  return {
    summary:
      normalizeOptionalText(parsed.summary) ||
      `Piki found ${normalized.rows.length} sales row${normalized.rows.length === 1 ? '' : 's'} in the file.`,
    headers: normalized.headers,
    rows: normalized.rows,
    warnings: salesImportWarnings(parsed, sourceTextTruncated),
    usage: body?.usage || {},
    model: aiConfig.model || 'openai/gpt-4o-mini',
  };
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

aiJobs.registerHandler('product_import', runProductImportAiJob);

async function runProductImportAiJob({ job, updateJob, addEvent, saveDraftItems }) {
  const totalSteps = 7;
  const step = async ({ completedSteps, currentStep, progress, eventType, title, message, toolName, level = 'info', metadata = null }) => {
    await updateJob(job.id, job.business_id, {
      completedSteps,
      totalSteps,
      currentStep,
      progress,
    });
    await addEvent({
      jobId: job.id,
      businessId: job.business_id,
      branchId: job.branch_id,
      eventType,
      level,
      title,
      message,
      toolName,
      progress,
      metadata,
    });
  };

  await step({
    completedSteps: 1,
    currentStep: 'Reading uploaded file',
    progress: 12,
    eventType: 'file_parsed',
    title: 'Reading uploaded file',
    message: job.source_file_name ? `Reading ${job.source_file_name}` : 'Reading the uploaded file',
    toolName: 'parse_uploaded_file',
  });

  const file = decodeProductImportFile({
    fileBase64: job.source_file_base64,
    fileName: job.source_file_name,
    mimeType: job.source_mime_type,
    extension: job.source_extension,
  });

  const aiConfig = await loadPlatformAiConfig();
  if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
    throw createHttpError(403, 'AI is not enabled by the platform administrator');
  }

  const fetch = (await import('node-fetch')).default;
  const sourceText = normalizeOptionalText(job.source_text);
  let workbookAssets = null;
  if (file.extension === 'xlsx') {
    workbookAssets = await extractXlsxProductImport(file.bytes);
  }
  let source = { text: '', truncated: false };
  let result;
  let imageAttachSummary = null;
  if (isProductImportImageFile(file) && !sourceText) {
    await step({
      completedSteps: 2,
      currentStep: 'Reading product image',
      progress: 28,
      eventType: 'ai_extracting',
      title: 'Reading product image',
      message: 'Piki is using cloud vision to extract product rows.',
      toolName: 'extract_products_from_image',
      metadata: { image: true },
    });
    result = await requestOpenRouterProductImageFileExtraction({
      fetchImpl: fetch,
      aiConfig,
      fileName: file.fileName,
      extension: file.extension,
      imageDataUrl: productImportImageDataUrl(file),
    });
  } else {
    const rawText = sourceText || workbookAssets?.text || (await extractTextFromProductImportFile(file));
    source = normalizeProductImportText(rawText);
    await step({
      completedSteps: 2,
      currentStep: 'Extracting product rows',
      progress: 28,
      eventType: 'ai_extracting',
      title: 'Extracting products',
      message: 'Piki is mapping visible file content into product rows.',
      toolName: 'extract_products_from_text',
      metadata: { sourceTextTruncated: source.truncated },
    });
    result = await requestOpenRouterProductFileExtraction({
      fetchImpl: fetch,
      aiConfig,
      fileName: file.fileName,
      extension: file.extension,
      sourceText: source.text,
      sourceTextTruncated: source.truncated,
    });
  }

  await step({
    completedSteps: 3,
    currentStep: `Found ${result.rows.length} possible products`,
    progress: 52,
    eventType: 'products_found',
    title: `Found ${result.rows.length} possible products`,
    message: result.summary,
    toolName: 'extract_products_from_text',
    metadata: { headers: result.headers, warnings: result.warnings },
  });

  if (workbookAssets?.images?.length) {
    await step({
      completedSteps: 4,
      currentStep: 'Matching embedded images',
      progress: 60,
      eventType: 'image_matching',
      title: 'Matching product images',
      message: `Piki found ${workbookAssets.images.length} embedded image${workbookAssets.images.length === 1 ? '' : 's'} in the workbook.`,
      toolName: 'match_embedded_images',
      metadata: { embeddedImages: workbookAssets.images.length },
    });
    const uploadedImages = await uploadEmbeddedXlsxProductImages({
      fetchImpl: fetch,
      job,
      images: workbookAssets.images,
    });
    const imageResult = attachUploadedProductImagesToImportResult(result, uploadedImages);
    result = imageResult.result;
    imageAttachSummary = imageResult.summary;
  }

  await step({
    completedSteps: 5,
    currentStep: 'Validating draft rows',
    progress: 64,
    eventType: 'validating_row',
    title: 'Checking draft rows',
    message: 'Piki is checking product names, prices, stock, duplicates, and image warnings.',
    toolName: 'validate_product_rows',
    metadata: imageAttachSummary,
  });

  const draftItems = await saveDraftItems({
    job,
    headers: result.headers,
    rows: result.rows,
    warnings: result.warnings,
  });

  const duplicateSummary = await annotateProductDraftDuplicates({
    job,
    draftItems,
    addEvent,
  });

  await step({
    completedSteps: 6,
    currentStep: 'Preparing import draft',
    progress: 82,
    eventType: 'product_prepared',
    title: 'Preparing product draft',
    message: 'Piki saved draft rows for review before anything is imported.',
    toolName: 'create_import_draft_item',
    metadata: duplicateSummary,
  });

  const counts = await loadProductDraftCounts(job.id, job.business_id);
  const summary = {
    summary: result.summary,
    headers: result.headers,
    rows: result.rows,
    warnings: result.warnings,
    fileName: file.fileName,
    extension: file.extension,
    sourceTextTruncated: source.truncated,
    model: result.model,
    usage: result.usage,
    draftCounts: counts,
    imageAttachSummary,
  };

  await updateJob(job.id, job.business_id, {
    status: 'waiting_for_review',
    progress: 100,
    completedSteps: totalSteps,
    totalSteps,
    currentStep: 'Draft ready for review',
    completedAt: new Date().toISOString(),
    resultJson: summary,
  });
  await addEvent({
    jobId: job.id,
    businessId: job.business_id,
    branchId: job.branch_id,
    eventType: 'review_required',
    title: 'Draft ready for review',
    message: `Review ${counts.total} product row${counts.total === 1 ? '' : 's'} before importing.`,
    toolName: 'create_import_draft_item',
    progress: 100,
    metadata: counts,
  });
}

async function annotateProductDraftDuplicates({ job, draftItems, addEvent }) {
  let duplicateCount = 0;
  let emitted = 0;
  for (const item of draftItems) {
    const match = await findMatchingProductForDraft(job, item);
    if (!match) {
      if (item.productName && emitted < 8) {
        emitted += 1;
        await addEvent({
          jobId: job.id,
          businessId: job.business_id,
          branchId: job.branch_id,
          eventType: 'duplicate_check',
          title: 'Checking duplicate',
          message: `No existing match found for ${item.productName}`,
          toolName: 'match_existing_products',
          entityType: 'product',
          entityName: item.productName,
          progress: 70,
        });
      }
      continue;
    }
    duplicateCount += 1;
    await query(
      `UPDATE ai_import_draft_items
       SET matched_product_id = $3,
           status = CASE WHEN status = 'invalid' THEN status ELSE 'duplicate' END,
           updated_at = NOW()
       WHERE id = $1 AND business_id = $2`,
      [item.id, job.business_id, match.id],
    );
    if (emitted < 12) {
      emitted += 1;
      await addEvent({
        jobId: job.id,
        businessId: job.business_id,
        branchId: job.branch_id,
        eventType: 'duplicate_check',
        level: 'warning',
        title: 'Possible duplicate found',
        message: `${item.productName || item.sku || item.barcode} may match ${match.name}`,
        toolName: 'match_existing_products',
        entityType: 'product',
        entityId: match.id,
        entityName: match.name,
        progress: 72,
      });
    }
  }
  return { duplicates: duplicateCount, checked: draftItems.length };
}

async function findMatchingProductForDraft(job, item) {
  const clauses = [];
  const params = [job.business_id, job.branch_id || 'main_branch'];
  function addMatch(column, value) {
    const normalized = normalizeOptionalText(value);
    if (!normalized) return;
    params.push(normalized.toLowerCase());
    clauses.push(`LOWER(TRIM(COALESCE(${column}, ''))) = $${params.length}`);
  }
  addMatch('barcode', item.barcode);
  addMatch('sku', item.sku);
  addMatch('name', item.productName);
  if (clauses.length === 0) {
    return null;
  }
  const result = await query(
    `SELECT id, name
     FROM products
     WHERE business_id = $1
       AND deleted_at IS NULL
       AND COALESCE(branch_id, 'main_branch') = COALESCE($2, 'main_branch')
       AND (${clauses.join(' OR ')})
     LIMIT 1`,
    params,
  );
  return result.rows[0] || null;
}

async function loadProductDraftCounts(jobId, businessId) {
  const result = await query(
    `SELECT
       COUNT(*)::int AS total,
       COUNT(*) FILTER (WHERE status = 'ready')::int AS ready,
       COUNT(*) FILTER (WHERE status = 'needs_review')::int AS needs_review,
       COUNT(*) FILTER (WHERE status = 'duplicate')::int AS duplicates,
       COUNT(*) FILTER (WHERE status = 'invalid')::int AS invalid
     FROM ai_import_draft_items
     WHERE job_id = $1 AND business_id = $2`,
    [jobId, businessId],
  );
  const row = result.rows[0] || {};
  return {
    total: Number(row.total || 0),
    ready: Number(row.ready || 0),
    needsReview: Number(row.needs_review || 0),
    duplicates: Number(row.duplicates || 0),
    invalid: Number(row.invalid || 0),
  };
}

function resolveAiJobBranchId(req, businessContext) {
  const requested = normalizeOptionalText(req.body?.branchId || req.query?.branchId);
  const scope = resolveDataScope(businessContext, requested);
  if (requested) {
    return requested;
  }
  if (scope.branchIds?.length === 1) {
    return scope.branchIds[0];
  }
  return 'main_branch';
}

app.post('/api/ai/imports', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const importType = normalizeOptionalText(req.body?.importType || req.body?.jobType) || 'products';
    if (!['products', 'product_import'].includes(importType)) {
      throw createHttpError(400, 'Only product AI import jobs are supported in this version');
    }
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.products);
    if (!hasBusinessFeature(businessContext, FEATURE_KEYS.products)) {
      throw createHttpError(403, 'This employee cannot manage products');
    }

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }

    const consumeQuota = req.body?.consumeQuota !== false;
    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const branchId = resolveAiJobBranchId(req, businessContext);
    const file = decodeProductImportFile(req.body);
    const sourceText = importSourceTextFromBody(req.body);
    const job = await aiJobs.createJob({
      businessId: businessContext.businessId,
      branchId,
      userId: businessContext.userId,
      jobType: 'product_import',
      title: 'Piki product import',
      sourceFileName: file.fileName,
      sourceFileBase64: file.bytes.toString('base64'),
      sourceMimeType: file.mimeType,
      sourceExtension: file.extension,
      sourceText,
      instruction: normalizeOptionalText(req.body?.instruction),
      totalSteps: 6,
    });
    res.status(202).json({ ok: true, job });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/jobs', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const statusParam = normalizeOptionalText(req.query?.status);
    const statuses = statusParam === 'active'
      ? ['queued', 'running', 'waiting_for_review']
      : statusParam
        ? statusParam.split(',').map((item) => item.trim()).filter(Boolean)
        : null;
    const jobs = await aiJobs.listJobs(businessContext.businessId, { statuses });
    res.json({ ok: true, jobs });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/jobs/:jobId', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const job = await aiJobs.getJob(req.params.jobId, businessContext.businessId);
    if (!job) throw createHttpError(404, 'AI job not found');
    res.json({ ok: true, job });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/jobs/:jobId/events', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const job = await aiJobs.getJob(req.params.jobId, businessContext.businessId);
    if (!job) throw createHttpError(404, 'AI job not found');
    const events = await aiJobs.getEvents(req.params.jobId, businessContext.businessId, {
      after: normalizeOptionalText(req.query?.after),
    });
    res.json({ ok: true, events });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/jobs/:jobId/events/stream', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const job = await aiJobs.getJob(req.params.jobId, businessContext.businessId);
    if (!job) throw createHttpError(404, 'AI job not found');
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    res.write(`event: job\ndata: ${JSON.stringify({ type: 'job', job })}\n\n`);
    const events = await aiJobs.getEvents(req.params.jobId, businessContext.businessId, {
      after: normalizeOptionalText(req.query?.after),
    });
    for (const event of events) {
      res.write(`event: event\ndata: ${JSON.stringify({ type: 'event', event })}\n\n`);
    }
    aiJobs.stream(req.params.jobId, res);
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/imports/:jobId/draft-items', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const job = await aiJobs.getJob(req.params.jobId, businessContext.businessId);
    if (!job) throw createHttpError(404, 'AI job not found');
    const items = await aiJobs.getDraftItems(req.params.jobId, businessContext.businessId);
    res.json({ ok: true, job, items });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/jobs/:jobId/cancel', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const job = await aiJobs.cancelJob(req.params.jobId, businessContext.businessId);
    if (!job) throw createHttpError(404, 'AI job not found');
    res.json({ ok: true, job });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/ai/imports/:jobId/retry', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    const job = await aiJobs.retryJob(req.params.jobId, businessContext.businessId);
    if (!job) throw createHttpError(404, 'AI job is not retryable');
    res.json({ ok: true, job });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});
app.post('/api/ai/imports/:jobId/confirm', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.products);
    const job = await aiJobs.completeJob(req.params.jobId, businessContext.businessId, {
      created: Number(req.body?.created || 0),
      updated: Number(req.body?.updated || 0),
      stockBatches: Number(req.body?.stockBatches || 0),
      skipped: Number(req.body?.skipped || 0),
    });
    if (!job) throw createHttpError(404, 'AI job not found');
    res.json({ ok: true, job });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});
app.post('/api/ai/product-file/extract', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.products);
    if (!hasBusinessFeature(businessContext, FEATURE_KEYS.products)) {
      throw createHttpError(403, 'This employee cannot manage products');
    }

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }

    const consumeQuota = req.body?.consumeQuota !== false;
    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const file = decodeProductImportFile(req.body);
    const rawText =
      importSourceTextFromBody(req.body) ||
      (await extractTextFromProductImportFile(file));
    const source = normalizeProductImportText(rawText);
    const fetch = (await import('node-fetch')).default;
    const result = await requestOpenRouterProductFileExtraction({
      fetchImpl: fetch,
      aiConfig,
      fileName: file.fileName,
      extension: file.extension,
      sourceText: source.text,
      sourceTextTruncated: source.truncated,
    });

    res.json({
      ok: true,
      data: {
        summary: result.summary,
        headers: result.headers,
        rows: result.rows,
        warnings: result.warnings,
        fileName: file.fileName,
        extension: file.extension,
        sourceTextTruncated: source.truncated,
        model: result.model,
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

app.post('/api/ai/sales-file/extract', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.sales);
    if (!hasBusinessFeature(businessContext, FEATURE_KEYS.sales)) {
      throw createHttpError(403, 'This employee cannot manage sales');
    }

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }

    const consumeQuota = req.body?.consumeQuota !== false;
    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const file = decodeProductImportFile(req.body);
    const rawText =
      importSourceTextFromBody(req.body) ||
      (await extractTextFromProductImportFile(file));
    const source = normalizeProductImportText(rawText);
    const fetch = (await import('node-fetch')).default;
    const result = await requestOpenRouterSalesFileExtraction({
      fetchImpl: fetch,
      aiConfig,
      fileName: file.fileName,
      extension: file.extension,
      sourceText: source.text,
      sourceTextTruncated: source.truncated,
    });

    res.json({
      ok: true,
      data: {
        summary: result.summary,
        headers: result.headers,
        rows: result.rows,
        warnings: result.warnings,
        fileName: file.fileName,
        extension: file.extension,
        sourceTextTruncated: source.truncated,
        model: result.model,
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

app.post('/api/ai/smart-file/extract', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensureAiFeatureAllowed(businessContext);

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }

    const consumeQuota = req.body?.consumeQuota !== false;
    const rateCheck = await checkAiRateLimit(businessContext, { consumeQuota });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const file = decodeProductImportFile(req.body);
    const rawText =
      importSourceTextFromBody(req.body) ||
      (await extractTextFromProductImportFile(file));
    const source = normalizeProductImportText(rawText);
    const fetch = (await import('node-fetch')).default;
    const result = await requestOpenRouterSmartFileExtraction({
      fetchImpl: fetch,
      aiConfig,
      fileName: file.fileName,
      extension: file.extension,
      sourceText: source.text,
      sourceTextTruncated: source.truncated,
      instruction: normalizeOptionalText(req.body?.instruction),
    });

    res.json({
      ok: true,
      data: {
        target: result.target,
        confidence: result.confidence,
        summary: result.summary,
        headers: result.headers,
        rows: result.rows,
        warnings: result.warnings,
        fileName: file.fileName,
        extension: file.extension,
        sourceTextTruncated: source.truncated,
        model: result.model,
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

app.post('/api/subscription/flutterwave/webhook', async (req, res, next) => {
  try {
    const gateway = await loadPaymentGateway('flutterwave');
    const flutterwaveConfig = resolveFlutterwaveGatewayConfig(gateway);
    if (!flutterwaveConfig.webhookHash) {
      throw createHttpError(503, 'Flutterwave webhook verification is not configured');
    }
    const providedHash = normalizeOptionalText(req.headers['verif-hash']);
    if (!safeEquals(providedHash, flutterwaveConfig.webhookHash)) {
      throw createHttpError(401, 'Invalid Flutterwave webhook signature');
    }
    const event = req.body || {};
    const data = event.data || {};
    const transactionId = normalizeOptionalText(data.id);
    const transactionReference = normalizeOptionalText(data.tx_ref);
    if (
      String(event.event || '').toLowerCase() === 'charge.completed' &&
      String(data.status || '').toLowerCase() === 'successful' &&
      transactionId &&
      transactionReference
    ) {
      const paymentResult = await query(
        `SELECT id FROM subscription_payments
         WHERE provider = 'flutterwave' AND provider_reference = $1
         LIMIT 1`,
        [transactionReference],
      );
      const paymentId = paymentResult.rows[0]?.id;
      if (paymentId) {
        await processFlutterwaveReturn({
          paymentId,
          transactionId,
          transactionReference,
        });
      }
    }
    res.status(200).json({ ok: true });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/platform/notifications', requirePlatformAdmin, async (req, res, next) => {
  try {
    await ensurePlatformNotificationSchema();
    const result = await query(`
      SELECT n.*, b.name AS target_business_name
      FROM platform_notifications n
      LEFT JOIN businesses b ON b.id = n.target_business_id
      ORDER BY n.created_at DESC
      LIMIT 200
    `);
    res.json({ ok: true, data: result.rows.map(normalizePlatformNotification) });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/platform/notifications', requirePlatformAdmin, async (req, res, next) => {
  try {
    await ensurePlatformNotificationSchema();
    const title = normalizeOptionalText(req.body?.title);
    const message = normalizeOptionalText(req.body?.message);
    const severity = normalizePlatformNotificationSeverity(req.body?.severity);
    const audience = normalizePlatformNotificationAudience(req.body?.audience);
    const targetBusinessId = audience === 'business'
      ? normalizeOptionalText(req.body?.businessId ?? req.body?.targetBusinessId)
      : null;
    const targetPlan = audience === 'plan'
      ? normalizeOptionalText(req.body?.plan ?? req.body?.targetPlan)?.toLowerCase()
      : null;
    const targetCountry = audience === 'country'
      ? normalizeCountryCode(req.body?.countryCode ?? req.body?.targetCountry)
      : null;
    const expiresAt = parseOptionalDate(req.body?.expiresAt);

    if (!title || title.length > 120) {
      throw createHttpError(400, 'Notification title is required and must be 120 characters or fewer.');
    }
    if (!message || message.length > 1000) {
      throw createHttpError(400, 'Notification message is required and must be 1000 characters or fewer.');
    }
    if (audience === 'business' && !targetBusinessId) {
      throw createHttpError(400, 'Choose a business for this notification.');
    }
    if (audience === 'plan' && !targetPlan) {
      throw createHttpError(400, 'Choose a subscription plan for this notification.');
    }
    if (audience === 'country' && !targetCountry) {
      throw createHttpError(400, 'Choose a country for this notification.');
    }
    if (expiresAt && expiresAt <= new Date()) {
      throw createHttpError(400, 'Notification expiry must be in the future.');
    }

    const result = await query(`
      INSERT INTO platform_notifications (
        id, title, message, severity, audience, target_business_id,
        target_plan, target_country, expires_at, created_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
      RETURNING *
    `, [
      crypto.randomUUID(), title, message, severity, audience,
      targetBusinessId, targetPlan, targetCountry,
      expiresAt?.toISOString() || null,
    ]);
    res.status(201).json({
      ok: true,
      data: normalizePlatformNotification(result.rows[0]),
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.delete('/api/platform/notifications/:notificationId', requirePlatformAdmin, async (req, res, next) => {
  try {
    await ensurePlatformNotificationSchema();
    const notificationId = normalizeOptionalText(req.params.notificationId);
    const result = await query(
      'DELETE FROM platform_notifications WHERE id = $1 RETURNING id',
      [notificationId],
    );
    if (!result.rows.length) {
      throw createHttpError(404, 'Notification not found');
    }
    res.json({ ok: true, data: { id: notificationId } });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/notifications', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req, {
      allowReadOnlyExpired: true,
    });
    await ensurePlatformNotificationSchema();
    const result = await query(`
      SELECT n.*
      FROM platform_notifications n
      WHERE n.is_active = true
        AND (n.expires_at IS NULL OR n.expires_at > NOW())
        AND (
          n.audience = 'all'
          OR (n.audience = 'business' AND n.target_business_id = $1)
          OR (n.audience = 'plan' AND n.target_plan = $2)
          OR (n.audience = 'country' AND n.target_country = $3)
        )
      ORDER BY n.created_at DESC
      LIMIT 50
    `, [
      businessContext.businessId,
      String(businessContext.plan || '').toLowerCase(),
      normalizeCountryCode(businessContext.countryCode),
    ]);
    res.json({ ok: true, data: result.rows.map(normalizePlatformNotification) });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/ai/cloud-settings', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.proactivePiki);
    requireManagerOrAdmin(businessContext);
    const settings = await pikiCloud.getSettings(businessContext.businessId);
    res.json({ ok: true, settings });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/ai/cloud-settings', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    ensurePlanFeatureAllowed(businessContext, FEATURE_KEYS.proactivePiki);
    requireManagerOrAdmin(businessContext);
    const settings = await pikiCloud.saveSettings(
      businessContext.businessId,
      req.body || {},
    );
    res.json({ ok: true, settings });
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
      storefrontType: req.query?.storefront || req.query?.type,
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
    const storefront = await findBusinessCatalogStorefrontBySubdomain(
      query,
      subdomain,
    );
    if (!storefront) {
      throw createHttpError(404, 'Catalog not found');
    }

    const catalog = await loadPublicCatalog(storefront.businessId, {
      currencyOverride: req.query?.currency,
      branchId: req.query?.branchId,
      storefrontType:
        storefront.storefrontType || req.query?.storefront || req.query?.type,
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
    const storefrontTypes = storefrontTypesForEntitlements(
      businessContext.entitlements,
      businessContext.sellingMode,
    );
    const primaryResult = await query(
      `SELECT primary_storefront_type
       FROM businesses
       WHERE id = $1 AND deleted_at IS NULL
       LIMIT 1`,
      [businessContext.businessId],
    );
    const primaryType = resolvePrimaryStorefrontType({
      primaryStorefrontType: primaryResult.rows[0]?.primary_storefront_type,
      availableStorefrontTypes: storefrontTypes,
      sellingMode: businessContext.sellingMode,
    });
    const requestedType = normalizeStorefrontType(req.query?.type, {
      fallback: null,
    });
    if (req.query?.type != null && !requestedType) {
      throw createHttpError(400, 'Storefront type must be retail, services, or restaurant.');
    }
    const selectedType = requestedType || primaryType;
    if (!storefrontTypes.includes(selectedType)) {
      throw createHttpError(403, 'This subscription does not include that storefront.');
    }
    const legacyBaseUrl =
      config.publicBaseUrl ||
      `https://${config.publicCatalogRootDomain}`;

    res.json({
      ok: true,
      data: {
        businessId: businessContext.businessId,
        subdomain: publicSubdomain,
        type: selectedType,
        primaryType,
        rootUrl: url,
        url: buildTypedStorefrontUrl(publicSubdomain, selectedType),
        storefronts: storefrontTypes.map((type) => ({
          ...storefrontDefinition(type),
          url: buildTypedStorefrontUrl(publicSubdomain, type),
        })),
        legacyUrl: `${legacyBaseUrl}/catalog/${encodeURIComponent(
          businessContext.businessId,
        )}/${selectedType}`,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/catalog/storefront/primary', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const primaryType = normalizeStorefrontType(
      req.body?.type || req.body?.storefrontType || req.body?.storefront_type,
      { fallback: null },
    );
    if (!primaryType) {
      throw createHttpError(400, 'Choose retail, services, or restaurant as the main website.');
    }
    const storefrontTypes = storefrontTypesForEntitlements(
      businessContext.entitlements,
      businessContext.sellingMode,
    );
    if (!storefrontTypes.includes(primaryType)) {
      throw createHttpError(403, 'This subscription does not include that storefront.');
    }
    await ensureCatalogSubdomainSchema(query);
    await query(
      `UPDATE businesses
       SET primary_storefront_type = $2,
           updated_at = NOW()
       WHERE id = $1
         AND deleted_at IS NULL`,
      [businessContext.businessId, primaryType],
    );
    await invalidateCatalogCache(businessContext.businessId);
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'storefront_primary',
      tables: ['businesses'],
    });
    res.json({ ok: true, data: { primaryType } });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/catalog/brand', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    const branchId = normalizeOptionalText(req.query?.branchId);
    const brand = await loadStorefrontBrand(businessContext.businessId, {
      branchId,
    });
    res.json({ ok: true, data: brand });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/catalog/brand', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const branchId = normalizeOptionalText(
      req.body?.branchId || req.query?.branchId,
    );
    const brand = await saveStorefrontBrand(
      businessContext.businessId,
      req.body || {},
      { branchId },
    );
    await invalidateCatalogCache(businessContext.businessId);
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'catalog_brand',
      tables: ['businesses', 'storefront_brands'],
    });
    res.json({ ok: true, data: brand });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/catalog/themes/presets', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    res.json({ ok: true, data: storefrontThemePresets() });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.get('/api/catalog/themes', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const scope = resolveStorefrontThemeScope(req.query || {}, businessContext);
    const themes = await listStorefrontThemes(
      query,
      businessContext.businessId,
      scope,
    );
    res.json({
      ok: true,
      data: {
        themes,
        presets: storefrontThemePresets(),
        branchId: scope.branchId,
        storefrontType: scope.storefrontType,
      },
    });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/catalog/themes', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const scope = resolveStorefrontThemeScope(req.body || {}, businessContext);
    const brand = await loadStorefrontBrand(businessContext.businessId, {
      branchId: scope.branchId,
    });
    const theme = await createStorefrontTheme(
      query,
      businessContext.businessId,
      req.body || {},
      {
        ...scope,
        brandColor: brand.primaryColor,
        createdBy: businessContext.userId,
      },
    );
    res.status(201).json({ ok: true, data: theme });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.put('/api/catalog/themes/:themeId', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const theme = await updateStorefrontTheme(
      query,
      businessContext.businessId,
      req.params.themeId,
      req.body || {},
    );
    if (theme.isPublished) {
      await invalidateCatalogCache(businessContext.businessId);
    }
    res.json({ ok: true, data: theme });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/catalog/themes/:themeId/duplicate', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const theme = await duplicateStorefrontTheme(
      query,
      businessContext.businessId,
      req.params.themeId,
      req.body || {},
      { createdBy: businessContext.userId },
    );
    res.status(201).json({ ok: true, data: theme });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/catalog/themes/:themeId/publish', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const theme = await withTransaction((client) =>
      publishStorefrontTheme(
        client,
        businessContext.businessId,
        req.params.themeId,
      ),
    );
    await invalidateCatalogCache(businessContext.businessId);
    notifyBusinessRealtimeChange({
      businessId: businessContext.businessId,
      sourceDeviceId: businessContext.deviceId,
      reason: 'storefront_theme',
      tables: ['storefront_themes'],
    });
    res.json({ ok: true, data: theme });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.delete('/api/catalog/themes/:themeId', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    const theme = await deleteStorefrontTheme(
      query,
      businessContext.businessId,
      req.params.themeId,
    );
    res.json({ ok: true, data: theme });
  } catch (error) {
    next(normalizeRouteError(error));
  }
});

app.post('/api/catalog/themes/:themeId/ai-customize', async (req, res, next) => {
  try {
    const businessContext = await requireBusinessContext(req);
    requireManagerOrAdmin(businessContext);
    ensureAiFeatureAllowed(businessContext);
    const instruction = limitText(req.body?.instruction || req.body?.prompt, 700);
    if (!instruction || instruction.length < 5) {
      throw createHttpError(400, 'Describe how Piki should customize this theme.');
    }
    const theme = await getStorefrontTheme(
      query,
      businessContext.businessId,
      req.params.themeId,
    );
    if (!theme) throw createHttpError(404, 'Theme was not found.');

    const aiConfig = await loadPlatformAiConfig();
    if (!aiConfig || !aiConfig.enabled || !aiConfig.api_key) {
      throw createHttpError(403, 'AI is not enabled by the platform administrator');
    }
    const rateCheck = await checkAiRateLimit(businessContext, {
      consumeQuota: req.body?.consumeQuota !== false,
    });
    if (!rateCheck.allowed) {
      throw createHttpError(
        429,
        `AI rate limit reached. Try again in ${rateCheck.resetInMinutes} minutes.`,
      );
    }

    const fetch = (await import('node-fetch')).default;
    const proposal = await requestOpenRouterStorefrontTheme({
      fetchImpl: fetch,
      aiConfig,
      instruction,
      theme,
    });
    const draft = theme.isPublished
      ? await duplicateStorefrontTheme(
          query,
          businessContext.businessId,
          theme.id,
          { name: `${theme.name} AI draft`, source: 'ai' },
          { createdBy: businessContext.userId },
        )
      : theme;
    const updated = await updateStorefrontTheme(
      query,
      businessContext.businessId,
      draft.id,
      {
        name: proposal.name || draft.name,
        preset: draft.preset,
        design: proposal.design,
        checkout: proposal.checkout,
        source: 'ai',
      },
    );
    res.json({
      ok: true,
      data: updated,
      summary: proposal.summary,
      draftCreated: theme.isPublished,
      remaining: rateCheck.remaining,
    });
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

app.get(['/catalog/:businessId', '/catalog/:businessId/:storefrontType'], async (req, res, next) => {
  try {
    const businessId = normalizeOptionalText(req.params.businessId);
    if (!businessId) {
      throw createHttpError(400, 'Business catalog link is invalid');
    }

    const catalog = await loadPublicCatalog(businessId, {
      currencyOverride: req.query?.currency,
      branchId: req.query?.branchId,
      storefrontType: req.params.storefrontType || req.query?.storefront || req.query?.type,
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

app.get(['/', '/catalog', '/retail', '/services', '/restaurant'], async (req, res, next) => {
  try {
    const subdomain = extractCatalogSubdomain(
      req.get('x-forwarded-host') || req.get('host'),
      config.publicCatalogRootDomain,
    );
    if (!subdomain) {
      next();
      return;
    }

    const storefrontLookup = await findBusinessCatalogStorefrontBySubdomain(
      query,
      subdomain,
    );
    if (!storefrontLookup) {
      throw createHttpError(404, 'Catalog not found');
    }

    const catalog = await loadPublicCatalog(storefrontLookup.businessId, {
      currencyOverride: req.query?.currency,
      branchId: req.query?.branchId,
      storefrontType:
        storefrontLookup.storefrontType ||
        (req.path === '/retail' || req.path === '/services' || req.path === '/restaurant'
          ? req.path.slice(1)
          : req.query?.storefront || req.query?.type),
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
  ensureStorefrontThemeSchema(query),
  ensureProductStorefrontSchema(),
  ensureQuotationsSchema(),
  ensurePlatformNotificationSchema(),
  pikiCloud.ensureSchema(),
  aiJobs.ensureSchema(),
])
  .then(async () => {
    await aiJobs.enqueueQueuedJobs();
    return startPikiProactiveWorker({
      query,
      withTransaction,
      intervalMs: Number(process.env.PIKI_PROACTIVE_INTERVAL_MS || 15 * 60 * 1000),
      initialDelayMs: Number(process.env.PIKI_PROACTIVE_INITIAL_DELAY_MS || 10 * 1000),
      onBusinessRefreshed: ({ businessId }) =>
        pikiCloud.dispatchBusinessAlerts({ businessId }),
    });
  })
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

function buildCorsOptions(req) {
  const allowedOrigins = new Set(
    (config.allowedOrigins || []).map((origin) =>
      String(origin || '').trim().replace(/\/+$/, ''),
    ),
  );
  return {
    origin(origin, callback, req) {
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
      if (
        isCatalogStorefrontOrigin(
          normalizedOrigin,
          config.publicCatalogRootDomain,
          { allowHttp: config.nodeEnv !== 'production' },
        )
      ) {
        callback(null, true);
        return;
      }
      // Allow same-origin requests (when the storefront is served by this backend).
      if (req) {
        const host = req.get("host");
        const proto = req.get("x-forwarded-proto") || req.protocol || "http";
        const serverOrigin = `${proto}://${host}`.replace(/\/+$/, "");
        if (serverOrigin === normalizedOrigin) {
          callback(null, true);
          return;
        }
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

function ensureRoleAtLeast(businessContext, minimumRole) {
  const rank = { CASHIER: 1, MANAGER: 2, ADMIN: 3 };
  const current = rank[normalizeBusinessRole(businessContext?.role)] || 0;
  const required = rank[normalizeBusinessRole(minimumRole)] || rank.MANAGER;
  if (current < required) {
    throw createHttpError(
      403,
      `${normalizeBusinessRole(minimumRole)} access is required`,
    );
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
  await ensureStorefrontBranchBrandSchema(target);
}

async function ensureStorefrontBranchBrandSchema(target = query) {
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS storefront_brands (
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text NOT NULL DEFAULT 'main_branch',
      name text,
      logo_url text,
      cover_url text,
      cover_urls_json jsonb,
      primary_color text,
      tagline text,
      description text,
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      PRIMARY KEY (business_id, branch_id)
    )`,
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
  await runDbQuery(
    target,
    'ALTER TABLE products ADD COLUMN IF NOT EXISTS is_restaurant_menu integer NOT NULL DEFAULT 0',
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

async function loadStorefrontBrand(businessId, options = {}) {
  const branchId = normalizeOptionalText(options.branchId);
  const branchName = normalizeOptionalText(options.branchName);
  await ensureStorefrontBrandSchema(query);

  if (branchId && branchId !== 'main_branch') {
    const branchResult = await query(
      `SELECT
         name,
         logo_url AS catalog_logo_url,
         cover_url AS catalog_cover_url,
         cover_urls_json AS catalog_cover_urls_json,
         primary_color AS catalog_primary_color,
         tagline AS catalog_tagline,
         description AS catalog_description,
         updated_at
       FROM storefront_brands
       WHERE business_id = $1 AND branch_id = $2
       LIMIT 1`,
      [businessId, branchId],
    );
    if (branchResult.rows.length) {
      const row = branchResult.rows[0];
      return normalizeStorefrontBrandRow({
        ...row,
        id: businessId,
        name:
          normalizeOptionalText(row.name) ||
          branchName ||
          (await loadBusinessName(query, businessId)),
      });
    }
  }

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

async function loadBusinessName(target, businessId) {
  const result = await target(
    `SELECT name FROM businesses WHERE id = $1 AND deleted_at IS NULL LIMIT 1`,
    [businessId],
  );
  return normalizeOptionalText(result.rows[0]?.name) || 'Store';
}

async function saveStorefrontBrand(businessId, input, options = {}) {
  const branchId = normalizeOptionalText(options.branchId);
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
  const displayName = normalizeOptionalText(input.name ?? input.businessName);

  if (branchId && branchId !== 'main_branch') {
    const result = await query(
      `INSERT INTO storefront_brands (
         business_id, branch_id, name, logo_url, cover_url,
         cover_urls_json, primary_color, tagline, description, updated_at
       )
       VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, NOW())
       ON CONFLICT (business_id, branch_id) DO UPDATE SET
         name = EXCLUDED.name,
         logo_url = EXCLUDED.logo_url,
         cover_url = EXCLUDED.cover_url,
         cover_urls_json = EXCLUDED.cover_urls_json,
         primary_color = EXCLUDED.primary_color,
         tagline = EXCLUDED.tagline,
         description = EXCLUDED.description,
         updated_at = NOW()
       RETURNING
         name,
         logo_url AS catalog_logo_url,
         cover_url AS catalog_cover_url,
         cover_urls_json AS catalog_cover_urls_json,
         primary_color AS catalog_primary_color,
         tagline AS catalog_tagline,
         description AS catalog_description,
         updated_at`,
      [
        businessId,
        branchId,
        displayName,
        logoUrl,
        primaryCoverUrl,
        JSON.stringify(coverUrls),
        primaryColor,
        tagline,
        description,
      ],
    );
    const row = result.rows[0];
    return normalizeStorefrontBrandRow({
      ...row,
      id: businessId,
      name: normalizeOptionalText(row.name) || displayName || 'Store',
    });
  }

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

async function ensurePlatformNotificationSchema(target = query) {
  await target(`
    CREATE TABLE IF NOT EXISTS platform_notifications (
      id text PRIMARY KEY,
      title text NOT NULL,
      message text NOT NULL,
      severity text NOT NULL DEFAULT 'info',
      audience text NOT NULL DEFAULT 'all',
      target_business_id text REFERENCES businesses(id) ON DELETE CASCADE,
      target_plan text,
      target_country text,
      is_active boolean NOT NULL DEFAULT true,
      expires_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT NOW()
    )
  `);
  await target(`
    CREATE INDEX IF NOT EXISTS idx_platform_notifications_delivery
    ON platform_notifications(is_active, audience, created_at DESC)
  `);
}

function normalizePlatformNotificationSeverity(value) {
  const severity = String(value || '').trim().toLowerCase();
  return ['info', 'success', 'warning', 'critical'].includes(severity)
    ? severity
    : 'info';
}

function normalizePlatformNotificationAudience(value) {
  const audience = String(value || '').trim().toLowerCase();
  return ['all', 'business', 'plan', 'country'].includes(audience)
    ? audience
    : 'all';
}

function normalizePlatformNotification(row) {
  return {
    id: row.id,
    title: row.title,
    message: row.message,
    severity: normalizePlatformNotificationSeverity(row.severity),
    audience: normalizePlatformNotificationAudience(row.audience),
    targetBusinessId: row.target_business_id || null,
    targetBusinessName: row.target_business_name || null,
    targetPlan: row.target_plan || null,
    targetCountry: row.target_country || null,
    isActive: row.is_active !== false,
    expiresAt: toIsoString(row.expires_at),
    createdAt: toIsoString(row.created_at),
  };
}

function normalizeStorefrontType(value, { fallback = 'retail' } = {}) {
  const normalized = normalizeOptionalText(value)?.toLowerCase();
  switch (normalized) {
    case 'retail':
    case 'store':
    case 'shop':
    case 'products':
    case 'product':
      return 'retail';
    case 'services':
    case 'service':
    case 'booking':
      return 'services';
    case 'restaurant':
    case 'menu':
    case 'food':
      return 'restaurant';
    default:
      return fallback && STOREFRONT_TYPES[fallback] ? fallback : null;
  }
}

function defaultStorefrontTypeForSellingMode(sellingMode) {
  switch (normalizeSellingMode(sellingMode)) {
    case 'services':
      return 'services';
    case 'restaurant':
      return 'restaurant';
    default:
      return 'retail';
  }
}

function resolveStorefrontThemeScope(input, businessContext) {
  const raw = input && typeof input === 'object' ? input : {};
  const branchId =
    normalizeOptionalText(raw.branchId || raw.branch_id) || 'main_branch';
  resolveDataScope(businessContext, branchId);
  const requestedRaw =
    raw.storefrontType || raw.storefront_type || raw.type || raw.module;
  const requestedType = normalizeStorefrontType(requestedRaw, {
    fallback: null,
  });
  if (requestedRaw != null && !requestedType) {
    throw createHttpError(
      400,
      'Storefront type must be retail, services, or restaurant.',
    );
  }
  const storefrontType =
    requestedType || defaultStorefrontTypeForSellingMode(businessContext.sellingMode);
  const available = storefrontTypesForEntitlements(
    businessContext.entitlements,
    businessContext.sellingMode,
  );
  if (!available.includes(storefrontType)) {
    throw createHttpError(403, 'This subscription does not include that storefront.');
  }
  return { branchId, storefrontType };
}

function storefrontTypesForEntitlements(entitlements, sellingMode) {
  const features = new Set(entitlements?.features || []);
  const mode = normalizeSellingMode(sellingMode);
  const types = [];
  if (mode !== 'restaurant' && features.has(FEATURE_KEYS.products)) {
    types.push('retail');
  }
  if (features.has(FEATURE_KEYS.services)) {
    types.push('services');
  }
  if (
    features.has(FEATURE_KEYS.products) &&
    features.has(FEATURE_KEYS.restaurantMode)
  ) {
    types.push('restaurant');
  }

  // Older businesses may not have a subscription record yet. Preserve the
  // existing public catalog while still selecting the right first experience.
  if (types.length === 0) {
    types.push(defaultStorefrontTypeForSellingMode(sellingMode));
  }
  return types;
}

function resolvePrimaryStorefrontType({
  primaryStorefrontType,
  availableStorefrontTypes,
  sellingMode,
}) {
  const configured = normalizeStorefrontType(primaryStorefrontType, {
    fallback: null,
  });
  if (configured && availableStorefrontTypes.includes(configured)) {
    return configured;
  }
  const modeDefault = defaultStorefrontTypeForSellingMode(sellingMode);
  return availableStorefrontTypes.includes(modeDefault)
    ? modeDefault
    : availableStorefrontTypes[0];
}

function storefrontDefinition(type) {
  const normalized = normalizeStorefrontType(type);
  return STOREFRONT_TYPES[normalized];
}

function buildTypedStorefrontUrl(businessSubdomain, type) {
  return buildCatalogStorefrontUrl(
    config.publicCatalogRootDomain,
    buildCatalogStorefrontSubdomain(businessSubdomain, type),
  );
}

function storefrontItemMatchesType(item, storefrontType) {
  const itemType = normalizePublicCatalogItemType(item?.itemType || item?.type);
  return storefrontType === 'services'
    ? itemType === 'service'
    : itemType === 'product';
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
    case 'supplier_payments':
    case 'purchase_orders':
    case 'purchase_order_items':
    case 'suppliers':
    case 'stock_batches':
      return FEATURE_KEYS.purchases;
    case 'services':
    case 'service_orders':
    case 'service_fields':
      return FEATURE_KEYS.services;
    case 'products':
    case 'product_variants':
    case 'product_variant_colors':
      return FEATURE_KEYS.products;
    case 'product_serials':
      return FEATURE_KEYS.serialTracking;
    case 'stocktake_sessions':
    case 'stocktake_items':
      return FEATURE_KEYS.stocktake;
    case 'sms_campaigns':
      return FEATURE_KEYS.smsCampaigns;
    case 'exchange_rates':
      return FEATURE_KEYS.multiCurrency;
    case 'wastage_logs':
      return FEATURE_KEYS.wastage;
    case 'restaurant_tables':
    case 'table_orders':
      return FEATURE_KEYS.restaurantMode;
    case 'employee_attendance':
      return FEATURE_KEYS.attendance;
    case 'customer_groups':
    case 'customer_group_members':
      return FEATURE_KEYS.customerSegments;
    case 'delivery_zones':
    case 'deliveries':
      return FEATURE_KEYS.delivery;
    case 'sales':
    case 'sale_items':
      return FEATURE_KEYS.sales;
    case 'shifts':
      return FEATURE_KEYS.shifts;
    case 'loyalty_rules':
    case 'loyalty_ledger':
      return FEATURE_KEYS.loyalty;
    case 'gift_cards':
    case 'gift_card_transactions':
      return FEATURE_KEYS.giftCards;
    case 'custom_roles':
      return FEATURE_KEYS.customRoles;
    case 'promotions':
    case 'promotion_rules':
      return FEATURE_KEYS.promotions;
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

  for (const mode of ['products', 'services', 'restaurant', 'combo']) {
    const validation = validateSellingModeEntitlement(entitlements, mode);
    if (validation.ok) {
      return validation.mode;
    }
  }

  throw createHttpError(
    400,
    'This plan is not available for product, service, or restaurant selling yet.',
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
    publicKey: secretConfig.publicKey || '',
    secretKey: secretConfig.secretKey || config.flutterwaveSecretKey,
    encryptionKey: secretConfig.encryptionKey || '',
    webhookHash: secretConfig.webhookHash || '',
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
  { currencyOverride, branchId: requestedBranchId, storefrontType } = {},
) {
  await ensureCatalogSubdomainSchema(query);
  await ensureStorefrontBrandSchema(query);
  await ensureStorefrontThemeSchema(query);
  await ensureProductStorefrontSchema(query);
  const businessResult = await query(
    `
    SELECT b.id, b.name, b.country_code, b.currency, b.selling_mode,
           b.primary_storefront_type, b.updated_at,
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

  const subscriptionResult = await query(
    'SELECT plan FROM subscriptions WHERE business_id = $1 LIMIT 1',
    [businessId],
  );
  const entitlements = applySellingModeToEntitlements(
    await loadEntitlementsForPlan(subscriptionResult.rows[0]?.plan),
    business.selling_mode,
  );
  const availableStorefrontTypes = storefrontTypesForEntitlements(
    entitlements,
    business.selling_mode,
  );
  const requestedType = normalizeStorefrontType(storefrontType, {
    fallback: null,
  });
  if (storefrontType != null && !requestedType) {
    throw createHttpError(404, 'Storefront not found');
  }
  const primaryStorefrontType = resolvePrimaryStorefrontType({
    primaryStorefrontType: business.primary_storefront_type,
    availableStorefrontTypes,
    sellingMode: business.selling_mode,
  });
  const selectedStorefrontType = requestedType || primaryStorefrontType;
  if (!availableStorefrontTypes.includes(selectedStorefrontType)) {
    throw createHttpError(404, 'Storefront not found');
  }
  const storefront = storefrontDefinition(selectedStorefrontType);
  const cacheKey = await buildCatalogCacheKey(businessId, {
    currencyOverride,
    branchId: requestedBranchId,
    storefrontType: selectedStorefrontType,
  });
  const cached = await cacheGetJson(cacheKey);
  if (cached) {
    return cached;
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

  const products = deduplicatePublicCatalogProducts(
    productsResult.rows.map((row) => normalizePublicCatalogProduct(row)),
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
  const catalogItems = [...products, ...serviceItems].filter((item) =>
    storefrontItemMatchesType(item, selectedStorefrontType),
  );
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

  const branchBrand = await loadStorefrontBrand(business.id, {
    branchId: selectedBranch.id,
    branchName: selectedBranch.name,
  });

  const publishedTheme = await loadPublishedStorefrontTheme(
    query,
    business.id,
    {
      branchId: selectedBranch.id,
      storefrontType: selectedStorefrontType,
      brandColor: branchBrand.primaryColor,
    },
  );
  const activePaymentProviders = [];
  try {
    const mpesaStatus = await loadPosMpesaConfig({
      businessId: business.id,
      countryCode: business.country_code,
    });
    if (mpesaStatus.active) activePaymentProviders.push('mpesa');
  } catch (_) {
    // Manual checkout remains available if gateway readiness cannot be loaded.
  }
  const publicTheme = {
    ...publishedTheme,
    checkout: checkoutForActiveGateways(
      publishedTheme.checkout,
      activePaymentProviders,
    ),
  };

  const catalog = {
    business: {
      id: business.id,
      name: branchBrand.businessName || business.name,
      countryCode: business.country_code || 'GLOBAL',
      whatsappNumber: normalizeOptionalText(business.whatsapp_number),
      brand: branchBrand,
      branches,
      selectedBranch,
    },
    storefront,
    theme: publicTheme,
    checkout: publicTheme.checkout,
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
  { currencyOverride, branchId, storefrontType } = {},
) {
  const version = (await cacheGetText(catalogCacheVersionKey(businessId))) || '0';
  return [
    'catalog',
    normalizeCacheKeyPart(businessId),
    normalizeCacheKeyPart(version),
    normalizeCacheKeyPart(branchId || 'default'),
    normalizeCacheKeyPart(currencyOverride || 'default'),
    normalizeCacheKeyPart(storefrontType || 'default'),
    CATALOG_CACHE_CODE_VERSION,
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
  const requestedStorefrontType = normalizeStorefrontType(
    payload.storefrontType || payload.storefront_type,
    { fallback: null },
  );
  if (
    (payload.storefrontType != null || payload.storefront_type != null) &&
    !requestedStorefrontType
  ) {
    throw createHttpError(400, 'Storefront type is invalid');
  }
  const note = normalizeOptionalText(payload.note);
  const rawItems = Array.isArray(payload.items)
    ? payload.items
    : Array.isArray(payload.lines)
      ? payload.lines
      : [];

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
    if (
      requestedStorefrontType &&
      !storefrontItemMatchesType(item, requestedStorefrontType)
    ) {
      throw createHttpError(
        400,
        requestedStorefrontType === 'services'
          ? 'A service booking can only include services.'
          : 'This storefront can only include menu or retail items.',
      );
    }
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
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending', $9, $10, $11, $12, $13)
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
        requestedStorefrontType
          ? `storefront_${requestedStorefrontType}`
          : 'catalog_link',
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
    paymentMethod: row.payment_method || 'manual',
    paymentStatus: row.payment_status || 'pending',
    deliveryStatus: row.delivery_status || null,
    trackingCode: row.tracking_code || null,
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
    itemType: 'product',
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

function deduplicatePublicCatalogProducts(products) {
  const seen = new Set();
  return products.filter((item) => {
    const key = String(item.name || '').trim().toLowerCase();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
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
    itemType: 'service',
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
  const storefront = storefrontDefinition(catalog.storefront?.type);
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
    storefront.description;
  const title = `${escapeHtml(businessName)} - ${escapeHtml(storefront.title)}`;

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
  if (/<div id="__next">/i.test(html)) {
    return html;
  }
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
  const storefront = storefrontDefinition(catalog.storefront?.type);
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
  const tagline = normalizeOptionalText(brand.tagline) || storefront.title;
  const description =
    normalizeOptionalText(brand.description) ||
    storefront.description;
  const products = Array.isArray(catalog.products) ? catalog.products : [];
  const visibleItems = products.slice(0, 12);
  const storeInitial = businessName.trim().charAt(0).toUpperCase() || 'P';
  const itemNoun = storefront.type === 'services' ? 'service' : 'item';
  const itemCountLabel = products.length === 1
    ? `1 ${itemNoun} available`
    : `${products.length} ${itemNoun}s available`;
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
          <article style="min-width:0;border:1px solid #e5e7eb;border-radius:18px;background:#fff;overflow:hidden;box-shadow:0 10px 24px -18px rgba(15,23,42,.38)">
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
          <h2 style="margin:0 0 8px;color:#111827;font-size:22px">No ${escapeHtml(itemNoun)}s published yet</h2>
          <p style="margin:0">This ${escapeHtml(storefront.label.toLowerCase())} is online. Items will appear once the business publishes them.</p>
        </div>`;

  return `<div id="root">
    <main data-static-storefront="true" style="box-sizing:border-box;width:100%;max-width:100%;overflow-x:hidden;background:#f6f7f9;color:#111827;font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
      <style>
        @keyframes storefrontHeroFade { 0%, ${slideVisibleEnd}% { opacity: 1; transform: scale(1.08); } ${slideFadeEnd}%, 100% { opacity: 0; transform: scale(1.02); } }
        [data-static-storefront] * { box-sizing: border-box; }
        [data-static-storefront] .static-store-hero { padding: clamp(24px, 3vw, 34px) 20px clamp(30px, 4vw, 42px); }
        [data-static-storefront] .static-store-wrap { width: min(1120px, 100%); margin: 0 auto; }
        [data-static-storefront] .static-store-grid-section { width: min(1120px, 100%); max-width: 100%; margin: -18px auto 0; padding: 0 20px 28px; }
        [data-static-storefront] .static-store-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(210px, 100%), 252px)); justify-content: center; gap: 18px; min-width: 0; }
        @media (max-width: 640px) {
          [data-static-storefront] .static-store-hero { padding: 24px 14px 34px; }
          [data-static-storefront] .static-store-grid-section { padding: 0 12px 24px; }
          [data-static-storefront] .static-store-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
        }
        @media (max-width: 360px) {
          [data-static-storefront] .static-store-grid { grid-template-columns: 1fr; }
        }
      </style>
      <section class="static-store-hero" style="box-sizing:border-box;position:relative;overflow:hidden;max-width:100%;background:linear-gradient(135deg,#111827 0%,#1f2937 62%,${escapeHtml(primaryColor)} 150%);color:#fff">
        ${fallbackSlides}
        <div style="position:absolute;inset:0;background:linear-gradient(135deg,rgba(17,24,39,.9),rgba(31,41,55,.72) 55%,rgba(0,0,0,.42));"></div>
        <div class="static-store-wrap" style="position:relative;display:grid;gap:18px">
          <div style="display:flex;align-items:center;gap:16px">
            <div style="width:56px;height:56px;border-radius:18px;background:#fff;display:grid;place-items:center;color:${escapeHtml(primaryColor)};font-weight:900;font-size:22px;overflow:hidden">
              ${
                logoUrl
                  ? `<img src="${escapeHtml(logoUrl)}" alt="${escapeHtml(businessName)} logo" style="width:100%;height:100%;object-fit:cover">`
                  : escapeHtml(storeInitial)
              }
            </div>
            <div>
              <p style="margin:0 0 4px;color:rgba(255,255,255,.72);font-size:13px;font-weight:800;text-transform:uppercase;letter-spacing:.06em">${escapeHtml(storefront.label)}</p>
              <h1 style="margin:0;font-size:clamp(28px,4.2vw,48px);line-height:1.02">${escapeHtml(businessName)}</h1>
            </div>
          </div>
          <div style="max-width:720px">
            <p style="margin:0 0 8px;font-size:clamp(17px,2.2vw,24px);font-weight:800">${escapeHtml(tagline)}</p>
            <p style="margin:0;color:rgba(255,255,255,.78);font-size:16px;line-height:1.55">${escapeHtml(description)}</p>
          </div>
          <div style="display:flex;flex-wrap:wrap;gap:10px">
            <span style="border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.1);border-radius:999px;padding:8px 12px;font-size:13px;font-weight:800">${escapeHtml(itemCountLabel)}</span>
            ${
              branchName
                ? `<span style="border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.1);border-radius:999px;padding:8px 12px;font-size:13px;font-weight:800">${escapeHtml(branchName)}</span>`
                : ''
            }
          </div>
        </div>
      </section>
      <section class="static-store-grid-section">
        ${
          visibleItems.length
            ? `<div class="static-store-grid">${productCards}</div>`
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
        const res = await fetch(\`/api/public/orders/\${encodeURIComponent(no)}/track?phone=\${encodeURIComponent(ph)}\`);
        const data = await res.json();
        if (!res.ok) throw new Error(data.message || 'Not found');
        resDiv.className = 'alert alert-success';
        resDiv.innerHTML = \`Order status: <strong>\${safeHtml(data.order.status)}</strong><br>Last updated: \${new Date(data.order.updated_at).toLocaleString()}\`;
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

let customerPortalAuthSchemaReady = false;

async function ensureCustomerPortalAuthSchema(target = query) {
  const canUseCache = target === query;
  if (canUseCache && customerPortalAuthSchemaReady) return;
  await runDbQuery(
    target,
    `CREATE TABLE IF NOT EXISTS customer_portal_email_otps (
       id text PRIMARY KEY,
       business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
       customer_id text NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
       email text NOT NULL,
       code_hash text NOT NULL,
       attempts integer NOT NULL DEFAULT 0,
       expires_at timestamptz NOT NULL,
       sent_at timestamptz NOT NULL DEFAULT NOW(),
       consumed_at timestamptz,
       created_at timestamptz NOT NULL DEFAULT NOW(),
       updated_at timestamptz NOT NULL DEFAULT NOW()
     )`,
  );
  await runDbQuery(
    target,
    `CREATE INDEX IF NOT EXISTS idx_customer_portal_email_otps_lookup
     ON customer_portal_email_otps (business_id, customer_id, email, created_at DESC)`,
  );
  if (canUseCache) customerPortalAuthSchemaReady = true;
}

function normalizeCustomerPortalEmail(value) {
  const email = String(value || '').trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

function customerPortalOtpHash({ businessId, customerId, email, code }) {
  return crypto
    .createHmac('sha256', config.emailOtpSecret || config.platformJwtSecret)
    .update([businessId, customerId, email, code].join(':'))
    .digest('hex');
}

async function requestCustomerPortalEmailCode({ businessId, email }) {
  await ensureCustomerPortalAuthSchema();
  const customerResult = await query(
    `SELECT id FROM customers
     WHERE business_id = $1 AND LOWER(TRIM(COALESCE(email, ''))) = $2
       AND deleted_at IS NULL
     LIMIT 1`,
    [businessId, email],
  );
  const customer = customerResult.rows[0];
  // Do not reveal whether the address has a portal account.
  if (!customer) return { sent: true };

  const latest = await query(
    `SELECT sent_at FROM customer_portal_email_otps
     WHERE business_id = $1 AND customer_id = $2 AND email = $3
       AND consumed_at IS NULL
     ORDER BY sent_at DESC LIMIT 1`,
    [businessId, customer.id, email],
  );
  const now = new Date();
  const cooldownMs = Math.max(1, Number(config.emailOtpCooldownSeconds || 60)) * 1000;
  const latestSentAt = latest.rows[0]?.sent_at ? new Date(latest.rows[0].sent_at) : null;
  if (latestSentAt && now.getTime() - latestSentAt.getTime() < cooldownMs) {
    return {
      sent: false,
      retryAfterSeconds: Math.max(1, Math.ceil((cooldownMs - (now.getTime() - latestSentAt.getTime())) / 1000)),
    };
  }

  const code = crypto.randomInt(0, 1000000).toString().padStart(6, '0');
  const expiresAt = new Date(
    now.getTime() + Math.max(1, Number(config.emailOtpTtlMinutes || 10)) * 60 * 1000,
  );
  const otpId = crypto.randomUUID();
  await query(
    `INSERT INTO customer_portal_email_otps (
       id, business_id, customer_id, email, code_hash, attempts,
       expires_at, sent_at, created_at, updated_at
     ) VALUES ($1, $2, $3, $4, $5, 0, $6, $7, $7, $7)`,
    [
      otpId,
      businessId,
      customer.id,
      email,
      customerPortalOtpHash({ businessId, customerId: customer.id, email, code }),
      expiresAt.toISOString(),
      now.toISOString(),
    ],
  );
  try {
    await sendOtpEmail({ email, code, expiresAt });
  } catch (error) {
    await query(
      `UPDATE customer_portal_email_otps
       SET consumed_at = NOW(), updated_at = NOW()
       WHERE id = $1`,
      [otpId],
    );
    throw error;
  }
  return { sent: true, expiresAt: expiresAt.toISOString() };
}

async function verifyCustomerPortalEmailCode({ businessId, email, code }) {
  await ensureCustomerPortalAuthSchema();
  const customerResult = await query(
    `SELECT id, name, balance FROM customers
     WHERE business_id = $1 AND LOWER(TRIM(COALESCE(email, ''))) = $2
       AND deleted_at IS NULL
     LIMIT 1`,
    [businessId, email],
  );
  const customer = customerResult.rows[0];
  if (!customer) throw createHttpError(401, 'The verification code is invalid or expired.');
  const otpResult = await query(
    `SELECT * FROM customer_portal_email_otps
     WHERE business_id = $1 AND customer_id = $2 AND email = $3
       AND consumed_at IS NULL
     ORDER BY created_at DESC LIMIT 1`,
    [businessId, customer.id, email],
  );
  const otp = otpResult.rows[0];
  const invalid = () => createHttpError(401, 'The verification code is invalid or expired.');
  if (!otp || new Date(otp.expires_at).getTime() <= Date.now()) throw invalid();
  if (Number(otp.attempts || 0) >= Math.max(1, Number(config.emailOtpMaxAttempts || 5))) {
    throw createHttpError(429, 'Too many incorrect attempts. Request a new code.');
  }
  const expected = customerPortalOtpHash({ businessId, customerId: customer.id, email, code });
  if (!safeEquals(expected, otp.code_hash)) {
    await query(
      `UPDATE customer_portal_email_otps SET attempts = attempts + 1, updated_at = NOW() WHERE id = $1`,
      [otp.id],
    );
    throw invalid();
  }
  await query(
    `UPDATE customer_portal_email_otps SET consumed_at = NOW(), updated_at = NOW() WHERE id = $1`,
    [otp.id],
  );
  return customer;
}

function requireCustomerPortalSession(req) {
  const token = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) throw createHttpError(401, 'Customer portal sign-in is required.');
  const portal = jwt.verify(token, config.platformJwtSecret);
  if (portal?.type !== 'customer_portal' || !portal.businessId || !portal.customerId) {
    throw createHttpError(403, 'Customer portal token required.');
  }
  return portal;
}

function customerPortalPaymentResponse(payment) {
  const portalMetadata = payment?.metadata?.customerPortal || {};
  return {
    id: payment.id,
    amount: Number(payment.amountMinor || 0) / 100,
    currency: payment.currency,
    status: payment.status,
    receiptNumber: payment.receiptNumber || null,
    appliedAmount: Number(portalMetadata.appliedAmount || 0),
    unappliedAmount: Number(portalMetadata.unappliedAmount || 0),
    createdAt: payment.createdAt,
    completedAt: payment.completedAt,
  };
}

async function applyCustomerPortalMpesaPayment(paymentResult) {
  if (paymentResult?.status !== 'paid' || !paymentResult?.businessId || !paymentResult?.paymentId) return;
  const payment = await loadPosPayment({
    businessId: paymentResult.businessId,
    paymentId: paymentResult.paymentId,
  });
  const customerId = normalizeOptionalText(payment?.metadata?.customerPortal?.customerId);
  if (!payment || !customerId) return;

  await ensureSyncStockEffectSchema();
  await withTransaction(async (client) => {
    const customerResult = await client.query(
      `SELECT id FROM customers WHERE business_id = $1 AND id = $2 AND deleted_at IS NULL FOR UPDATE`,
      [payment.businessId, customerId],
    );
    if (!customerResult.rows[0]) return;
    const sales = await client.query(
      `SELECT id, balance_due FROM sales
       WHERE business_id = $1 AND customer_id = $2 AND deleted_at IS NULL
         AND refund_for_sale_id IS NULL AND balance_due > 0.009
       ORDER BY CASE WHEN due_date IS NULL THEN 1 ELSE 0 END, due_date ASC, created_at ASC
       FOR UPDATE`,
      [payment.businessId, customerId],
    );
    let remaining = Math.max(0, Number(payment.amountMinor || 0) / 100);
    const now = new Date().toISOString();
    for (const sale of sales.rows) {
      if (remaining <= 0.009) break;
      const applied = Math.min(remaining, Math.max(0, Number(sale.balance_due || 0)));
      if (applied <= 0) continue;
      const paymentId = `portal_${payment.id}_${sale.id}`;
      await client.query(
        `INSERT INTO credit_payments (
           id, business_id, payment_group_id, customer_id, sale_id, user_id,
           amount, note, received_at, created_at, updated_at, sync_status
         ) VALUES ($1, $2, $3, $4, $5, 'customer_portal', $6, $7, $8, $8, $8, 'synced')
         ON CONFLICT (id) DO NOTHING RETURNING id`,
        [
          paymentId,
          payment.businessId,
          payment.id,
          customerId,
          sale.id,
          applied,
          `Customer portal M-Pesa${payment.receiptNumber ? ` ${payment.receiptNumber}` : ''}`,
          now,
        ],
      );
      remaining = Number((remaining - applied).toFixed(2));
      await rebuildSaleCreditBalance(client, payment.businessId, sale.id);
    }
    const appliedResult = await client.query(
      `SELECT COALESCE(SUM(amount), 0) AS amount
       FROM credit_payments
       WHERE business_id = $1 AND payment_group_id = $2 AND deleted_at IS NULL`,
      [payment.businessId, payment.id],
    );
    const appliedAmount = Number(appliedResult.rows[0]?.amount || 0);
    await rebuildCustomerBalance(client, payment.businessId, customerId);
    await client.query(
      `UPDATE pos_payment_requests
       SET metadata_json = metadata_json || $2::jsonb, updated_at = NOW()
       WHERE id = $1`,
      [
        payment.id,
        JSON.stringify({
          customerPortal: {
            ...(payment.metadata?.customerPortal || {}),
            appliedAmount,
            unappliedAmount: Math.max(0, Number(payment.amountMinor || 0) / 100 - appliedAmount),
            creditedAt: now,
          },
        }),
      ],
    );
  });
}

async function applyPublicCatalogMpesaPayment(paymentResult) {
  if (!paymentResult?.businessId || !paymentResult?.paymentId) return;
  const payment = await loadPosPayment({
    businessId: paymentResult.businessId,
    paymentId: paymentResult.paymentId,
  });
  const orderId = normalizeOptionalText(payment?.metadata?.publicCatalogOrder?.orderId);
  if (!payment || !orderId) return;
  const status = paymentResult.status === 'paid' ? 'paid' : 'failed';
  await query(
    `UPDATE public_catalog_orders
     SET payment_status = $1,
         payment_reference = COALESCE($2, payment_reference),
         updated_at = NOW()
     WHERE id = $3 AND business_id = $4 AND payment_method = 'mpesa'`,
    [status, payment.receiptNumber || payment.id, orderId, payment.businessId],
  );
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

function normalizeReportDateRange(queryParams = {}) {
  const now = new Date();
  const firstOfMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
    .toISOString()
    .slice(0, 10);
  return {
    from: queryParams.from ? normalizeReportDate(queryParams.from) : firstOfMonth,
    to: queryParams.to ? normalizeReportDate(queryParams.to) : normalizeReportDate(),
  };
}

function addReportBranchFilter(clauses, params, alias, scope) {
  if (scope.branchIds == null) {
    return;
  }
  clauses.push(
    `COALESCE(${alias}.branch_id, 'main_branch') = ANY($${params.length + 1}::text[])`,
  );
  params.push(scope.branchIds);
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

  await cleanupOldReleases(platformDir, filename);

  return {
    platform,
    version,
    fileName: filename,
    bytes,
    url: `${appReleaseUrlPrefix}/${platform}/${filename}`,
  };
}

async function cleanupOldReleases(platformDir, keepFileName) {
  try {
    const entries = await fsp.readdir(platformDir);
    const releaseFiles = entries.filter(
      (name) => !name.startsWith('.') && name !== keepFileName,
    );
    for (const name of releaseFiles) {
      const filePath = path.join(platformDir, name);
      try {
        const stat = await fsp.stat(filePath);
        if (stat.isFile()) {
          await fsp.rm(filePath, { force: true });
        }
      } catch (_) {
        // best-effort cleanup
      }
    }
  } catch (_) {
    // directory may not exist yet
  }
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
    const embeddedSignupEligible =
      publicConfig.embeddedSignupEligible === true ||
      ['true', 'yes', '1', 'on'].includes(
        String(publicConfig.embeddedSignupEligible || '').trim().toLowerCase(),
      );
    const hasFallbackSender =
      publicConfig.phoneNumberId && secretConfig.accessToken;
    if (!hasEmbeddedSignup && !hasFallbackSender) {
      errors.push(
        'Embedded Signup App ID, Config ID, and App Secret, or fallback Phone Number ID and access token',
      );
    }
    if (hasEmbeddedSignup && !embeddedSignupEligible && !hasFallbackSender) {
      errors.push(
        'Meta BSP/Tech Provider approval for Embedded Signup, or fallback Phone Number ID and access token',
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
            throw new Error(platform.setupBlockedReason || "WhatsApp setup is not enabled yet. Contact Piki support.");
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
  product_variant_colors: 'products',
  purchase_invoices: 'purchases',
  supplier_payments: 'purchases',
  purchase_orders: 'purchases',
  purchase_order_items: 'purchases',
  stock_batches: 'products',
  stock_transfers: 'transfers',
  stocktake_sessions: 'stocktake',
  stocktake_items: 'stocktake',
  sms_campaigns: 'sms_campaigns',
  exchange_rates: 'multi_currency',
  wastage_logs: 'wastage',
  restaurant_tables: 'restaurant_mode',
  table_orders: 'restaurant_mode',
  employee_attendance: 'attendance',
  customer_groups: 'customer_segments',
  customer_group_members: 'customer_segments',
  delivery_zones: 'delivery',
  deliveries: 'delivery',
  customer_invoices: 'sales',
  customer_invoice_items: 'sales',
  expenses: 'profit_loss',
  services: 'services',
  service_fields: 'services',
  service_orders: 'services',
  service_field_values: 'services',
  loyalty_rules: 'loyalty',
  loyalty_ledger: 'loyalty',
  gift_cards: 'gift_cards',
  gift_card_transactions: 'gift_cards',
  promotions: 'promotions',
  promotion_rules: 'promotions',
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
