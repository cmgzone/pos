const test = require('node:test');
const assert = require('node:assert/strict');

const {
  isRetryableOpenRouterFailure,
  requestOpenRouterJson,
  userFacingOpenRouterMessage,
} = require('../src/openRouterJson');

function response(status, body) {
  return {
    status,
    ok: status >= 200 && status < 300,
    async text() {
      return JSON.stringify(body);
    },
  };
}

test('marketing JSON request falls back when the selected provider fails', async () => {
  const requests = [];
  const fetchImpl = async (_url, options) => {
    const requestBody = JSON.parse(options.body);
    requests.push(requestBody);
    if (requestBody.model === 'tencent/hy3:free') {
      return response(502, { error: { message: 'Provider returned error' } });
    }
    return response(200, {
      model: 'openai/gpt-oss-20b:free',
      choices: [{ message: { content: '{"campaignName":"Ready"}' } }],
    });
  };

  const result = await requestOpenRouterJson({
    fetchImpl,
    baseUrl: 'https://openrouter.example/api/v1',
    apiKey: 'test-key',
    model: 'tencent/hy3:free',
    fallbackModel: 'openrouter/free',
    messages: [{ role: 'user', content: 'Write JSON' }],
    maxTokens: 100,
    temperature: 0,
    title: 'Test',
    isUsableBody: (body) => Boolean(body.choices?.[0]?.message?.content),
    logger: { warn() {} },
  });

  assert.deepEqual(requests.map((item) => item.model), [
    'tencent/hy3:free',
    'openrouter/free',
  ]);
  assert.equal(result.usedFallback, true);
  assert.equal(result.resolvedModel, 'openai/gpt-oss-20b:free');
});

test('request retries the same model without JSON mode when unsupported', async () => {
  const requests = [];
  const fetchImpl = async (_url, options) => {
    const requestBody = JSON.parse(options.body);
    requests.push(requestBody);
    if (requests.length === 1) {
      return response(400, {
        error: { message: 'response_format json_object is not supported' },
      });
    }
    return response(200, {
      choices: [{ message: { content: '{"ok":true}' } }],
    });
  };

  const result = await requestOpenRouterJson({
    fetchImpl,
    baseUrl: 'https://openrouter.example/api/v1/',
    apiKey: 'test-key',
    model: 'example/model',
    fallbackModel: 'openrouter/free',
    messages: [],
    maxTokens: 100,
    temperature: 0,
    isUsableBody: (body) => Boolean(body.choices?.[0]?.message?.content),
    logger: { warn() {} },
  });

  assert.equal(requests.length, 2);
  assert.equal(requests[0].response_format.type, 'json_object');
  assert.equal('response_format' in requests[1], false);
  assert.equal(result.usedFallback, false);
});

test('invalid successful response also uses the backup router', async () => {
  const requests = [];
  const fetchImpl = async (_url, options) => {
    const requestBody = JSON.parse(options.body);
    requests.push(requestBody);
    if (requestBody.model === 'primary/model') {
      return response(200, {
        choices: [{ finish_reason: 'length', message: { content: '' } }],
      });
    }
    return response(200, {
      choices: [{ message: { content: '{"ok":true}' } }],
    });
  };

  const result = await requestOpenRouterJson({
    fetchImpl,
    baseUrl: 'https://openrouter.example/api/v1',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'openrouter/free',
    messages: [],
    maxTokens: 100,
    temperature: 0,
    isUsableBody: (body) => Boolean(body.choices?.[0]?.message?.content),
    logger: { warn() {} },
  });

  assert.equal(requests.length, 2);
  assert.equal(result.usedFallback, true);
  assert.equal(result.attempts[0].finishReason, 'length');
});

test('network failures use the backup router', async () => {
  const requests = [];
  const fetchImpl = async (_url, options) => {
    const requestBody = JSON.parse(options.body);
    requests.push(requestBody);
    if (requestBody.model === 'primary/model') {
      throw new Error('socket disconnected');
    }
    return response(200, {
      choices: [{ message: { content: '{"ok":true}' } }],
    });
  };

  const result = await requestOpenRouterJson({
    fetchImpl,
    baseUrl: 'https://openrouter.example/api/v1',
    apiKey: 'test-key',
    model: 'primary/model',
    fallbackModel: 'openrouter/free',
    messages: [],
    maxTokens: 100,
    temperature: 0,
    isUsableBody: (body) => Boolean(body.choices?.[0]?.message?.content),
    logger: { warn() {} },
  });

  assert.deepEqual(requests.map((item) => item.model), [
    'primary/model',
    'openrouter/free',
  ]);
  assert.equal(result.usedFallback, true);
});

test('provider failures are classified and translated for the user', () => {
  assert.equal(
    isRetryableOpenRouterFailure(502, {
      error: { message: 'Provider returned error' },
    }),
    true,
  );
  assert.equal(
    userFacingOpenRouterMessage(502, {
      error: { message: 'Provider returned error' },
    }),
    "Piki's AI providers are temporarily unavailable. Please retry shortly.",
  );
  assert.doesNotMatch(
    userFacingOpenRouterMessage(502, {
      error: { message: 'Provider returned error' },
    }),
    /Provider returned error/,
  );
});
