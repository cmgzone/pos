const DEFAULT_OAUTH_URL =
  'https://idp.flutterwave.com/realms/flutterwave/protocol/openid-connect/token';

async function requestFlutterwaveV4AccessToken({
  clientId,
  clientSecret,
  oauthUrl = DEFAULT_OAUTH_URL,
  fetchImpl,
}) {
  const cleanClientId = String(clientId || '').trim();
  const cleanClientSecret = String(clientSecret || '').trim();
  const cleanOauthUrl = String(oauthUrl || '').trim();
  if (!cleanClientId || !cleanClientSecret) {
    throw new Error('Flutterwave v4 Client ID and Client Secret are required.');
  }
  if (!isHttpsUrl(cleanOauthUrl)) {
    throw new Error('Flutterwave v4 OAuth URL must be a valid HTTPS URL.');
  }
  const fetch = fetchImpl || (await import('node-fetch')).default;
  const response = await fetch(cleanOauthUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: cleanClientId,
      client_secret: cleanClientSecret,
      grant_type: 'client_credentials',
    }).toString(),
  });
  const body = await readMaybeJson(response);
  if (!response.ok || !body.access_token) {
    throw new Error(
      body.error_description ||
        body.message ||
        body.error ||
        'Flutterwave v4 authentication failed.',
    );
  }
  return {
    accessToken: String(body.access_token),
    expiresIn: Number(body.expires_in || 0),
    tokenType: String(body.token_type || 'Bearer'),
  };
}

async function readMaybeJson(response) {
  try {
    return await response.json();
  } catch (_) {
    return {};
  }
}

function isHttpsUrl(value) {
  try {
    return new URL(String(value || '')).protocol === 'https:';
  } catch (_) {
    return false;
  }
}

module.exports = {
  DEFAULT_OAUTH_URL,
  requestFlutterwaveV4AccessToken,
};
