const { isUnsupportedJsonModeResponse } = require('./storefrontThemeAi');

const DEFAULT_OPENROUTER_FALLBACK_MODEL = 'openrouter/free';
const RETRYABLE_STATUSES = new Set([408, 425, 429, 500, 502, 503, 504]);

async function requestOpenRouterJson({
  fetchImpl,
  baseUrl,
  apiKey,
  model,
  fallbackModel = DEFAULT_OPENROUTER_FALLBACK_MODEL,
  messages,
  maxTokens,
  temperature,
  title,
  responseFormat = { type: 'json_object' },
  isUsableBody,
  timeoutMs = 60000,
  logger = console,
}) {
  const primaryModel = normalizeModel(model) || 'openai/gpt-4o-mini';
  const backupModel = normalizeModel(fallbackModel);
  const candidateModels = [primaryModel];
  if (backupModel && backupModel !== primaryModel) {
    candidateModels.push(backupModel);
  } else if (backupModel === DEFAULT_OPENROUTER_FALLBACK_MODEL) {
    // The free router can select a different provider/model on another request.
    candidateModels.push(backupModel);
  }

  const attempts = [];
  let lastResult = null;
  let lastBodyWasInvalid = false;

  for (let index = 0; index < candidateModels.length; index += 1) {
    const candidateModel = candidateModels[index];
    let result = await sendOpenRouterRequest({
      fetchImpl,
      baseUrl,
      apiKey,
      model: candidateModel,
      messages,
      maxTokens,
      temperature,
      title,
      responseFormat,
      timeoutMs,
    });
    attempts.push(summarizeAttempt(candidateModel, true, result));

    if (
      !result.response.ok &&
      isUnsupportedJsonModeResponse(result.response.status, result.body)
    ) {
      result = await sendOpenRouterRequest({
        fetchImpl,
        baseUrl,
        apiKey,
        model: candidateModel,
        messages,
        maxTokens,
        temperature,
        title,
        responseFormat: null,
        timeoutMs,
      });
      attempts.push(summarizeAttempt(candidateModel, false, result));
    }

    lastResult = result;
    if (result.response.ok) {
      const usable =
        typeof isUsableBody !== 'function' || isUsableBody(result.body);
      if (usable) {
        return {
          body: result.body,
          requestedModel: candidateModel,
          resolvedModel: normalizeModel(result.body?.model) || candidateModel,
          usedFallback: index > 0,
          attempts,
        };
      }
      lastBodyWasInvalid = true;
      logAttemptFailure(logger, candidateModel, result, 'empty_or_invalid_body');
      continue;
    }

    logAttemptFailure(logger, candidateModel, result, 'provider_error');
    if (!isRetryableOpenRouterFailure(result.response.status, result.body)) {
      break;
    }
  }

  if (lastBodyWasInvalid && lastResult?.response?.ok) {
    throw openRouterError(
      502,
      'Piki AI returned an incomplete response. Please retry shortly.',
      lastResult,
      attempts,
    );
  }

  const status = Number(lastResult?.response?.status || 502);
  throw openRouterError(
    status === 401 ? 502 : status,
    userFacingOpenRouterMessage(status, lastResult?.body),
    lastResult,
    attempts,
  );
}

async function sendOpenRouterRequest({
  fetchImpl,
  baseUrl,
  apiKey,
  model,
  messages,
  maxTokens,
  temperature,
  title,
  responseFormat,
  timeoutMs,
}) {
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    Math.max(1000, Number(timeoutMs) || 60000),
  );
  try {
    const response = await fetchImpl(
      `${String(baseUrl).replace(/\/+$/, '')}/chat/completions`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://pikipos.com',
          'X-Title': title || 'Piki POS AI',
        },
        body: JSON.stringify({
          model,
          messages,
          ...(responseFormat ? { response_format: responseFormat } : {}),
          max_tokens: maxTokens,
          temperature,
        }),
        signal: controller.signal,
      },
    );
    return { response, body: await readMaybeJsonResponse(response) };
  } catch (error) {
    const timedOut = error?.name === 'AbortError';
    return {
      response: { ok: false, status: timedOut ? 504 : 503 },
      body: {
        error: {
          message: timedOut
            ? 'Provider request timed out'
            : 'Provider network request failed',
        },
      },
      cause: error,
    };
  } finally {
    clearTimeout(timer);
  }
}

async function readMaybeJsonResponse(response) {
  const text = await response.text();
  if (!text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    return { message: text.trim().slice(0, 500) };
  }
}

function isRetryableOpenRouterFailure(status, body) {
  if (RETRYABLE_STATUSES.has(Number(status))) return true;
  const message = providerMessage(body).toLowerCase();
  return /provider returned error|provider unavailable|no endpoints found|temporar(?:y|ily)|overloaded|rate.?limit|timed? out|timeout|upstream/.test(
    message,
  );
}

function userFacingOpenRouterMessage(status, body) {
  const numericStatus = Number(status);
  if (numericStatus === 401 || numericStatus === 403) {
    return 'Piki AI credentials need attention. Ask the platform administrator to reconnect OpenRouter.';
  }
  if (numericStatus === 402) {
    return 'Piki AI provider credits are unavailable. Ask the platform administrator to review OpenRouter billing.';
  }
  if (numericStatus === 429) {
    return 'Piki AI is busy right now. Please retry in a few minutes.';
  }
  if (isRetryableOpenRouterFailure(numericStatus, body)) {
    return "Piki's AI providers are temporarily unavailable. Please retry shortly.";
  }
  if (numericStatus === 400) {
    return 'Piki AI could not process this request. Please simplify the brief and retry.';
  }
  return 'Piki could not generate the marketing pack. Please retry shortly.';
}

function providerMessage(body) {
  return String(body?.error?.message || body?.message || body?.error || '').trim();
}

function summarizeAttempt(model, jsonMode, result) {
  return {
    model,
    jsonMode,
    status: Number(result.response.status || 0),
    ok: Boolean(result.response.ok),
  };
}

function logAttemptFailure(logger, model, result, reason) {
  if (!logger || typeof logger.warn !== 'function') return;
  const message = providerMessage(result.body).replace(/\s+/g, ' ').slice(0, 180);
  logger.warn(
    `[openrouter] ${reason} model=${model} status=${result.response.status}` +
      (message ? ` message=${message}` : ''),
  );
}

function openRouterError(statusCode, message, result, attempts) {
  const error = new Error(message);
  error.statusCode = statusCode;
  error.openRouterStatus = Number(result?.response?.status || 0);
  error.openRouterMessage = providerMessage(result?.body);
  error.openRouterAttempts = attempts;
  return error;
}

function normalizeModel(value) {
  return value == null ? '' : String(value).trim();
}

module.exports = {
  DEFAULT_OPENROUTER_FALLBACK_MODEL,
  isRetryableOpenRouterFailure,
  requestOpenRouterJson,
  userFacingOpenRouterMessage,
};
