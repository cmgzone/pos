const crypto = require('crypto');

const SEVERITY_RANK = Object.freeze({
  info: 0,
  medium: 1,
  high: 2,
});
const ALLOWED_SEVERITIES = new Set(Object.keys(SEVERITY_RANK));

function createPikiCloudModule({ query, config }) {
  let schemaReady = false;

  async function ensureSchema(target = query) {
    const canUseCache = target === query;
    if (canUseCache && schemaReady) return;

    await runQuery(
      target,
      `
      CREATE TABLE IF NOT EXISTS piki_cloud_settings (
        business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
        enabled boolean NOT NULL DEFAULT false,
        notification_email text,
        minimum_severity text NOT NULL DEFAULT 'high',
        cooldown_minutes integer NOT NULL DEFAULT 360,
        created_at timestamptz NOT NULL DEFAULT NOW(),
        updated_at timestamptz NOT NULL DEFAULT NOW(),
        CONSTRAINT piki_cloud_settings_severity
          CHECK (minimum_severity IN ('info', 'medium', 'high')),
        CONSTRAINT piki_cloud_settings_cooldown
          CHECK (cooldown_minutes >= 15 AND cooldown_minutes <= 10080)
      )
      `,
    );
    await runQuery(
      target,
      `
      CREATE TABLE IF NOT EXISTS piki_cloud_deliveries (
        id text PRIMARY KEY,
        business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
        insight_id text,
        dedupe_key text NOT NULL,
        channel text NOT NULL DEFAULT 'email',
        recipient text NOT NULL,
        status text NOT NULL DEFAULT 'pending',
        error_message text,
        created_at timestamptz NOT NULL DEFAULT NOW(),
        sent_at timestamptz
      )
      `,
    );
    await runQuery(
      target,
      `
      CREATE INDEX IF NOT EXISTS idx_piki_cloud_delivery_dedupe
        ON piki_cloud_deliveries(
          business_id, dedupe_key, channel, recipient, sent_at DESC
        )
      `,
    );
    await runQuery(
      target,
      `
      CREATE INDEX IF NOT EXISTS idx_piki_cloud_delivery_business
        ON piki_cloud_deliveries(business_id, created_at DESC)
      `,
    );

    if (canUseCache) schemaReady = true;
  }

  async function getSettings(businessId) {
    await ensureSchema();
    const result = await query(
      `
      SELECT settings.*, business.owner_email,
        (
          SELECT sent_at
          FROM piki_cloud_deliveries delivery
          WHERE delivery.business_id = business.id
            AND delivery.status = 'sent'
          ORDER BY delivery.sent_at DESC
          LIMIT 1
        ) AS last_delivery_at
      FROM businesses business
      LEFT JOIN piki_cloud_settings settings ON settings.business_id = business.id
      WHERE business.id = $1
      LIMIT 1
      `,
      [businessId],
    );
    return normalizeSettingsRow(result.rows[0], config);
  }

  async function saveSettings(businessId, input = {}) {
    await ensureSchema();
    const existing = await getSettings(businessId);
    const enabled = input.enabled == null ? existing.enabled : Boolean(input.enabled);
    const notificationEmail = normalizeEmail(
      input.notificationEmail ?? input.notification_email ?? existing.notificationEmail,
    );
    const minimumSeverity = normalizeSeverity(
      input.minimumSeverity ?? input.minimum_severity ?? existing.minimumSeverity,
    );
    const cooldownMinutes = normalizeCooldown(
      input.cooldownMinutes ?? input.cooldown_minutes ?? existing.cooldownMinutes,
    );
    if (enabled && !notificationEmail) {
      throw createError(400, 'Add a notification email before enabling Piki Cloud.');
    }

    const result = await query(
      `
      INSERT INTO piki_cloud_settings (
        business_id, enabled, notification_email, minimum_severity,
        cooldown_minutes, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
      ON CONFLICT (business_id) DO UPDATE
      SET enabled = EXCLUDED.enabled,
          notification_email = EXCLUDED.notification_email,
          minimum_severity = EXCLUDED.minimum_severity,
          cooldown_minutes = EXCLUDED.cooldown_minutes,
          updated_at = NOW()
      RETURNING *
      `,
      [businessId, enabled, notificationEmail, minimumSeverity, cooldownMinutes],
    );
    const owner = await query(
      'SELECT owner_email FROM businesses WHERE id = $1 LIMIT 1',
      [businessId],
    );
    return normalizeSettingsRow(
      {
        ...result.rows[0],
        owner_email: owner.rows[0]?.owner_email || null,
      },
      config,
    );
  }

  async function dispatchBusinessAlerts({ businessId }) {
    await ensureSchema();
    const settings = await getSettings(businessId);
    if (!settings.enabled) {
      return { sent: 0, skipped: 'disabled' };
    }
    if (!settings.notificationEmail) {
      return { sent: 0, skipped: 'missing_recipient' };
    }
    if (!config.resendApiKey) {
      return { sent: 0, skipped: 'email_not_configured' };
    }

    const businessResult = await query(
      'SELECT name FROM businesses WHERE id = $1 LIMIT 1',
      [businessId],
    );
    const businessName = String(businessResult.rows[0]?.name || 'your business');
    const insightsResult = await query(
      `
      SELECT id, severity, kind, title, body, dedupe_key, action_json
      FROM piki_proactive_insights
      WHERE business_id = $1
        AND status = 'active'
        AND generated_at >= NOW() - INTERVAL '35 minutes'
      ORDER BY
        CASE severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
        generated_at DESC
      LIMIT 20
      `,
      [businessId],
    );

    let sent = 0;
    let skipped = 0;
    let failed = 0;
    for (const insight of insightsResult.rows) {
      if (!meetsSeverity(insight.severity, settings.minimumSeverity)) {
        skipped += 1;
        continue;
      }
      const deliveredRecently = await query(
        `
        SELECT id
        FROM piki_cloud_deliveries
        WHERE business_id = $1
          AND dedupe_key = $2
          AND channel = 'email'
          AND recipient = $3
          AND status = 'sent'
          AND sent_at >= NOW() - ($4::int * INTERVAL '1 minute')
        ORDER BY sent_at DESC
        LIMIT 1
        `,
        [businessId, insight.dedupe_key, settings.notificationEmail, settings.cooldownMinutes],
      );
      if (deliveredRecently.rows.length > 0) {
        skipped += 1;
        continue;
      }

      try {
        await sendInsightEmail({
          config,
          recipient: settings.notificationEmail,
          businessName,
          insight,
        });
        await recordDelivery({
          businessId,
          insight,
          recipient: settings.notificationEmail,
          status: 'sent',
        });
        sent += 1;
      } catch (error) {
        await recordDelivery({
          businessId,
          insight,
          recipient: settings.notificationEmail,
          status: 'failed',
          errorMessage: error.message,
        });
        failed += 1;
        console.error(
          `Piki Cloud could not deliver ${insight.kind} for ${businessId}:`,
          error.message,
        );
      }
    }
    return { sent, skipped, failed };
  }

  async function recordDelivery({
    businessId,
    insight,
    recipient,
    status,
    errorMessage = null,
  }) {
    await query(
      `
      INSERT INTO piki_cloud_deliveries (
        id, business_id, insight_id, dedupe_key, channel, recipient,
        status, error_message, created_at, sent_at
      )
      VALUES ($1, $2, $3, $4, 'email', $5, $6, $7, NOW(),
        CASE WHEN $6 = 'sent' THEN NOW() ELSE NULL END)
      `,
      [
        crypto.randomUUID(),
        businessId,
        insight.id || null,
        insight.dedupe_key || insight.kind || 'piki_alert',
        recipient,
        status,
        limitText(errorMessage, 500),
      ],
    );
  }

  return {
    dispatchBusinessAlerts,
    ensureSchema,
    getSettings,
    saveSettings,
  };
}

async function sendInsightEmail({ config, recipient, businessName, insight }) {
  const from = String(
    config.pikiCloudFromEmail || config.otpFromEmail || config.smtpFromEmail || '',
  ).trim();
  if (!from) throw new Error('Piki Cloud sender email is not configured.');

  const fetch = (await import('node-fetch')).default;
  const response = await fetch(`${config.resendApiBaseUrl}/emails`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.resendApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [recipient],
      subject: `Piki Cloud: ${limitText(insight.title, 120)}`,
      text: `Piki Cloud alert for ${businessName}\n\n${insight.title}\n${insight.body}\n\nOpen Piki POS to review the recommendation.`,
      html: buildInsightEmailHtml({ businessName, insight }),
      tags: [{ name: 'kind', value: 'piki_cloud_alert' }],
    }),
  });
  if (response.ok) return;

  let message = `Email provider rejected the Piki Cloud alert (${response.status}).`;
  try {
    const body = await response.json();
    message = body?.message || body?.error?.message || message;
  } catch (_) {
    // Preserve the HTTP status message.
  }
  throw new Error(message);
}

function buildInsightEmailHtml({ businessName, insight }) {
  return `
    <div style="font-family:Arial,sans-serif;color:#171421;line-height:1.5;max-width:560px">
      <p style="margin:0 0 8px;color:#6b6478;font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase">Piki Cloud</p>
      <h2 style="margin:0 0 12px">${escapeHtml(insight.title)}</h2>
      <p style="margin:0 0 16px">${escapeHtml(insight.body)}</p>
      <p style="margin:0;color:#6b6478;font-size:13px">${escapeHtml(businessName)} · Open Piki POS to review the recommendation. You can change cloud alerts in Settings.</p>
    </div>
  `;
}

function normalizeSettingsRow(row, config) {
  const ownerEmail = normalizeEmail(row?.owner_email);
  const notificationEmail = normalizeEmail(row?.notification_email) || ownerEmail;
  return {
    enabled: row?.enabled === true,
    notificationEmail,
    minimumSeverity: normalizeSeverity(row?.minimum_severity || 'high'),
    cooldownMinutes: normalizeCooldown(row?.cooldown_minutes || 360),
    emailConfigured: Boolean(config.resendApiKey),
    lastDeliveryAt: toIsoString(row?.last_delivery_at),
  };
}

function meetsSeverity(value, minimum) {
  const actual = SEVERITY_RANK[normalizeSeverity(value)] ?? 0;
  const threshold = SEVERITY_RANK[normalizeSeverity(minimum)] ?? 2;
  return actual >= threshold;
}

function normalizeSeverity(value) {
  const normalized = String(value || 'high').trim().toLowerCase();
  return ALLOWED_SEVERITIES.has(normalized) ? normalized : 'high';
}

function normalizeCooldown(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 360;
  return Math.min(10080, Math.max(15, Math.round(parsed)));
}

function normalizeEmail(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (!normalized) return '';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
    throw createError(400, 'Enter a valid Piki Cloud notification email.');
  }
  return normalized;
}

function limitText(value, max) {
  const text = String(value || '').trim();
  return text.length <= max ? text : text.slice(0, max);
}

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function toIsoString(value) {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function createError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

async function runQuery(target, text, params = []) {
  if (typeof target === 'function') return target(text, params);
  return target.query(text, params);
}

module.exports = {
  createPikiCloudModule,
  meetsSeverity,
  normalizeCooldown,
  normalizeSeverity,
};
