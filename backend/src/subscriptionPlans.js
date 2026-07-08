const crypto = require('crypto');

const { config } = require('./config');
const { query } = require('./db');

const FEATURE_KEYS = Object.freeze({
  pos: 'pos',
  products: 'products',
  categories: 'categories',
  purchases: 'purchases',
  sales: 'sales',
  dashboard: 'dashboard',
  kopesha: 'kopesha',
  profitLoss: 'profit_loss',
  reports: 'reports',
  settings: 'settings',
  shifts: 'shifts',
  services: 'services',
  agent: 'agent',
  stockList: 'stock_list',
  transfers: 'transfers',
  branches: 'branches',
  auditLogs: 'audit_logs',
  proactivePiki: 'proactive_piki',
  loyalty: 'loyalty',
});

const SELLING_MODES = Object.freeze({
  products: 'products',
  services: 'services',
  combo: 'combo',
});

const DEFAULT_SELLING_MODES = Object.freeze(Object.values(SELLING_MODES));
const ALLOWED_SUBSCRIPTION_PROVIDERS = new Set([
  'google_play',
  'paypal',
  'flutterwave',
]);

const BASE_FEATURES = [
  FEATURE_KEYS.pos,
  FEATURE_KEYS.products,
  FEATURE_KEYS.sales,
  FEATURE_KEYS.dashboard,
  FEATURE_KEYS.settings,
  FEATURE_KEYS.shifts,
  FEATURE_KEYS.agent,
];

const TRIAL_FEATURES = [
  ...BASE_FEATURES,
  FEATURE_KEYS.services,
];

const STARTER_FEATURES = [
  ...BASE_FEATURES,
  FEATURE_KEYS.categories,
  FEATURE_KEYS.stockList,
  FEATURE_KEYS.reports,
];

const GROWTH_FEATURES = [
  ...STARTER_FEATURES,
  FEATURE_KEYS.purchases,
  FEATURE_KEYS.transfers,
  FEATURE_KEYS.branches,
  FEATURE_KEYS.services,
  FEATURE_KEYS.profitLoss,
  FEATURE_KEYS.loyalty,
];

const ALL_FEATURES = [
  ...GROWTH_FEATURES,
  FEATURE_KEYS.kopesha,
  FEATURE_KEYS.auditLogs,
  FEATURE_KEYS.proactivePiki,
];

const DEFAULT_PLANS = [
  {
    code: 'trial',
    name: 'Trial',
    description: 'Starter trial for a new shop.',
    features: TRIAL_FEATURES,
    maxBranches: 1,
    maxEmployees: 2,
    maxAiAgents: 1,
    aiRateHourly: 20,
    aiRateWeekly: 200,
    aiRateMonthly: 500,
    sortOrder: 10,
    sellingModes: [...DEFAULT_SELLING_MODES],
  },
  {
    code: 'starter',
    name: 'Starter',
    description: 'One-branch retail operations.',
    features: STARTER_FEATURES,
    maxBranches: 1,
    maxEmployees: 3,
    maxAiAgents: 1,
    aiRateHourly: 60,
    aiRateWeekly: 1000,
    aiRateMonthly: 3000,
    sortOrder: 20,
    sellingModes: [SELLING_MODES.products],
  },
  {
    code: 'growth',
    name: 'Growth',
    description: 'Multi-branch operations with transfers and services.',
    features: GROWTH_FEATURES,
    maxBranches: 3,
    maxEmployees: 10,
    maxAiAgents: 3,
    aiRateHourly: 200,
    aiRateWeekly: 5000,
    aiRateMonthly: 15000,
    sortOrder: 30,
    sellingModes: [...DEFAULT_SELLING_MODES],
  },
  {
    code: 'pro',
    name: 'Pro',
    description: 'Full POS suite with advanced controls and Piki.',
    features: ALL_FEATURES,
    maxBranches: 10,
    maxEmployees: 30,
    maxAiAgents: 10,
    aiRateHourly: 600,
    aiRateWeekly: 20000,
    aiRateMonthly: 60000,
    sortOrder: 40,
    sellingModes: [...DEFAULT_SELLING_MODES],
  },
  {
    code: 'enterprise',
    name: 'Enterprise',
    description: 'Custom limits and pricing for large teams.',
    isActive: false,
    features: ALL_FEATURES,
    maxBranches: 999999,
    maxEmployees: 999999,
    maxAiAgents: 999999,
    aiRateHourly: 999999,
    aiRateWeekly: 9999999,
    aiRateMonthly: 99999999,
    sortOrder: 50,
    sellingModes: [...DEFAULT_SELLING_MODES],
  },
];

const DEFAULT_PRICE_AMOUNTS = [
  ['trial', 0, 0],
  ['starter', 150000, 1500],
  ['growth', 350000, 3500],
  ['pro', 750000, 7500],
  ['enterprise', 0, 0],
];

const DEFAULT_PRICES = DEFAULT_PRICE_AMOUNTS.flatMap(
  ([planCode, kesAmount, usdAmount]) => {
    const productId = planCode === 'trial' ? null : `piki_${planCode}_monthly`;
    return [
      [planCode, 'KE', 'KES', kesAmount, 'monthly', 'google_play', productId],
      [planCode, 'GLOBAL', 'USD', usdAmount, 'monthly', 'google_play', productId],
      [planCode, 'KE', 'KES', kesAmount, 'monthly', 'flutterwave', null],
      [planCode, 'GLOBAL', 'USD', usdAmount, 'monthly', 'flutterwave', null],
      [planCode, 'GLOBAL', 'USD', usdAmount, 'monthly', 'paypal', null],
    ];
  },
);

const SECRET_MASK_PREFIX = '********';

let schemaReady = false;

async function ensureSubscriptionSchema(target = query) {
  const canUseCache = target === query;
  if (canUseCache && schemaReady) {
    return;
  }

  await runQuery(
    target,
    `
    ALTER TABLE businesses
      ADD COLUMN IF NOT EXISTS country_code text NOT NULL DEFAULT 'GLOBAL'
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE businesses
      ADD COLUMN IF NOT EXISTS selling_mode text NOT NULL DEFAULT 'combo'
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE businesses
      ADD COLUMN IF NOT EXISTS currency text
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS subscription_plans (
      code text PRIMARY KEY,
      name text NOT NULL,
      description text,
      is_active boolean NOT NULL DEFAULT true,
      features_json jsonb NOT NULL DEFAULT '[]'::jsonb,
      allowed_selling_modes_json jsonb NOT NULL DEFAULT '["products","services","combo"]'::jsonb,
      max_branches integer NOT NULL DEFAULT 1,
      max_employees integer NOT NULL DEFAULT 1,
      max_ai_agents integer NOT NULL DEFAULT 0,
      ai_rate_hourly integer NOT NULL DEFAULT 0,
      ai_rate_weekly integer NOT NULL DEFAULT 0,
      ai_rate_monthly integer NOT NULL DEFAULT 0,
      sort_order integer NOT NULL DEFAULT 0,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE subscription_plans
      ADD COLUMN IF NOT EXISTS allowed_selling_modes_json jsonb NOT NULL DEFAULT '["products","services","combo"]'::jsonb
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS platform_subscription_settings (
      id integer PRIMARY KEY DEFAULT 1,
      trial_days integer NOT NULL DEFAULT 30,
      grace_days integer NOT NULL DEFAULT 5,
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      CONSTRAINT platform_subscription_settings_single_row CHECK (id = 1),
      CONSTRAINT platform_subscription_settings_trial_days CHECK (trial_days BETWEEN 1 AND 365),
      CONSTRAINT platform_subscription_settings_grace_days CHECK (grace_days BETWEEN 0 AND 30)
    )
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE platform_subscription_settings
      ADD COLUMN IF NOT EXISTS grace_days integer NOT NULL DEFAULT 5
    `,
  );

  await runQuery(
    target,
    `
    INSERT INTO platform_subscription_settings (id, trial_days, grace_days)
    VALUES (1, $1, $2)
    ON CONFLICT (id) DO NOTHING
    `,
    [configuredTrialDays(), configuredGraceDays()],
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS platform_payment_gateways (
      provider text PRIMARY KEY,
      display_name text NOT NULL,
      is_active boolean NOT NULL DEFAULT false,
      countries_json jsonb NOT NULL DEFAULT '[]'::jsonb,
      public_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      secret_config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await seedDefaultPaymentGateways(target);

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS subscription_plan_prices (
      id text PRIMARY KEY,
      plan_code text NOT NULL REFERENCES subscription_plans(code) ON DELETE CASCADE,
      country_code text NOT NULL DEFAULT 'GLOBAL',
      currency text NOT NULL DEFAULT 'USD',
      amount_minor integer NOT NULL DEFAULT 0,
      billing_period text NOT NULL DEFAULT 'monthly',
      provider text NOT NULL DEFAULT 'google_play',
      store_product_id text,
      is_active boolean NOT NULL DEFAULT true,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_plan_prices_unique
      ON subscription_plan_prices(plan_code, country_code, provider, billing_period)
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE subscription_plan_prices
      ADD COLUMN IF NOT EXISTS store_product_id text
    `,
  );

  await migrateMpesaSubscriptionPrices(target);

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS subscription_payments (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      plan_code text NOT NULL REFERENCES subscription_plans(code),
      price_id text REFERENCES subscription_plan_prices(id),
      provider text NOT NULL,
      country_code text NOT NULL,
      currency text NOT NULL,
      amount_minor integer NOT NULL,
      billing_period text NOT NULL DEFAULT 'monthly',
      selling_mode text NOT NULL DEFAULT 'products',
      status text NOT NULL DEFAULT 'pending',
      phone_number text,
      external_reference text,
      checkout_request_id text,
      provider_reference text,
      google_pay_token_json jsonb,
      metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      completed_at timestamptz
    )
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE subscription_payments
      ADD COLUMN IF NOT EXISTS selling_mode text NOT NULL DEFAULT 'products'
    `,
  );

  await runQuery(
    target,
    `
    ALTER TABLE subscription_payments
      ADD COLUMN IF NOT EXISTS provider_reference text
    `,
  );

  await runQuery(
    target,
    `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_subscription_payments_provider_reference
      ON subscription_payments(provider, provider_reference)
      WHERE provider_reference IS NOT NULL
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_subscription_payments_business
      ON subscription_payments(business_id, created_at DESC)
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS ai_rate_limit_counters (
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      period text NOT NULL,
      request_count integer NOT NULL DEFAULT 0,
      window_start timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      PRIMARY KEY (business_id, period)
    )
    `,
  );

  for (const plan of DEFAULT_PLANS) {
    await runQuery(
      target,
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
        sort_order
      )
      VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, $7, $8, $9, $10, $11, $12, $13)
      ON CONFLICT (code) DO NOTHING
      `,
      [
        plan.code,
        plan.name,
        plan.description,
        plan.isActive !== false,
        JSON.stringify(plan.features),
        JSON.stringify(plan.sellingModes || DEFAULT_SELLING_MODES),
        plan.maxBranches,
        plan.maxEmployees,
        plan.maxAiAgents,
        plan.aiRateHourly,
        plan.aiRateWeekly,
        plan.aiRateMonthly,
        plan.sortOrder,
      ],
    );
  }

  await runQuery(
    target,
    `
    UPDATE subscription_plans
    SET features_json = $3::jsonb,
        allowed_selling_modes_json = $4::jsonb,
        updated_at = NOW()
    WHERE code = 'trial'
      AND features_json = $1::jsonb
      AND allowed_selling_modes_json = $2::jsonb
    `,
    [
      JSON.stringify(BASE_FEATURES),
      JSON.stringify([SELLING_MODES.products]),
      JSON.stringify(TRIAL_FEATURES),
      JSON.stringify(DEFAULT_SELLING_MODES),
    ],
  );

  // Backfill the loyalty feature into paid plans that were seeded before
  // loyalty existed in the canonical feature lists. Without this, devices on
  // those plans receive a license token whose entitlements omit 'loyalty', so
  // the Loyalty screen stays hidden even for admins on paid plans.
  for (const [planCode, canonicalFeatures] of [
    ['growth', GROWTH_FEATURES],
    ['pro', ALL_FEATURES],
    ['enterprise', ALL_FEATURES],
  ]) {
    await runQuery(
      target,
      `
      UPDATE subscription_plans
      SET features_json = COALESCE(
            features_json || (
              SELECT jsonb_agg(f)
              FROM jsonb_array_elements_text($2::jsonb) AS f
              WHERE NOT (features_json ? f)
            ),
            features_json
          ),
          updated_at = NOW()
      WHERE code = $1
        AND EXISTS (
          SELECT 1
          FROM jsonb_array_elements_text($2::jsonb) AS f
          WHERE NOT (features_json ? f)
        )
      `,
      [planCode, JSON.stringify(canonicalFeatures)],
    );
  }

  for (const price of DEFAULT_PRICES) {
    const [
      planCode,
      countryCode,
      currency,
      amountMinor,
      billingPeriod,
      provider,
      storeProductId,
    ] = price;
    await runQuery(
      target,
      `
      INSERT INTO subscription_plan_prices (
        id,
        plan_code,
        country_code,
        currency,
        amount_minor,
        billing_period,
        provider,
        store_product_id
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ON CONFLICT (plan_code, country_code, provider, billing_period) DO NOTHING
      `,
      [
        `price_${planCode}_${countryCode.toLowerCase()}_${provider}_${billingPeriod}`,
        planCode,
        countryCode,
        currency,
        amountMinor,
        billingPeriod,
        provider,
        storeProductId,
      ],
    );
  }

  if (canUseCache) {
    schemaReady = true;
  }
}

async function loadPlatformSubscriptionSettings(target = query) {
  await ensureSubscriptionSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT trial_days, grace_days, updated_at
    FROM platform_subscription_settings
    WHERE id = 1
    LIMIT 1
    `,
  );
  const row = result.rows[0];
  return {
    trialDays: normalizeTrialDays(row?.trial_days, configuredTrialDays()),
    graceDays: normalizeGraceDays(row?.grace_days, configuredGraceDays()),
    updatedAt: toIsoString(row?.updated_at),
  };
}

async function savePlatformSubscriptionSettings(input = {}, target = query) {
  await ensureSubscriptionSchema(target);
  const current = await loadPlatformSubscriptionSettings(target);
  const trialDays = normalizeTrialDays(
    input.trialDays ?? input.trial_days,
    current.trialDays,
  );
  const graceDays = normalizeGraceDays(
    input.graceDays ?? input.grace_days,
    current.graceDays,
  );
  const result = await runQuery(
    target,
    `
    INSERT INTO platform_subscription_settings (id, trial_days, grace_days, updated_at)
    VALUES (1, $1, $2, NOW())
    ON CONFLICT (id) DO UPDATE
    SET trial_days = EXCLUDED.trial_days,
        grace_days = EXCLUDED.grace_days,
        updated_at = NOW()
    RETURNING trial_days, grace_days, updated_at
    `,
    [trialDays, graceDays],
  );
  const row = result.rows[0];
  return {
    trialDays: normalizeTrialDays(row.trial_days),
    graceDays: normalizeGraceDays(row.grace_days),
    updatedAt: toIsoString(row.updated_at),
  };
}

async function listPlans({ includeInactive = false } = {}, target = query) {
  await ensureSubscriptionSchema(target);
  const planResult = await runQuery(
    target,
    `
    SELECT *
    FROM subscription_plans
    ${includeInactive ? '' : 'WHERE is_active = true'}
    ORDER BY sort_order ASC, name ASC
    `,
  );
  const priceResult = await runQuery(
    target,
    `
    SELECT *
    FROM subscription_plan_prices
    ORDER BY plan_code ASC, country_code ASC, provider ASC, billing_period ASC
    `,
  );

  const pricesByPlan = new Map();
  for (const row of priceResult.rows) {
    const items = pricesByPlan.get(row.plan_code) || [];
    items.push(normalizePriceRow(row));
    pricesByPlan.set(row.plan_code, items);
  }

  return planResult.rows.map((row) => ({
    ...normalizePlanRow(row),
    prices: pricesByPlan.get(row.code) || [],
  }));
}

async function loadEntitlementsForPlan(planCode, target = query) {
  await ensureSubscriptionSchema(target);
  const normalizedCode = normalizeCode(planCode) || 'trial';
  let result = await runQuery(
    target,
    'SELECT * FROM subscription_plans WHERE code = $1 LIMIT 1',
    [normalizedCode],
  );

  if (!result.rows.length && normalizedCode !== 'trial') {
    result = await runQuery(
      target,
      "SELECT * FROM subscription_plans WHERE code = 'trial' LIMIT 1",
    );
  }

  const row = result.rows[0];
  return row ? normalizeEntitlements(row) : defaultTrialEntitlements();
}

async function resolvePlanPrice({
  planCode,
  countryCode,
  provider,
  billingPeriod = 'monthly',
} = {}, target = query) {
  await ensureSubscriptionSchema(target);
  const cleanPlanCode = normalizeCode(planCode) || 'trial';
  const cleanProvider = normalizeText(provider) ? normalizeProvider(provider) : null;
  if (cleanProvider && !isSubscriptionPaymentProviderAllowed(cleanProvider)) {
    return null;
  }
  const cleanCountry = normalizeCountryCode(countryCode);
  const cleanBillingPeriod = normalizeBillingPeriod(billingPeriod);

  const result = await runQuery(
    target,
    `
    SELECT p.*
    FROM subscription_plan_prices p
    JOIN subscription_plans sp ON sp.code = p.plan_code AND sp.is_active = true
    JOIN platform_payment_gateways g ON g.provider = p.provider
    WHERE p.plan_code = $1
      AND ($2::text IS NULL OR p.provider = $2)
      AND p.billing_period = $3
      AND p.is_active = true
      AND (
        p.amount_minor = 0
        OR (
          g.is_active = true
          AND g.countries_json ? p.country_code
        )
      )
      AND p.country_code IN ($4, 'GLOBAL')
    ORDER BY CASE WHEN p.country_code = $4 THEN 0 ELSE 1 END
    LIMIT 1
    `,
    [cleanPlanCode, cleanProvider, cleanBillingPeriod, cleanCountry],
  );

  return result.rows[0] ? normalizePriceRow(result.rows[0]) : null;
}

async function listPublicPlans({ countryCode } = {}, target = query) {
  const hasCountry = normalizeText(countryCode) !== null;
  const cleanCountry = hasCountry ? normalizeCountryCode(countryCode) : null;
  const plans = await listPlans({ includeInactive: false }, target);

  return plans.map((plan) => {
    const prices = plan.prices.filter(
      (price) => {
        return (
          price.isActive &&
          isSubscriptionPaymentProviderAllowed(price.provider) &&
          isPriceVisibleInPublicCatalog(price) &&
          (!cleanCountry ||
            price.countryCode === cleanCountry ||
            price.countryCode === 'GLOBAL')
        );
      },
    );
    const exactPrice = cleanCountry
      ? prices.find((price) => price.countryCode === cleanCountry)
      : prices[0];
    const fallbackPrice = cleanCountry
      ? prices.find((price) => price.countryCode === 'GLOBAL')
      : null;
    return {
      ...plan,
      prices,
      price: exactPrice || fallbackPrice || null,
      sellingModes: availableSellingModesForEntitlements(plan.entitlements),
      entitlements: plan.entitlements,
    };
  });
}

async function listPublicMarkets(target = query) {
  await ensureSubscriptionSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT
      country_code,
      currency,
      provider,
      display_name,
      public_config_json,
      gateway_active,
      payment_active
    FROM (
      SELECT DISTINCT
        p.country_code,
        p.currency,
        p.provider,
        g.display_name,
        g.public_config_json,
        g.is_active AS gateway_active,
        (
          g.is_active = true
          AND g.countries_json ? p.country_code
        ) AS payment_active,
        CASE
          WHEN p.country_code = 'KE' THEN 0
          WHEN p.country_code = 'GLOBAL' THEN 2
          ELSE 1
        END AS sort_rank
      FROM subscription_plan_prices p
      JOIN subscription_plans sp ON sp.code = p.plan_code
      JOIN platform_payment_gateways g ON g.provider = p.provider
      WHERE p.is_active = true
        AND sp.is_active = true
    ) markets
    ORDER BY sort_rank ASC, country_code ASC, provider ASC
    `,
  );

  return result.rows
    .map((row) => ({
      countryCode: normalizeCountryCode(row.country_code),
      label: countryLabel(row.country_code),
      currency: normalizeCurrency(row.currency),
      provider: normalizeProvider(row.provider),
      providerLabel: row.display_name || providerLabel(row.provider),
      paymentActive: Boolean(row.payment_active),
      publicConfig: parseJsonValue(row.public_config_json, {}),
    }))
    .filter((market) => isSubscriptionPaymentProviderAllowed(market.provider));
}

async function listPaymentGateways({ includeSecrets = false } = {}, target = query) {
  await ensureSubscriptionSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM platform_payment_gateways
    WHERE provider NOT IN ('mpesa', 'google_pay')
    ORDER BY CASE provider
      WHEN 'google_play' THEN 0
      WHEN 'flutterwave' THEN 1
      WHEN 'paypal' THEN 2
      ELSE 3
    END, provider ASC
    `,
  );
  return result.rows.map((row) =>
    normalizePaymentGatewayRow(row, { includeSecrets }),
  );
}

async function loadPaymentGateway(
  provider,
  target = query,
  { includeSecrets = true } = {},
) {
  await ensureSubscriptionSchema(target);
  const cleanProvider = normalizeProvider(provider);
  const result = await runQuery(
    target,
    'SELECT * FROM platform_payment_gateways WHERE provider = $1 LIMIT 1',
    [cleanProvider],
  );
  return result.rows[0]
    ? normalizePaymentGatewayRow(result.rows[0], { includeSecrets })
    : null;
}

async function savePaymentGateway(provider, input = {}, target = query) {
  await ensureSubscriptionSchema(target);
  const cleanProvider = normalizeProvider(provider || input.provider);
  if (!isSubscriptionPaymentProviderAllowed(cleanProvider)) {
    throw createError(
      400,
      'This provider is not available for subscriptions.',
    );
  }
  const existing = await loadPaymentGateway(cleanProvider, target, {
    includeSecrets: true,
  });
  const normalized = normalizePaymentGatewayInput(input, {
    ...(existing || {}),
    provider: cleanProvider,
  });
  validatePaymentGatewayConfiguration(normalized);

  const result = await runQuery(
    target,
    `
    INSERT INTO platform_payment_gateways (
      provider,
      display_name,
      is_active,
      countries_json,
      public_config_json,
      secret_config_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6::jsonb, NOW(), NOW())
    ON CONFLICT (provider) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        is_active = EXCLUDED.is_active,
        countries_json = EXCLUDED.countries_json,
        public_config_json = EXCLUDED.public_config_json,
        secret_config_json = EXCLUDED.secret_config_json,
        updated_at = NOW()
    RETURNING *
    `,
    [
      cleanProvider,
      normalized.displayName,
      normalized.isActive,
      JSON.stringify(normalized.countries),
      JSON.stringify(normalized.publicConfig),
      JSON.stringify(normalized.secretConfig),
    ],
  );

  return normalizePaymentGatewayRow(result.rows[0], { includeSecrets: false });
}

async function seedDefaultPaymentGateways(target = query) {
  for (const gateway of defaultPaymentGateways()) {
    await runQuery(
      target,
      `
      INSERT INTO platform_payment_gateways (
        provider,
        display_name,
        is_active,
        countries_json,
        public_config_json,
        secret_config_json
      )
      VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6::jsonb)
      ON CONFLICT (provider) DO NOTHING
      `,
      [
        gateway.provider,
        gateway.displayName,
        gateway.isActive,
        JSON.stringify(gateway.countries),
        JSON.stringify(gateway.publicConfig),
        JSON.stringify(gateway.secretConfig),
      ],
    );
  }
}

function defaultPaymentGateways() {
  return [
    {
      provider: 'google_play',
      displayName: 'Google Play',
      isActive: Boolean(
        config.googlePlayPackageName &&
          config.googlePlayServiceAccountEmail &&
          config.googlePlayServiceAccountPrivateKey,
      ),
      countries: ['KE', 'GLOBAL'],
      publicConfig: removeEmptyValues({ packageName: config.googlePlayPackageName }),
      secretConfig: removeEmptyValues({
        serviceAccountEmail: config.googlePlayServiceAccountEmail,
        serviceAccountPrivateKey: config.googlePlayServiceAccountPrivateKey,
      }),
    },
    {
      provider: 'flutterwave',
      displayName: 'Flutterwave',
      isActive: Boolean(config.flutterwaveSecretKey && config.publicBaseUrl),
      countries: ['KE', 'GLOBAL'],
      publicConfig: removeEmptyValues({ baseUrl: config.flutterwaveBaseUrl }),
      secretConfig: removeEmptyValues({ secretKey: config.flutterwaveSecretKey }),
    },
    {
      provider: 'paypal',
      displayName: 'PayPal',
      isActive: Boolean(
        config.paypalClientId && config.paypalClientSecret && config.publicBaseUrl,
      ),
      countries: ['GLOBAL'],
      publicConfig: removeEmptyValues({ baseUrl: config.paypalBaseUrl }),
      secretConfig: removeEmptyValues({
        clientId: config.paypalClientId,
        clientSecret: config.paypalClientSecret,
      }),
    },
  ];
}

function normalizePaymentGatewayInput(input, existing = {}) {
  const raw = input && typeof input === 'object' ? input : {};
  const publicConfig = normalizeConfigObject(
    raw.publicConfig ?? raw.public_config ?? {},
    existing.publicConfig || {},
    { secret: false },
  );
  const secretConfig = normalizeConfigObject(
    raw.secretConfig ?? raw.secret_config ?? {},
    existing.secretConfig || {},
    { secret: true },
  );
  return {
    provider: normalizeProvider(raw.provider ?? existing.provider),
    displayName:
      normalizeText(raw.displayName ?? raw.display_name) ||
      existing.displayName ||
      providerLabel(existing.provider),
    isActive:
      raw.isActive == null && raw.is_active == null
        ? existing.isActive ?? false
        : Boolean(raw.isActive ?? raw.is_active),
    countries: normalizeCountryList(raw.countries ?? existing.countries ?? []),
    publicConfig,
    secretConfig,
  };
}

function normalizePaymentGatewayRow(row, { includeSecrets = false } = {}) {
  const secretConfig = parseJsonValue(row.secret_config_json, {});
  return {
    provider: normalizeProvider(row.provider),
    displayName: row.display_name || providerLabel(row.provider),
    isActive: Boolean(row.is_active),
    countries: normalizeCountryList(parseJsonValue(row.countries_json, [])),
    publicConfig: parseJsonValue(row.public_config_json, {}),
    secretConfig: includeSecrets ? secretConfig : maskConfigObject(secretConfig),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeConfigObject(input, existing = {}, { secret = false } = {}) {
  const raw = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
  const normalized = { ...existing };
  for (const [key, value] of Object.entries(raw)) {
    const cleanKey = normalizeText(key);
    if (!cleanKey) {
      continue;
    }
    const text = value == null ? '' : String(value).trim();
    if (secret && (!text || text.startsWith(SECRET_MASK_PREFIX))) {
      continue;
    }
    if (!secret && !text) {
      delete normalized[cleanKey];
      continue;
    }
    normalized[cleanKey] = text;
  }
  return normalized;
}

function maskConfigObject(configObject) {
  const masked = {};
  for (const [key, value] of Object.entries(configObject || {})) {
    const text = value == null ? '' : String(value);
    masked[key] = text ? `${SECRET_MASK_PREFIX}${text.slice(-4)}` : '';
  }
  return masked;
}

function removeEmptyValues(value) {
  const result = {};
  for (const [key, item] of Object.entries(value || {})) {
    const text = item == null ? '' : String(item).trim();
    if (text) {
      result[key] = text;
    }
  }
  return result;
}

function normalizeCountryList(value) {
  const source = Array.isArray(value)
    ? value
    : String(value || '')
        .split(',')
        .map((item) => item.trim());
  const countries = [];
  for (const item of source) {
    const country = normalizeCountryCode(item);
    if (country && !countries.includes(country)) {
      countries.push(country);
    }
  }
  return countries;
}

function countryLabel(countryCode) {
  const cleanCountry = normalizeCountryCode(countryCode);
  if (cleanCountry === 'KE') return 'Kenya';
  if (cleanCountry === 'GLOBAL') return 'Other Countries';
  return cleanCountry;
}

function providerLabel(provider) {
  switch (normalizeProvider(provider)) {
    case 'mpesa':
      return 'M-Pesa';
    case 'google_pay':
      return 'Google Pay';
    case 'google_play':
      return 'Google Play';
    case 'paypal':
      return 'PayPal';
    case 'flutterwave':
      return 'Flutterwave';
    default:
      return normalizeProvider(provider).replace(/_/g, ' ');
  }
}

function parseJsonValue(value, fallback) {
  if (value == null) {
    return fallback;
  }
  if (typeof value === 'object') {
    return value;
  }
  try {
    return JSON.parse(String(value));
  } catch (_) {
    return fallback;
  }
}

function findPublicPriceForCountry(prices, cleanCountry) {
  const exactPrice = prices.find(
    (price) =>
      price.isActive &&
      price.countryCode === cleanCountry,
  );
  return (
    exactPrice ||
    prices.find(
      (price) => price.isActive && price.countryCode === 'GLOBAL',
    ) ||
    null
  );
}

function isPriceAvailableForPublicCatalog(price, gateway) {
  if (!price?.isActive) {
    return false;
  }
  if (Number(price.amountMinor || 0) === 0) {
    return true;
  }
  return Boolean(
    gateway?.isActive &&
      (gateway.countries || []).includes(price.countryCode),
  );
}

function isPriceVisibleInPublicCatalog(price) {
  return Boolean(price?.isActive);
}

function validatePaymentGatewayConfiguration(gateway) {
  if (!gateway?.isActive) {
    return;
  }

  if (gateway.provider === 'google_play') {
    const publicConfig = gateway.publicConfig || {};
    const secretConfig = gateway.secretConfig || {};
    const missing = [];
    if (!publicConfig.packageName) missing.push('Android package name');
    if (!secretConfig.serviceAccountEmail) missing.push('service account email');
    if (!secretConfig.serviceAccountPrivateKey) missing.push('service account private key');
    if (missing.length > 0) {
      throw createError(
        400,
        `Complete Google Play settings before enabling: ${missing.join(', ')}.`,
      );
    }
  }

  if (gateway.provider === 'paypal') {
    const publicConfig = gateway.publicConfig || {};
    const secretConfig = gateway.secretConfig || {};
    if (!isHttpsUrl(publicConfig.baseUrl)) {
      throw createError(400, 'PayPal base URL must be a valid HTTPS URL.');
    }
    if (!secretConfig.clientId || !secretConfig.clientSecret) {
      throw createError(400, 'PayPal client ID and client secret are required.');
    }
  }

  if (gateway.provider === 'flutterwave') {
    const publicConfig = gateway.publicConfig || {};
    const secretConfig = gateway.secretConfig || {};
    if (!isHttpsUrl(publicConfig.baseUrl)) {
      throw createError(400, 'Flutterwave base URL must be a valid HTTPS URL.');
    }
    if (!secretConfig.secretKey) {
      throw createError(400, 'Flutterwave secret key is required.');
    }
  }
}

function isHttpsUrl(value) {
  try {
    return new URL(String(value || '')).protocol === 'https:';
  } catch (_) {
    return false;
  }
}

async function migrateMpesaSubscriptionPrices(target = query) {
  for (const provider of ['google_play', 'flutterwave']) {
    await runQuery(
      target,
      `
      INSERT INTO subscription_plan_prices (
        id, plan_code, country_code, currency, amount_minor, billing_period,
        provider, store_product_id, is_active, created_at, updated_at
      )
      SELECT
        id || $1,
        plan_code,
        country_code,
        currency,
        amount_minor,
        billing_period,
        $2,
        CASE WHEN $2 = 'google_play' AND plan_code <> 'trial'
          THEN 'piki_' || plan_code || '_' || billing_period
          ELSE NULL
        END,
        is_active,
        created_at,
        NOW()
      FROM subscription_plan_prices
      WHERE provider IN ('mpesa', 'google_pay')
      ON CONFLICT (plan_code, country_code, provider, billing_period) DO NOTHING
      `,
      [`-${provider}`, provider],
    );
  }

  await runQuery(
    target,
    `
    INSERT INTO subscription_plan_prices (
      id, plan_code, country_code, currency, amount_minor, billing_period,
      provider, is_active, created_at, updated_at
    )
    SELECT
      id || '-paypal', plan_code, country_code, currency, amount_minor,
      billing_period, 'paypal', is_active, created_at, NOW()
    FROM subscription_plan_prices
    WHERE provider IN ('mpesa', 'google_pay')
      AND country_code = 'GLOBAL'
    ON CONFLICT (plan_code, country_code, provider, billing_period) DO NOTHING
    `,
  );

  await runQuery(
    target,
    `
    UPDATE subscription_plan_prices
    SET is_active = false,
        updated_at = NOW()
    WHERE provider IN ('mpesa', 'google_pay')
      AND is_active = true
    `,
  );

  await runQuery(
    target,
    `
    UPDATE platform_payment_gateways
    SET is_active = false,
        updated_at = NOW()
    WHERE provider IN ('mpesa', 'google_pay')
      AND is_active = true
    `,
  );

  await runQuery(
    target,
    `
    UPDATE subscription_plan_prices
    SET store_product_id = 'piki_' || plan_code || '_' || billing_period,
        updated_at = NOW()
    WHERE provider = 'google_play'
      AND plan_code <> 'trial'
      AND (store_product_id IS NULL OR store_product_id = '')
    `,
  );
}

function isSubscriptionPaymentProviderAllowed(provider) {
  return ALLOWED_SUBSCRIPTION_PROVIDERS.has(normalizeProvider(provider));
}

function isPlausibleMpesaPasskey(value) {
  const passkey = normalizeText(value);
  return (
    passkey.length >= 32 &&
    passkey.length <= 128 &&
    !/\s/.test(passkey) &&
    !passkey.includes('-----BEGIN')
  );
}

function renewalBaseDate(expiresAt, referenceDate = new Date()) {
  const now = parseDate(referenceDate) || new Date();
  const expiry = parseDate(expiresAt);
  return expiry && expiry > now ? expiry : now;
}

function normalizePlanInput(input, existing = {}) {
  const raw = input && typeof input === 'object' ? input : {};
  const code = normalizeCode(raw.code ?? existing.code);
  const features = normalizeFeatureList(raw.features ?? existing.features);
  return {
    code,
    name: normalizeText(raw.name) || existing.name || code,
    description:
      raw.description == null
        ? existing.description || ''
        : String(raw.description).trim(),
    isActive:
      raw.isActive == null && raw.is_active == null
        ? existing.isActive ?? true
        : Boolean(raw.isActive ?? raw.is_active),
    features,
    sellingModes: normalizeSellingModes(
      raw.sellingModes ??
        raw.allowedSellingModes ??
        raw.allowed_selling_modes,
      existing.sellingModes ?? DEFAULT_SELLING_MODES,
    ),
    maxBranches: normalizeLimit(raw.maxBranches ?? raw.max_branches, existing.maxBranches ?? 1),
    maxEmployees: normalizeLimit(
      raw.maxEmployees ?? raw.max_employees,
      existing.maxEmployees ?? 1,
    ),
    maxAiAgents: normalizeLimit(
      raw.maxAiAgents ?? raw.max_ai_agents,
      existing.maxAiAgents ?? 0,
    ),
    aiRateHourly: normalizeLimit(
      raw.aiRateHourly ?? raw.ai_rate_hourly,
      existing.aiRateHourly ?? 0,
    ),
    aiRateWeekly: normalizeLimit(
      raw.aiRateWeekly ?? raw.ai_rate_weekly,
      existing.aiRateWeekly ?? 0,
    ),
    aiRateMonthly: normalizeLimit(
      raw.aiRateMonthly ?? raw.ai_rate_monthly,
      existing.aiRateMonthly ?? 0,
    ),
    sortOrder: normalizeLimit(raw.sortOrder ?? raw.sort_order, existing.sortOrder ?? 0),
    prices: normalizePrices(raw.prices ?? existing.prices ?? []),
  };
}

function normalizePriceInput(input, planCode) {
  const raw = input && typeof input === 'object' ? input : {};
  return {
    id: normalizeText(raw.id) || crypto.randomUUID(),
    planCode: normalizeCode(raw.planCode ?? raw.plan_code ?? planCode),
    countryCode: normalizeCountryCode(raw.countryCode ?? raw.country_code),
    currency: normalizeCurrency(raw.currency),
    amountMinor: normalizeLimit(raw.amountMinor ?? raw.amount_minor, 0),
    billingPeriod: normalizeBillingPeriod(raw.billingPeriod ?? raw.billing_period),
    provider: normalizeProvider(raw.provider),
    storeProductId: normalizeText(raw.storeProductId ?? raw.store_product_id),
    isActive:
      raw.isActive == null && raw.is_active == null
        ? true
        : Boolean(raw.isActive ?? raw.is_active),
  };
}

function normalizePlanRow(row) {
  const entitlements = normalizeEntitlements(row);
  return {
    code: row.code,
    name: row.name,
    description: row.description || '',
    isActive: Boolean(row.is_active),
    features: entitlements.features,
    sellingModes: entitlements.allowedSellingModes,
    availableSellingModes: availableSellingModesForEntitlements(entitlements),
    maxBranches: entitlements.maxBranches,
    maxEmployees: entitlements.maxEmployees,
    maxAiAgents: entitlements.maxAiAgents,
    aiRateHourly: entitlements.aiRateLimits.hourly,
    aiRateWeekly: entitlements.aiRateLimits.weekly,
    aiRateMonthly: entitlements.aiRateLimits.monthly,
    sortOrder: Number(row.sort_order || 0),
    entitlements,
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizePriceRow(row) {
  return {
    id: row.id,
    planCode: row.plan_code,
    countryCode: row.country_code,
    currency: row.currency,
    amountMinor: Number(row.amount_minor || 0),
    billingPeriod: row.billing_period || 'monthly',
    provider: row.provider || 'google_play',
    storeProductId: normalizeText(row.store_product_id),
    isActive: row.is_active !== false,
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeEntitlements(row) {
  const features = normalizeFeatureList(row.features_json);
  const allowedSellingModes = normalizeSellingModes(
    row.allowed_selling_modes_json,
    DEFAULT_SELLING_MODES,
  );
  return {
    features,
    allowedSellingModes,
    sellingModes: availableSellingModesForFeatures(features, allowedSellingModes),
    maxBranches: normalizeLimit(row.max_branches, 1),
    maxEmployees: normalizeLimit(row.max_employees, 1),
    maxAiAgents: normalizeLimit(row.max_ai_agents, 0),
    aiRateLimits: {
      hourly: normalizeLimit(row.ai_rate_hourly, 0),
      weekly: normalizeLimit(row.ai_rate_weekly, 0),
      monthly: normalizeLimit(row.ai_rate_monthly, 0),
    },
  };
}

function defaultTrialEntitlements() {
  const trial = DEFAULT_PLANS[0];
  const allowedSellingModes = normalizeSellingModes(
    trial.sellingModes,
    DEFAULT_SELLING_MODES,
  );
  return {
    features: [...trial.features],
    allowedSellingModes,
    sellingModes: availableSellingModesForFeatures(trial.features, allowedSellingModes),
    maxBranches: trial.maxBranches,
    maxEmployees: trial.maxEmployees,
    maxAiAgents: trial.maxAiAgents,
    aiRateLimits: {
      hourly: trial.aiRateHourly,
      weekly: trial.aiRateWeekly,
      monthly: trial.aiRateMonthly,
    },
  };
}

function providerForCountry(countryCode) {
  return 'google_play';
}

function normalizePrices(values) {
  if (!Array.isArray(values)) {
    return [];
  }
  return values.map((value) => normalizePriceInput(value)).filter((price) => price.planCode);
}

function normalizeFeatureList(value) {
  let source = value;
  if (typeof value === 'string') {
    try {
      source = JSON.parse(value);
    } catch (_) {
      source = [];
    }
  }
  if (!Array.isArray(source)) {
    return [];
  }
  const normalized = [];
  for (const item of source) {
    const feature = normalizeText(item);
    if (feature && !normalized.includes(feature)) {
      normalized.push(feature);
    }
  }
  return normalized;
}

function normalizeSellingModes(value, fallback = DEFAULT_SELLING_MODES) {
  let source = value;
  if (typeof value === 'string') {
    try {
      source = JSON.parse(value);
    } catch (_) {
      source = value.split(',');
    }
  }
  if (!Array.isArray(source)) {
    source = fallback;
  }
  const normalized = [];
  for (const item of source) {
    const mode = normalizeSellingMode(item);
    if (mode && !normalized.includes(mode)) {
      normalized.push(mode);
    }
  }
  return normalized.length ? normalized : [...fallback];
}

function normalizeSellingMode(value) {
  const mode = normalizeText(value)?.toLowerCase().replace(/[^a-z0-9_]+/g, '_');
  switch (mode) {
    case SELLING_MODES.products:
    case 'product':
    case 'product_only':
    case 'products_only':
    case 'retail':
      return SELLING_MODES.products;
    case SELLING_MODES.services:
    case 'service':
    case 'service_only':
    case 'services_only':
      return SELLING_MODES.services;
    case SELLING_MODES.combo:
    case 'both':
    case 'mixed':
    case 'product_service':
    case 'product_services':
    case 'products_service':
    case 'products_services':
    case 'product_and_service':
    case 'product_and_services':
    case 'products_and_service':
    case 'products_and_services':
    case 'product_plus_service':
    case 'product_plus_services':
    case 'products_plus_service':
    case 'products_plus_services':
      return SELLING_MODES.combo;
    default:
      return null;
  }
}

function availableSellingModesForEntitlements(entitlements) {
  return availableSellingModesForFeatures(
    entitlements?.features || [],
    entitlements?.allowedSellingModes || DEFAULT_SELLING_MODES,
  );
}

function availableSellingModesForFeatures(features, allowedModes = DEFAULT_SELLING_MODES) {
  const featureSet = new Set(features || []);
  const allowedSet = new Set(normalizeSellingModes(allowedModes, DEFAULT_SELLING_MODES));
  const modes = [];
  if (allowedSet.has(SELLING_MODES.products) && featureSet.has(FEATURE_KEYS.products)) {
    modes.push(SELLING_MODES.products);
  }
  if (allowedSet.has(SELLING_MODES.services) && featureSet.has(FEATURE_KEYS.services)) {
    modes.push(SELLING_MODES.services);
  }
  if (
    allowedSet.has(SELLING_MODES.combo) &&
    featureSet.has(FEATURE_KEYS.products) &&
    featureSet.has(FEATURE_KEYS.services)
  ) {
    modes.push(SELLING_MODES.combo);
  }
  return modes;
}

function applySellingModeToEntitlements(entitlements, sellingMode) {
  const mode = normalizeSellingMode(sellingMode) || SELLING_MODES.combo;
  const source = entitlements && typeof entitlements === 'object'
    ? entitlements
    : defaultTrialEntitlements();
  const disabled = new Set();
  if (mode === SELLING_MODES.products) {
    disabled.add(FEATURE_KEYS.services);
  } else if (mode === SELLING_MODES.services) {
    disabled.add(FEATURE_KEYS.products);
    disabled.add(FEATURE_KEYS.categories);
    disabled.add(FEATURE_KEYS.purchases);
    disabled.add(FEATURE_KEYS.stockList);
    disabled.add(FEATURE_KEYS.transfers);
  }
  return {
    ...source,
    features: (source.features || []).filter((feature) => !disabled.has(feature)),
    sellingMode: mode,
    allowedSellingModes: source.allowedSellingModes || DEFAULT_SELLING_MODES,
    sellingModes: availableSellingModesForEntitlements(source),
  };
}

function validateSellingModeEntitlement(entitlements, sellingMode) {
  const mode = normalizeSellingMode(sellingMode);
  if (!mode) {
    return {
      ok: false,
      message: 'Choose products, services, or combo for the business type.',
    };
  }
  const modes = availableSellingModesForEntitlements(entitlements);
  if (!modes.includes(mode)) {
    return {
      ok: false,
      message:
        mode === SELLING_MODES.combo
          ? 'This plan must include both Products and Services before Combo can be selected.'
          : `This plan does not include ${mode}.`,
    };
  }
  return { ok: true, mode };
}

function normalizeCode(value) {
  const text = normalizeText(value);
  return text ? text.toLowerCase().replace(/[^a-z0-9_]+/g, '_') : null;
}

function normalizeText(value) {
  const text = value == null ? '' : String(value).trim();
  return text || null;
}

function normalizeCountryCode(value) {
  const text = normalizeText(value);
  if (!text) return 'GLOBAL';
  return text.toUpperCase().slice(0, 8);
}

function normalizeCurrency(value) {
  const text = normalizeText(value);
  return (text || 'USD').toUpperCase().slice(0, 3);
}

function normalizeProvider(value) {
  const text = normalizeText(value);
  return (text || 'google_play').toLowerCase().replace(/[^a-z0-9_]+/g, '_');
}

function normalizeBillingPeriod(value) {
  const text = normalizeText(value);
  return (text || 'monthly').toLowerCase();
}

function normalizeLimit(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(0, Math.floor(parsed));
}

function normalizeTrialDays(value, fallback = null) {
  const candidate =
    value == null || String(value).trim() === '' ? fallback : value;
  const parsed = Number(candidate);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 365) {
    throw createError(
      400,
      'Trial period must be a whole number between 1 and 365 days.',
    );
  }
  return parsed;
}

function configuredTrialDays() {
  return normalizeTrialDays(config.subscriptionTrialDays, 30);
}

function normalizeGraceDays(value, fallback = null) {
  const candidate =
    value == null || String(value).trim() === '' ? fallback : value;
  const parsed = Number(candidate);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 30) {
    throw createError(
      400,
      'Grace period must be a whole number between 0 and 30 days.',
    );
  }
  return parsed;
}

function configuredGraceDays() {
  return normalizeGraceDays(config.subscriptionGraceDays, 5);
}

function toIsoString(value) {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function parseDate(value) {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (value == null) {
    return null;
  }
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function runQuery(target, sql, params = []) {
  if (typeof target === 'function') {
    return target(sql, params);
  }
  return target.query(sql, params);
}

module.exports = {
  ALL_FEATURES,
  DEFAULT_PLANS,
  FEATURE_KEYS,
  SELLING_MODES,
  applySellingModeToEntitlements,
  availableSellingModesForEntitlements,
  ensureSubscriptionSchema,
  listPaymentGateways,
  listPlans,
  loadPlatformSubscriptionSettings,
  listPublicPlans,
  listPublicMarkets,
  loadEntitlementsForPlan,
  loadPaymentGateway,
  isPriceAvailableForPublicCatalog,
  isPriceVisibleInPublicCatalog,
  isSubscriptionPaymentProviderAllowed,
  isHttpsUrl,
  isPlausibleMpesaPasskey,
  normalizePlanInput,
  normalizeCountryCode,
  normalizePriceInput,
  normalizePriceRow,
  normalizeProvider,
  normalizeSellingMode,
  normalizeGraceDays,
  normalizeTrialDays,
  providerForCountry,
  renewalBaseDate,
  resolvePlanPrice,
  savePaymentGateway,
  savePlatformSubscriptionSettings,
  validatePaymentGatewayConfiguration,
  validateSellingModeEntitlement,
};
