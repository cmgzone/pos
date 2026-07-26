const test = require('node:test');
const assert = require('node:assert/strict');

const {
  DEFAULT_OAUTH_URL,
  requestFlutterwaveV4AccessToken,
} = require('../src/flutterwaveV4');

test('Flutterwave v4 exchanges client credentials without exposing the token', async () => {
  let request;
  const result = await requestFlutterwaveV4AccessToken({
    clientId: 'client-id',
    clientSecret: 'client-secret',
    fetchImpl: async (url, options) => {
      request = { url, options };
      return {
        ok: true,
        async json() {
          return { access_token: 'token-value', expires_in: 600, token_type: 'Bearer' };
        },
      };
    },
  });

  assert.equal(request.url, DEFAULT_OAUTH_URL);
  assert.match(request.options.body, /client_id=client-id/);
  assert.match(request.options.body, /client_secret=client-secret/);
  assert.deepEqual(result, {
    accessToken: 'token-value',
    expiresIn: 600,
    tokenType: 'Bearer',
  });
});

test('Flutterwave v4 reports OAuth credential failures', async () => {
  await assert.rejects(
    requestFlutterwaveV4AccessToken({
      clientId: 'bad-id',
      clientSecret: 'bad-secret',
      fetchImpl: async () => ({
        ok: false,
        async json() {
          return { error_description: 'Invalid client credentials' };
        },
      }),
    }),
    /Invalid client credentials/,
  );
});
