const crypto = require('crypto');

const { query } = require('./db');
const { normalizeCountryCode } = require('./subscriptionPlans');

const SECRET_MASK_PREFIX = '********';
const META_API_VERSION_PATTERN = /^v\d+\.\d+$/;

let schemaReady = false;

async function ensureCommunicationSchema(target = query) {
  const canUseCache = target === query;
  if (canUseCache && schemaReady) {
    return;
  }

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS platform_message_gateways (
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

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS business_communication_settings (
      business_id text PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
      whatsapp_number text,
      sms_sender_id text,
      allow_api_send boolean NOT NULL DEFAULT true,
      whatsapp_api_status text NOT NULL DEFAULT 'not_connected',
      whatsapp_waba_id text,
      whatsapp_phone_number_id text,
      whatsapp_display_phone_number text,
      whatsapp_business_name text,
      whatsapp_access_token text,
      whatsapp_connected_at timestamptz,
      whatsapp_last_error text,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await ensureBusinessCommunicationColumns(target);

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS message_send_logs (
      id text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      user_id text,
      channel text NOT NULL,
      mode text NOT NULL DEFAULT 'api',
      provider text,
      recipient text NOT NULL,
      body text NOT NULL,
      status text NOT NULL DEFAULT 'pending',
      error_message text,
      metadata_json jsonb NOT NULL DEFAULT '{}'::jsonb,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      updated_at timestamptz NOT NULL DEFAULT NOW()
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE TABLE IF NOT EXISTS business_whatsapp_connect_sessions (
      token_hash text PRIMARY KEY,
      business_id text NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
      device_id text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT NOW(),
      expires_at timestamptz NOT NULL,
      consumed_at timestamptz
    )
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_whatsapp_connect_sessions_business
      ON business_whatsapp_connect_sessions(business_id, created_at DESC)
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_whatsapp_connect_sessions_expires
      ON business_whatsapp_connect_sessions(expires_at)
    `,
  );

  await runQuery(
    target,
    `
    CREATE INDEX IF NOT EXISTS idx_message_send_logs_business
      ON message_send_logs(business_id, created_at DESC)
    `,
  );

  await seedDefaultMessageGateways(target);

  if (canUseCache) {
    schemaReady = true;
  }
}

async function listMessageGateways({ includeSecrets = false } = {}, target = query) {
  await ensureCommunicationSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM platform_message_gateways
    ORDER BY CASE provider
      WHEN 'whatsapp' THEN 0
      WHEN 'africas_talking' THEN 1
      ELSE 2
    END, provider ASC
    `,
  );
  return result.rows.map((row) => normalizeGatewayRow(row, { includeSecrets }));
}

async function loadMessageGateway(provider, target = query, { includeSecrets = true } = {}) {
  await ensureCommunicationSchema(target);
  const cleanProvider = normalizeProvider(provider);
  const result = await runQuery(
    target,
    'SELECT * FROM platform_message_gateways WHERE provider = $1 LIMIT 1',
    [cleanProvider],
  );
  return result.rows[0]
    ? normalizeGatewayRow(result.rows[0], { includeSecrets })
    : null;
}

async function saveMessageGateway(provider, input = {}, target = query) {
  await ensureCommunicationSchema(target);
  const cleanProvider = normalizeProvider(provider || input.provider);
  const existing = await loadMessageGateway(cleanProvider, target, {
    includeSecrets: true,
  });
  const normalized = normalizeGatewayInput(input, {
    ...(existing || {}),
    provider: cleanProvider,
  });
  if (cleanProvider === 'whatsapp') {
    const apiVersion = normalizeText(normalized.publicConfig?.apiVersion);
    if (apiVersion && !META_API_VERSION_PATTERN.test(apiVersion)) {
      throw createError(
        400,
        'WhatsApp API Version must look like v25.0. Use zero, not the letter O.',
      );
    }
  }

  const result = await runQuery(
    target,
    `
    INSERT INTO platform_message_gateways (
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

  return normalizeGatewayRow(result.rows[0], { includeSecrets: false });
}

async function getBusinessCommunicationSettings(
  businessId,
  target = query,
  { includeSecrets = false } = {},
) {
  await ensureCommunicationSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM business_communication_settings
    WHERE business_id = $1
    LIMIT 1
    `,
    [businessId],
  );
  return normalizeBusinessSettingsRow(result.rows[0] || { business_id: businessId }, {
    includeSecrets,
  });
}

async function saveBusinessCommunicationSettings(businessId, input = {}, target = query) {
  await ensureCommunicationSchema(target);
  const whatsappNumber = normalizeText(input.whatsappNumber ?? input.whatsapp_number);
  const smsSenderId = normalizeText(input.smsSenderId ?? input.sms_sender_id);
  const allowApiSend =
    input.allowApiSend == null && input.allow_api_send == null
      ? true
      : Boolean(input.allowApiSend ?? input.allow_api_send);
  const result = await runQuery(
    target,
    `
    INSERT INTO business_communication_settings (
      business_id,
      whatsapp_number,
      sms_sender_id,
      allow_api_send,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, NOW(), NOW())
    ON CONFLICT (business_id) DO UPDATE
    SET whatsapp_number = EXCLUDED.whatsapp_number,
        sms_sender_id = EXCLUDED.sms_sender_id,
        allow_api_send = EXCLUDED.allow_api_send,
        updated_at = NOW()
    RETURNING *
    `,
    [businessId, whatsappNumber, smsSenderId, allowApiSend],
  );
  return normalizeBusinessSettingsRow(result.rows[0]);
}

async function getBusinessWhatsAppConnectStatus(businessId, target = query) {
  await ensureCommunicationSchema(target);
  const settings = await getBusinessCommunicationSettings(businessId, target);
  const gateway = await loadMessageGateway('whatsapp', target, {
    includeSecrets: false,
  });
  const publicConfig = gateway?.publicConfig || {};
  const signupConfigId =
    normalizeText(publicConfig.embeddedSignupConfigId) ||
    normalizeText(publicConfig.businessLoginConfigurationId) ||
    normalizeText(publicConfig.configId);
  const embeddedSignupEligible = normalizeConfigFlag(
    publicConfig.embeddedSignupEligible,
  );
  const setupBlockedReason = embeddedSignupEligible
    ? ''
    : 'WhatsApp Embedded Signup requires Meta BSP or Tech Provider approval before store owners can connect their own numbers.';

  return {
    ...settings,
    platform: {
      isActive: gateway?.isActive === true,
      appId: normalizeText(publicConfig.appId) || '',
      apiVersion: normalizeText(publicConfig.apiVersion) || 'v20.0',
      embeddedSignupConfigId: signupConfigId || '',
      embeddedSignupEligible,
      oauthRedirectUri: normalizeText(publicConfig.oauthRedirectUri) || '',
      setupReady: Boolean(
        publicConfig.appId &&
          signupConfigId &&
          publicConfig.oauthRedirectUri &&
          embeddedSignupEligible,
      ),
      setupBlockedReason,
      docsUrl:
        'https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview',
    },
  };
}

async function createBusinessWhatsAppConnectSession(
  businessId,
  deviceId,
  target = query,
) {
  await ensureCommunicationSchema(target);
  const cleanBusinessId = normalizeText(businessId);
  const cleanDeviceId = normalizeText(deviceId);
  if (!cleanBusinessId) {
    throw createError(400, 'businessId is required');
  }
  if (!cleanDeviceId) {
    throw createError(400, 'deviceId is required');
  }

  const token = crypto.randomBytes(32).toString('base64url');
  const tokenHash = hashConnectSessionToken(token);
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

  await runQuery(
    target,
    'DELETE FROM business_whatsapp_connect_sessions WHERE expires_at < NOW() OR consumed_at IS NOT NULL',
  );
  await runQuery(
    target,
    `
    INSERT INTO business_whatsapp_connect_sessions (
      token_hash,
      business_id,
      device_id,
      expires_at
    )
    VALUES ($1, $2, $3, $4)
    `,
    [tokenHash, cleanBusinessId, cleanDeviceId, expiresAt.toISOString()],
  );

  return {
    token,
    expiresAt: expiresAt.toISOString(),
  };
}

async function resolveBusinessWhatsAppConnectSession(token, target = query) {
  await ensureCommunicationSchema(target);
  const tokenHash = hashConnectSessionToken(token);
  if (!tokenHash) return null;

  const result = await runQuery(
    target,
    `
    SELECT business_id, device_id, expires_at
    FROM business_whatsapp_connect_sessions
    WHERE token_hash = $1
      AND consumed_at IS NULL
      AND expires_at > NOW()
    LIMIT 1
    `,
    [tokenHash],
  );
  const row = result.rows[0];
  return row
    ? {
        businessId: row.business_id,
        deviceId: row.device_id,
        expiresAt: toIsoString(row.expires_at),
      }
    : null;
}

async function consumeBusinessWhatsAppConnectSession(token, target = query) {
  await ensureCommunicationSchema(target);
  const tokenHash = hashConnectSessionToken(token);
  if (!tokenHash) return false;

  const result = await runQuery(
    target,
    `
    UPDATE business_whatsapp_connect_sessions
    SET consumed_at = NOW()
    WHERE token_hash = $1
      AND consumed_at IS NULL
      AND expires_at > NOW()
    `,
    [tokenHash],
  );
  return result.rowCount > 0;
}

async function connectBusinessWhatsApp(businessId, input = {}, target = query) {
  await ensureCommunicationSchema(target);
  const gateway = await loadMessageGateway('whatsapp', target, {
    includeSecrets: true,
  });
  if (!gateway) {
    throw createError(400, 'WhatsApp API gateway is not configured');
  }

  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const code = normalizeText(input.code ?? input.authorizationCode);
  const redirectUri =
    normalizeText(input.redirectUri ?? input.redirect_uri) ||
    normalizeText(publicConfig.oauthRedirectUri);
  const exchangeResult = code
    ? await exchangeWhatsAppSignupCode({
        gateway,
        code,
        redirectUri,
      })
    : {};

  const phoneNumberId = normalizeText(
    input.phoneNumberId ??
      input.phone_number_id ??
      input.phoneId ??
      exchangeResult.phoneNumberId,
  );
  const wabaId = normalizeText(
    input.wabaId ??
      input.waba_id ??
      input.whatsappBusinessAccountId ??
      exchangeResult.wabaId,
  );
  const displayPhoneNumber = normalizeText(
    input.displayPhoneNumber ??
      input.display_phone_number ??
      input.whatsappNumber ??
      input.whatsapp_number,
  );
  const businessName = normalizeText(
    input.businessName ?? input.business_name ?? input.verifiedName,
  );
  const accessToken = normalizeText(
    input.accessToken ?? input.access_token ?? exchangeResult.accessToken,
  );

  if (!phoneNumberId) {
    throw createError(400, 'WhatsApp phone number ID is required');
  }
  if (!accessToken && !normalizeText(secretConfig.accessToken)) {
    throw createError(
      400,
      'WhatsApp access token is required for API sending',
    );
  }

  const result = await runQuery(
    target,
    `
    INSERT INTO business_communication_settings (
      business_id,
      whatsapp_number,
      allow_api_send,
      whatsapp_api_status,
      whatsapp_waba_id,
      whatsapp_phone_number_id,
      whatsapp_display_phone_number,
      whatsapp_business_name,
      whatsapp_access_token,
      whatsapp_connected_at,
      whatsapp_last_error,
      created_at,
      updated_at
    )
    VALUES ($1, $2, true, 'connected', $3, $4, $5, $6, $7, NOW(), NULL, NOW(), NOW())
    ON CONFLICT (business_id) DO UPDATE
    SET whatsapp_number = COALESCE(NULLIF(business_communication_settings.whatsapp_number, ''), EXCLUDED.whatsapp_number),
        allow_api_send = true,
        whatsapp_api_status = 'connected',
        whatsapp_waba_id = EXCLUDED.whatsapp_waba_id,
        whatsapp_phone_number_id = EXCLUDED.whatsapp_phone_number_id,
        whatsapp_display_phone_number = EXCLUDED.whatsapp_display_phone_number,
        whatsapp_business_name = EXCLUDED.whatsapp_business_name,
        whatsapp_access_token = COALESCE(EXCLUDED.whatsapp_access_token, business_communication_settings.whatsapp_access_token),
        whatsapp_connected_at = NOW(),
        whatsapp_last_error = NULL,
        updated_at = NOW()
    RETURNING *
    `,
    [
      businessId,
      displayPhoneNumber,
      wabaId,
      phoneNumberId,
      displayPhoneNumber,
      businessName,
      accessToken,
    ],
  );
  return normalizeBusinessSettingsRow(result.rows[0]);
}

async function disconnectBusinessWhatsApp(businessId, target = query) {
  await ensureCommunicationSchema(target);
  const result = await runQuery(
    target,
    `
    INSERT INTO business_communication_settings (
      business_id,
      whatsapp_api_status,
      created_at,
      updated_at
    )
    VALUES ($1, 'not_connected', NOW(), NOW())
    ON CONFLICT (business_id) DO UPDATE
    SET whatsapp_api_status = 'not_connected',
        whatsapp_waba_id = NULL,
        whatsapp_phone_number_id = NULL,
        whatsapp_display_phone_number = NULL,
        whatsapp_business_name = NULL,
        whatsapp_access_token = NULL,
        whatsapp_connected_at = NULL,
        whatsapp_last_error = NULL,
        updated_at = NOW()
    RETURNING *
    `,
    [businessId],
  );
  return normalizeBusinessSettingsRow(result.rows[0]);
}

async function sendBusinessMessage({
  businessContext,
  userId,
  channel,
  recipient,
  body,
  metadata = {},
}) {
  await ensureCommunicationSchema();
  const cleanChannel = normalizeChannel(channel);
  const cleanRecipient = normalizeText(recipient);
  const cleanBody = normalizeText(body);
  if (!cleanRecipient) {
    throw createError(400, 'recipient is required');
  }
  if (!cleanBody) {
    throw createError(400, 'message body is required');
  }

  const settings = await getBusinessCommunicationSettings(
    businessContext.businessId,
    query,
    { includeSecrets: true },
  );
  if (!settings.allowApiSend) {
    throw createError(403, 'API messaging is disabled for this business');
  }

  const provider = cleanChannel === 'sms' ? 'africas_talking' : 'whatsapp';
  const gateway = await loadMessageGateway(provider);
  const countryCode = normalizeCountryCode(businessContext.countryCode || 'GLOBAL');
  if (
    !gateway ||
    !gateway.isActive ||
    (
      !(gateway.countries || []).includes(countryCode) &&
      !(gateway.countries || []).includes('GLOBAL')
    )
  ) {
    throw createError(400, `${gatewayLabel(provider)} is not active for this business country`);
  }

  const log = await insertMessageLog({
    businessId: businessContext.businessId,
    userId,
    channel: cleanChannel,
    mode: 'api',
    provider,
    recipient: cleanRecipient,
    body: cleanBody,
    status: 'pending',
    metadata,
  });

  try {
    const providerResult =
      provider === 'whatsapp'
        ? await sendWhatsAppMessage(gateway, cleanRecipient, cleanBody, settings)
        : await sendAfricasTalkingSms(
            gateway,
            cleanRecipient,
            cleanBody,
            settings.smsSenderId,
          );
    return updateMessageLog(log.id, {
      status: 'sent',
      metadata: providerResult,
    });
  } catch (error) {
    await updateMessageLog(log.id, {
      status: 'failed',
      errorMessage: error.message,
      metadata: { error: error.message },
    });
    throw error;
  }
}

async function listMessageLogs(businessId, { limit = 50 } = {}, target = query) {
  await ensureCommunicationSchema(target);
  const result = await runQuery(
    target,
    `
    SELECT *
    FROM message_send_logs
    WHERE business_id = $1
    ORDER BY created_at DESC
    LIMIT $2
    `,
    [businessId, Math.min(Math.max(Number(limit) || 50, 1), 200)],
  );
  return result.rows.map(normalizeMessageLogRow);
}

async function seedDefaultMessageGateways(target = query) {
  const defaults = [
    {
      provider: 'whatsapp',
      displayName: 'WhatsApp API',
      isActive: false,
      countries: ['GLOBAL', 'KE'],
      publicConfig: {
        baseUrl: 'https://graph.facebook.com',
        apiVersion: 'v20.0',
        appId: '',
        embeddedSignupConfigId: '',
        oauthRedirectUri: '',
        phoneNumberId: '',
      },
      secretConfig: { appSecret: '', accessToken: '' },
    },
    {
      provider: 'africas_talking',
      displayName: "Africa's Talking SMS",
      isActive: false,
      countries: ['KE'],
      publicConfig: {
        username: '',
        senderId: '',
        baseUrl: 'https://api.africastalking.com/version1/messaging',
      },
      secretConfig: { apiKey: '' },
    },
  ];
  for (const gateway of defaults) {
    await runQuery(
      target,
      `
      INSERT INTO platform_message_gateways (
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

async function sendWhatsAppMessage(gateway, recipient, body, businessSettings = {}) {
  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const baseUrl = normalizeText(publicConfig.baseUrl) || 'https://graph.facebook.com';
  const apiVersion = normalizeText(publicConfig.apiVersion) || 'v20.0';
  const phoneNumberId =
    normalizeText(businessSettings.whatsappPhoneNumberId) ||
    normalizeText(publicConfig.phoneNumberId);
  const accessToken =
    normalizeText(businessSettings.whatsappAccessToken) ||
    normalizeText(secretConfig.accessToken);
  if (!phoneNumberId || !accessToken) {
    throw createError(
      400,
      'WhatsApp API sender is not connected for this business',
    );
  }
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(
    `${baseUrl.replace(/\/$/, '')}/${apiVersion}/${phoneNumberId}/messages`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messaging_product: 'whatsapp',
        to: normalizePhone(recipient),
        type: 'text',
        text: { preview_url: false, body },
      }),
    },
  );
  const result = await readMaybeJson(response);
  if (!response.ok) {
    throw createError(
      response.status,
      result?.error?.message || result?.message || 'WhatsApp send failed',
    );
  }
  return result;
}

async function exchangeWhatsAppSignupCode({ gateway, code, redirectUri }) {
  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const baseUrl = normalizeText(publicConfig.baseUrl) || 'https://graph.facebook.com';
  const apiVersion = normalizeText(publicConfig.apiVersion) || 'v20.0';
  const appId = normalizeText(publicConfig.appId);
  const appSecret = normalizeText(secretConfig.appSecret);
  if (!appId || !appSecret) {
    throw createError(
      400,
      'Meta App ID and App Secret are required for Embedded Signup',
    );
  }
  const params = new URLSearchParams({
    client_id: appId,
    client_secret: appSecret,
    code,
  });
  if (redirectUri) {
    params.set('redirect_uri', redirectUri);
  }
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(
    `${baseUrl.replace(/\/$/, '')}/${apiVersion}/oauth/access_token?${params.toString()}`,
  );
  const result = await readMaybeJson(response);
  if (!response.ok) {
    throw createError(
      response.status,
      result?.error?.message || result?.message || 'WhatsApp signup code exchange failed',
    );
  }
  const accessToken = normalizeText(result.access_token);
  const discovered = accessToken
    ? await discoverWhatsAppSignupAssets({
        gateway,
        accessToken,
        fetch,
      })
    : {};
  return {
    accessToken,
    tokenType: normalizeText(result.token_type),
    expiresIn: result.expires_in,
    ...discovered,
  };
}

async function discoverWhatsAppSignupAssets({ gateway, accessToken, fetch }) {
  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const baseUrl = normalizeText(publicConfig.baseUrl) || 'https://graph.facebook.com';
  const apiVersion = normalizeText(publicConfig.apiVersion) || 'v20.0';
  const appId = normalizeText(publicConfig.appId);
  const appSecret = normalizeText(secretConfig.appSecret);
  if (!accessToken || !appId || !appSecret) {
    return {};
  }

  const debugParams = new URLSearchParams({
    input_token: accessToken,
    access_token: `${appId}|${appSecret}`,
  });
  const debugResponse = await fetch(
    `${baseUrl.replace(/\/$/, '')}/${apiVersion}/debug_token?${debugParams.toString()}`,
  );
  const debugResult = await readMaybeJson(debugResponse);
  if (!debugResponse.ok) {
    return {};
  }

  const targetIds = extractDebugTokenTargetIds(debugResult?.data);
  for (const wabaId of targetIds) {
    const phoneResult = await fetchFirstWabaPhoneNumber({
      baseUrl,
      apiVersion,
      wabaId,
      accessToken,
      fetch,
    });
    if (phoneResult.phoneNumberId) {
      return {
        wabaId,
        ...phoneResult,
      };
    }
  }

  return targetIds[0] ? { wabaId: targetIds[0] } : {};
}

function extractDebugTokenTargetIds(data) {
  const ids = [];
  const scopes = Array.isArray(data?.granular_scopes)
    ? data.granular_scopes
    : [];
  for (const scope of scopes) {
    const scopeName = normalizeProvider(scope?.scope);
    if (!scopeName.includes('whatsapp') && scopeName !== 'business_management') {
      continue;
    }
    const targets = Array.isArray(scope?.target_ids) ? scope.target_ids : [];
    for (const id of targets) {
      const clean = normalizeText(id);
      if (clean && !ids.includes(clean)) {
        ids.push(clean);
      }
    }
  }
  return ids;
}

async function fetchFirstWabaPhoneNumber({
  baseUrl,
  apiVersion,
  wabaId,
  accessToken,
  fetch,
}) {
  const params = new URLSearchParams({
    fields: 'id,display_phone_number,verified_name',
    access_token: accessToken,
  });
  const response = await fetch(
    `${baseUrl.replace(/\/$/, '')}/${apiVersion}/${encodeURIComponent(wabaId)}/phone_numbers?${params.toString()}`,
  );
  const result = await readMaybeJson(response);
  if (!response.ok || !Array.isArray(result?.data)) {
    return {};
  }
  const phone = result.data.find((item) => normalizeText(item?.id));
  return phone
    ? {
        phoneNumberId: normalizeText(phone.id),
        displayPhoneNumber: normalizeText(phone.display_phone_number),
        businessName: normalizeText(phone.verified_name),
      }
    : {};
}

async function sendAfricasTalkingSms(gateway, recipient, body, senderId) {
  const publicConfig = gateway.publicConfig || {};
  const secretConfig = gateway.secretConfig || {};
  const username = normalizeText(publicConfig.username);
  const apiKey = normalizeText(secretConfig.apiKey);
  const endpoint =
    normalizeText(publicConfig.baseUrl) ||
    'https://api.africastalking.com/version1/messaging';
  const from = normalizeText(senderId) || normalizeText(publicConfig.senderId);
  if (!username || !apiKey) {
    throw createError(400, "Africa's Talking credentials are not configured");
  }
  const form = new URLSearchParams();
  form.set('username', username);
  form.set('to', normalizePhone(recipient, { plus: true }));
  form.set('message', body);
  if (from) {
    form.set('from', from);
  }
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      apiKey,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: form.toString(),
  });
  const result = await readMaybeJson(response);
  if (!response.ok) {
    throw createError(
      response.status,
      result?.SMSMessageData?.Message || result?.message || 'SMS send failed',
    );
  }
  return result;
}

async function insertMessageLog({
  businessId,
  userId,
  channel,
  mode,
  provider,
  recipient,
  body,
  status,
  metadata,
}) {
  const id = crypto.randomUUID();
  const result = await query(
    `
    INSERT INTO message_send_logs (
      id,
      business_id,
      user_id,
      channel,
      mode,
      provider,
      recipient,
      body,
      status,
      metadata_json,
      created_at,
      updated_at
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, NOW(), NOW())
    RETURNING *
    `,
    [
      id,
      businessId,
      normalizeText(userId),
      channel,
      mode,
      provider,
      recipient,
      body,
      status,
      JSON.stringify(metadata || {}),
    ],
  );
  return normalizeMessageLogRow(result.rows[0]);
}

async function updateMessageLog(id, { status, errorMessage = null, metadata = {} }) {
  const result = await query(
    `
    UPDATE message_send_logs
    SET status = $2,
        error_message = $3,
        metadata_json = metadata_json || $4::jsonb,
        updated_at = NOW()
    WHERE id = $1
    RETURNING *
    `,
    [id, status, errorMessage, JSON.stringify(metadata || {})],
  );
  return normalizeMessageLogRow(result.rows[0]);
}

function normalizeGatewayInput(input, existing = {}) {
  const raw = input && typeof input === 'object' ? input : {};
  return {
    provider: normalizeProvider(raw.provider ?? existing.provider),
    displayName:
      normalizeText(raw.displayName ?? raw.display_name) ||
      existing.displayName ||
      gatewayLabel(existing.provider),
    isActive:
      raw.isActive == null && raw.is_active == null
        ? existing.isActive ?? false
        : Boolean(raw.isActive ?? raw.is_active),
    countries: normalizeCountryList(raw.countries ?? existing.countries ?? []),
    publicConfig: normalizeConfigObject(
      raw.publicConfig ?? raw.public_config ?? {},
      existing.publicConfig || {},
      { secret: false },
    ),
    secretConfig: normalizeConfigObject(
      raw.secretConfig ?? raw.secret_config ?? {},
      existing.secretConfig || {},
      { secret: true },
    ),
  };
}

function normalizeGatewayRow(row, { includeSecrets = false } = {}) {
  const secretConfig = parseJson(row.secret_config_json, {});
  return {
    provider: normalizeProvider(row.provider),
    displayName: row.display_name || gatewayLabel(row.provider),
    isActive: Boolean(row.is_active),
    countries: normalizeCountryList(parseJson(row.countries_json, [])),
    publicConfig: parseJson(row.public_config_json, {}),
    secretConfig: includeSecrets ? secretConfig : maskConfigObject(secretConfig),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeBusinessSettingsRow(row, { includeSecrets = false } = {}) {
  const status = normalizeWhatsAppStatus(
    row.whatsapp_api_status || (row.whatsapp_phone_number_id ? 'connected' : ''),
  );
  const normalized = {
    businessId: row.business_id,
    whatsappNumber: row.whatsapp_number || '',
    smsSenderId: row.sms_sender_id || '',
    allowApiSend: row.allow_api_send !== false,
    whatsappApiStatus: status,
    whatsappConnected: status === 'connected' && Boolean(row.whatsapp_phone_number_id),
    whatsappWabaId: row.whatsapp_waba_id || '',
    whatsappPhoneNumberId: row.whatsapp_phone_number_id || '',
    whatsappDisplayPhoneNumber: row.whatsapp_display_phone_number || '',
    whatsappBusinessName: row.whatsapp_business_name || '',
    whatsappConnectedAt: toIsoString(row.whatsapp_connected_at),
    whatsappLastError: row.whatsapp_last_error || '',
    updatedAt: toIsoString(row.updated_at),
  };
  if (includeSecrets) {
    normalized.whatsappAccessToken = row.whatsapp_access_token || '';
  }
  return normalized;
}

async function ensureBusinessCommunicationColumns(target) {
  const columns = [
    ["whatsapp_api_status", "text NOT NULL DEFAULT 'not_connected'"],
    ['whatsapp_waba_id', 'text'],
    ['whatsapp_phone_number_id', 'text'],
    ['whatsapp_display_phone_number', 'text'],
    ['whatsapp_business_name', 'text'],
    ['whatsapp_access_token', 'text'],
    ['whatsapp_connected_at', 'timestamptz'],
    ['whatsapp_last_error', 'text'],
  ];
  for (const [column, definition] of columns) {
    await runQuery(
      target,
      `ALTER TABLE business_communication_settings ADD COLUMN IF NOT EXISTS ${column} ${definition}`,
    );
  }
}

function normalizeMessageLogRow(row) {
  return {
    id: row.id,
    businessId: row.business_id,
    userId: row.user_id,
    channel: row.channel,
    mode: row.mode,
    provider: row.provider,
    recipient: row.recipient,
    body: row.body,
    status: row.status,
    errorMessage: row.error_message,
    metadata: parseJson(row.metadata_json, {}),
    createdAt: toIsoString(row.created_at),
    updatedAt: toIsoString(row.updated_at),
  };
}

function normalizeConfigObject(input, existing = {}, { secret = false } = {}) {
  const raw = input && typeof input === 'object' && !Array.isArray(input) ? input : {};
  const normalized = { ...existing };
  for (const [key, value] of Object.entries(raw)) {
    const cleanKey = normalizeText(key);
    if (!cleanKey) continue;
    if (secret && typeof value === 'string' && value.startsWith(SECRET_MASK_PREFIX)) {
      continue;
    }
    if (value === null || value === undefined) {
      delete normalized[cleanKey];
      continue;
    }
    normalized[cleanKey] = typeof value === 'string' ? value.trim() : value;
  }
  return normalized;
}

function normalizeConfigFlag(value) {
  if (value === true) return true;
  if (value === false || value == null) return false;
  const clean = normalizeText(value).toLowerCase();
  return clean === 'true' || clean === 'yes' || clean === '1' || clean === 'on';
}

function maskConfigObject(input = {}) {
  return Object.fromEntries(
    Object.entries(input).map(([key, value]) => [
      key,
      value ? `${SECRET_MASK_PREFIX}${String(value).slice(-4)}` : '',
    ]),
  );
}

function normalizeCountryList(input) {
  const list = Array.isArray(input)
    ? input
    : String(input || '')
        .split(',')
        .map((item) => item.trim());
  return Array.from(
    new Set(
      list
        .map((item) => normalizeCountryCode(item))
        .filter((item) => item && item.length > 0),
    ),
  );
}

function normalizeProvider(value) {
  return normalizeText(value)?.toLowerCase().replace(/[^a-z0-9_]+/g, '_') || '';
}

function normalizeChannel(value) {
  const clean = normalizeProvider(value);
  return clean === 'sms' ? 'sms' : 'whatsapp';
}

function normalizeWhatsAppStatus(value) {
  const clean = normalizeProvider(value);
  if (clean === 'connected' || clean === 'pending' || clean === 'error') {
    return clean;
  }
  return 'not_connected';
}

function normalizeText(value) {
  if (value == null) return null;
  const normalized = String(value).trim();
  return normalized || null;
}

function hashConnectSessionToken(token) {
  const clean = normalizeText(token);
  return clean ? crypto.createHash('sha256').update(clean).digest('hex') : null;
}

function normalizePhone(value, { plus = false } = {}) {
  const raw = String(value || '').trim();
  if (!raw) return raw;
  const digits = raw.replace(/[^\d]/g, '');
  if (plus && digits.startsWith('254')) {
    return `+${digits}`;
  }
  return plus && raw.startsWith('+') ? raw : digits || raw;
}

function gatewayLabel(provider) {
  switch (normalizeProvider(provider)) {
    case 'whatsapp':
      return 'WhatsApp API';
    case 'africas_talking':
      return "Africa's Talking SMS";
    default:
      return provider || 'Message Gateway';
  }
}

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch (_) {
    return fallback;
  }
}

function toIsoString(value) {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

async function readMaybeJson(response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    return { raw: text };
  }
}

function createError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function runQuery(target, text, params) {
  if (typeof target === 'function') {
    return target(text, params);
  }
  return target.query(text, params);
}

module.exports = {
  ensureCommunicationSchema,
  listMessageGateways,
  loadMessageGateway,
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
};
