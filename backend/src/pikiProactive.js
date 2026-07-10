const crypto = require('crypto');

const DEFAULT_BRANCH_ID = 'main_branch';
let workerHandle = null;
let workerRunning = false;

async function ensurePikiProactiveSchema(target) {
  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS piki_learning (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text,
      kind text NOT NULL,
      phrase text NOT NULL,
      target text NOT NULL,
      weight double precision NOT NULL DEFAULT 1,
      metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW(),
      deleted_at timestamptz
    )
    `,
  );
  await runQuery(
    target,
    `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_piki_learning_business_phrase
      ON piki_learning(business_id, kind, COALESCE(branch_id, ''), LOWER(phrase))
      WHERE deleted_at IS NULL
    `,
  );
  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS piki_proactive_insights (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      branch_id text,
      severity text NOT NULL DEFAULT 'info',
      kind text NOT NULL,
      title text NOT NULL,
      body text NOT NULL,
      action_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      dedupe_key text NOT NULL,
      status text NOT NULL DEFAULT 'active',
      generated_at timestamptz NOT NULL DEFAULT NOW(),
      acknowledged_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );
  await runQuery(
    target,
    `
    CREATE UNIQUE INDEX IF NOT EXISTS idx_piki_proactive_dedupe
      ON piki_proactive_insights(business_id, dedupe_key)
    `,
  );
  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_piki_proactive_active
      ON piki_proactive_insights(business_id, status, generated_at DESC)
    `,
  );
}

function buildInsightRowsFromSnapshot(snapshot, now = new Date()) {
  const generatedAt =
    now instanceof Date ? now.toISOString() : new Date(now).toISOString();
  const currency = snapshot.currency || '';
  const branchId = snapshot.branchId || null;
  const insights = [];

  const lowStock = Array.isArray(snapshot.lowStock) ? snapshot.lowStock : [];
  if (lowStock.length > 0) {
    const names = lowStock.slice(0, 3).map((item) => item.name).join(', ');
    insights.push({
      branch_id: branchId,
      severity: lowStock.length >= 5 ? 'high' : 'medium',
      kind: 'low_stock',
      title: `${lowStock.length} low-stock item${lowStock.length === 1 ? '' : 's'}`,
      body: names
        ? `Restock ${names}${lowStock.length > 3 ? ', and more' : ''}.`
        : 'Inventory is below reorder levels.',
      action_json: { tool: 'restock_list', limit: 10 },
      dedupe_key: dedupeKey('low_stock', branchId),
      generated_at: generatedAt,
    });
  }

  const expiring = Array.isArray(snapshot.expiringBatches)
    ? snapshot.expiringBatches
    : [];
  if (expiring.length > 0) {
    const first = expiring[0];
    insights.push({
      branch_id: branchId,
      severity: 'medium',
      kind: 'expiry_risk',
      title: `${expiring.length} batch${expiring.length === 1 ? '' : 'es'} expiring soon`,
      body: first?.name
        ? `${first.name} expires first. Discount, move, or sell it before it turns into waste.`
        : 'Some batches are expiring soon.',
      action_json: { tool: 'expiry_check', limit: 10 },
      dedupe_key: dedupeKey('expiry_risk', branchId),
      generated_at: generatedAt,
    });
  }

  const today = snapshot.todaySales || {};
  const yesterday = snapshot.yesterdaySales || {};
  const todayRevenue = Number(today.revenue || 0);
  const yesterdayRevenue = Number(yesterday.revenue || 0);
  if (yesterdayRevenue > 0 && todayRevenue < yesterdayRevenue * 0.6) {
    const dropPercent = Math.round(
      ((yesterdayRevenue - todayRevenue) / yesterdayRevenue) * 100,
    );
    insights.push({
      branch_id: branchId,
      severity: dropPercent >= 60 ? 'high' : 'medium',
      kind: 'sales_drop',
      title: 'Sales are tracking below yesterday',
      body: `Today is at ${currency}${todayRevenue.toFixed(2)}, down about ${dropPercent}% from yesterday.`,
      action_json: { tool: 'sales_summary', daysRange: 2 },
      dedupe_key: dedupeKey('sales_drop', branchId),
      generated_at: generatedAt,
    });
  }

  const openShifts = Array.isArray(snapshot.openShifts)
    ? snapshot.openShifts
    : [];
  if (openShifts.length > 0) {
    const cashierNames = openShifts
      .slice(0, 3)
      .map((shift) => shift.cashier_name || 'cashier')
      .join(', ');
    insights.push({
      branch_id: branchId,
      severity: 'high',
      kind: 'open_shift',
      title: `${openShifts.length} shift${openShifts.length === 1 ? '' : 's'} open over 12 hours`,
      body: `Ask ${cashierNames} to close or reconcile the drawer.`,
      action_json: { tool: 'shift_summary', limit: 5 },
      dedupe_key: dedupeKey('open_shift', branchId),
      generated_at: generatedAt,
    });
  }

  const debtors = snapshot.debtors || {};
  const debtorTotal = Number(debtors.total || 0);
  const debtorCount = Number(debtors.count || 0);
  if (debtorTotal > 0 && debtorCount > 0) {
    insights.push({
      branch_id: branchId,
      severity: debtorTotal >= 10000 ? 'medium' : 'info',
      kind: 'customer_debt',
      title: `${debtorCount} customer${debtorCount === 1 ? '' : 's'} owe balances`,
      body: `Outstanding Kopesha balance is ${currency}${debtorTotal.toFixed(2)}.`,
      action_json: { tool: 'top_debtors', limit: 10 },
      dedupe_key: dedupeKey('customer_debt', branchId),
      generated_at: generatedAt,
    });
  }

  return insights;
}

async function refreshBusinessInsights(client, businessId, options = {}) {
  const branchId = normalizeText(options.branchId);
  await ensurePikiProactiveSchema(client);
  const snapshot = await loadBusinessSnapshot(client, businessId, branchId);
  const insights = buildInsightRowsFromSnapshot(snapshot);
  const now = new Date().toISOString();

  await client.query(
    `
    UPDATE piki_proactive_insights
    SET status = 'stale', updated_at = $2
    WHERE business_id = $1
      AND status = 'active'
      AND (
        $3::text IS NULL
        OR COALESCE(branch_id, '${DEFAULT_BRANCH_ID}') = COALESCE($3, '${DEFAULT_BRANCH_ID}')
      )
    `,
    [businessId, now, branchId],
  );

  for (const insight of insights) {
    await client.query(
      `
      INSERT INTO piki_proactive_insights (
        id, business_id, branch_id, severity, kind, title, body,
        action_json, dedupe_key, status, generated_at, created_at, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, 'active', $10, $11, $11
      )
      ON CONFLICT (business_id, dedupe_key) DO UPDATE
      SET branch_id = EXCLUDED.branch_id,
          severity = EXCLUDED.severity,
          kind = EXCLUDED.kind,
          title = EXCLUDED.title,
          body = EXCLUDED.body,
          action_json = EXCLUDED.action_json,
          status = 'active',
          generated_at = EXCLUDED.generated_at,
          updated_at = EXCLUDED.updated_at
      `,
      [
        crypto.randomUUID(),
        businessId,
        insight.branch_id,
        insight.severity,
        insight.kind,
        insight.title,
        insight.body,
        JSON.stringify(insight.action_json || {}),
        insight.dedupe_key,
        insight.generated_at,
        now,
      ],
    );
  }

  return insights;
}

function startPikiProactiveWorker({
  query,
  withTransaction,
  intervalMs = 15 * 60 * 1000,
  initialDelayMs = 10 * 1000,
  onBusinessRefreshed = null,
} = {}) {
  if (!query || !withTransaction || workerHandle) {
    return { stop: stopPikiProactiveWorker };
  }

  const run = async () => {
    if (workerRunning) return;
    workerRunning = true;
    try {
      const businesses = await query(
        'SELECT id FROM businesses ORDER BY created_at ASC',
      );
      for (const business of businesses.rows) {
        try {
          await withTransaction((client) =>
            refreshBusinessInsights(client, business.id),
          );
          if (typeof onBusinessRefreshed === 'function') {
            await onBusinessRefreshed({ businessId: business.id });
          }
        } catch (error) {
          console.error(
            `Piki proactive refresh failed for ${business.id}:`,
            error.message,
          );
        }
      }
    } catch (error) {
      console.error('Piki proactive worker failed:', error.message);
    } finally {
      workerRunning = false;
    }
  };

  const firstRun = setTimeout(run, Math.max(1000, Number(initialDelayMs) || 0));
  const interval = setInterval(run, Math.max(60_000, Number(intervalMs) || 0));
  workerHandle = { firstRun, interval };
  return { stop: stopPikiProactiveWorker };
}

function stopPikiProactiveWorker() {
  if (!workerHandle) return;
  clearTimeout(workerHandle.firstRun);
  clearInterval(workerHandle.interval);
  workerHandle = null;
}

async function loadBusinessSnapshot(client, businessId, branchId) {
  const businessResult = await client.query(
    'SELECT currency, country_code FROM businesses WHERE id = $1 LIMIT 1',
    [businessId],
  );
  const lowStockParams = [businessId];
  const lowStockBranch = branchClause('p', lowStockParams, branchId);
  const lowStock = await client.query(
    `
    SELECT p.id, p.name, p.stock, p.low_stock, p.unit
    FROM products p
    WHERE p.business_id = $1
      AND p.deleted_at IS NULL
      AND COALESCE(p.track_stock, 1) <> 0
      AND p.stock <= p.low_stock
      ${lowStockBranch}
    ORDER BY (p.stock - p.low_stock) ASC, p.name ASC
    LIMIT 10
    `,
    lowStockParams,
  );

  const expiryParams = [businessId];
  const expiryBranch = branchClause('sb', expiryParams, branchId);
  const expiring = await client.query(
    `
    SELECT sb.id, p.name, sb.quantity_remaining, sb.expiry_date
    FROM stock_batches sb
    JOIN products p ON p.id = sb.product_id
    WHERE sb.business_id = $1
      AND sb.deleted_at IS NULL
      AND sb.quantity_remaining > 0
      AND sb.expiry_date IS NOT NULL
      AND sb.expiry_date <= CURRENT_DATE + INTERVAL '7 days'
      ${expiryBranch}
    ORDER BY sb.expiry_date ASC, p.name ASC
    LIMIT 10
    `,
    expiryParams,
  );

  const todaySales = await loadSalesSummary(client, businessId, branchId, 0);
  const yesterdaySales = await loadSalesSummary(client, businessId, branchId, 1);

  const shiftParams = [businessId];
  const shiftBranch = branchClause('s', shiftParams, branchId);
  const openShifts = await client.query(
    `
    SELECT s.id, s.cashier_name, s.opened_at
    FROM shifts s
    WHERE s.business_id = $1
      AND s.deleted_at IS NULL
      AND LOWER(s.status) = 'open'
      AND s.opened_at <= NOW() - INTERVAL '12 hours'
      ${shiftBranch}
    ORDER BY s.opened_at ASC
    LIMIT 10
    `,
    shiftParams,
  );

  const debtorParams = [businessId];
  const debtorBranch = branchClause('c', debtorParams, branchId);
  const debtors = await client.query(
    `
    SELECT COUNT(*)::int AS count, COALESCE(SUM(c.balance), 0)::float AS total
    FROM customers c
    WHERE c.business_id = $1
      AND c.deleted_at IS NULL
      AND c.balance > 0
      ${debtorBranch}
    `,
    debtorParams,
  );

  return {
    branchId,
    currency: String(
      businessResult.rows[0]?.currency ||
        displayCurrencyForCountry(businessResult.rows[0]?.country_code),
    ).trim(),
    lowStock: lowStock.rows,
    expiringBatches: expiring.rows,
    todaySales,
    yesterdaySales,
    openShifts: openShifts.rows,
    debtors: debtors.rows[0] || { count: 0, total: 0 },
  };
}

async function loadSalesSummary(client, businessId, branchId, dayOffset) {
  const params = [businessId, dayOffset];
  const salesBranch = branchClause('s', params, branchId);
  const result = await client.query(
    `
    SELECT COUNT(*)::int AS count, COALESCE(SUM(s.total_amount), 0)::float AS revenue
    FROM sales s
    WHERE s.business_id = $1
      AND s.deleted_at IS NULL
      AND s.refund_for_sale_id IS NULL
      AND s.created_at >= date_trunc('day', NOW()) - ($2::int * INTERVAL '1 day')
      AND s.created_at < date_trunc('day', NOW()) - (($2::int - 1) * INTERVAL '1 day')
      ${salesBranch}
    `,
    params,
  );
  return result.rows[0] || { count: 0, revenue: 0 };
}

function branchClause(alias, params, branchId) {
  if (!branchId) return '';
  params.push(branchId);
  return `AND COALESCE(${alias}.branch_id, '${DEFAULT_BRANCH_ID}') = $${params.length}`;
}

function displayCurrencyForCountry(countryCode) {
  const normalized = String(countryCode || '').trim().toUpperCase();
  if (normalized === 'KE') return 'KSh';
  if (normalized === 'TZ') return 'TSh';
  if (normalized === 'UG') return 'USh';
  if (normalized === 'RW') return 'FRw';
  if (normalized === 'ZA') return 'R';
  if (normalized === 'GB') return '\u00A3';
  return '$';
}

async function runQuery(target, text, params = []) {
  if (typeof target === 'function') {
    return target(text, params);
  }
  return target.query(text, params);
}

function dedupeKey(kind, branchId) {
  return `${kind}:${branchId || 'all'}`;
}

function normalizeText(value) {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized === '' ? null : normalized;
}

module.exports = {
  buildInsightRowsFromSnapshot,
  ensurePikiProactiveSchema,
  refreshBusinessInsights,
  startPikiProactiveWorker,
  stopPikiProactiveWorker,
};
