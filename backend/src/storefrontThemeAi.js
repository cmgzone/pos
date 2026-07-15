const {
  normalizeStorefrontCheckout,
  normalizeStorefrontThemeDesign,
  presetStorefrontTheme,
} = require('./storefrontThemes');

function extractStorefrontAiContent(body) {
  const message = body?.choices?.[0]?.message || {};
  const toolArguments =
    message?.tool_calls?.[0]?.function?.arguments ??
    message?.function_call?.arguments;
  if (toolArguments && typeof toolArguments === 'object') {
    return JSON.stringify(toolArguments);
  }
  if (typeof toolArguments === 'string' && toolArguments.trim()) {
    return toolArguments.trim();
  }

  const content = message.content;
  if (content && typeof content === 'object' && !Array.isArray(content)) {
    return JSON.stringify(content);
  }
  if (typeof content === 'string') return content.trim();
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === 'string') return part;
        if (typeof part?.text === 'string') return part.text;
        if (part?.json && typeof part.json === 'object') {
          return JSON.stringify(part.json);
        }
        if (typeof part?.content === 'string') return part.content;
        return '';
      })
      .filter(Boolean)
      .join('\n')
      .trim();
  }
  return '';
}

function parseStorefrontAiThemeResponse(value, theme = {}) {
  const parsed = parseJsonValue(value);
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return null;
  }
  const candidate = objectValue(
    parsed.theme ?? parsed.data ?? parsed.result ?? parsed,
  );
  const designInput = objectOrNull(candidate.design);
  const checkoutInput = objectOrNull(candidate.checkout);
  if (!designInput && !checkoutInput) return null;

  return {
    name: limitText(candidate.name, 80) || theme.name || 'Piki storefront',
    summary:
      limitText(candidate.summary, 240) ||
      'Piki prepared a storefront theme draft for review.',
    design: normalizeStorefrontThemeDesign(designInput || {}, theme.design || {}),
    checkout: normalizeStorefrontCheckout(
      checkoutInput || {},
      theme.checkout || {},
    ),
    usedFallback: false,
  };
}

function fallbackStorefrontAiTheme(theme = {}, instruction = '') {
  const request = String(instruction || '').trim().toLowerCase();
  const storefrontType = theme.storefrontType || 'retail';
  let preset = null;
  if (/\b(minimal|clean|simple|light|white)\b/.test(request)) {
    preset = 'minimal';
  } else if (/\b(warm|earth|earthy|cozy|rustic)\b/.test(request)) {
    preset = 'warm';
  } else if (/\b(fresh|green|teal|natural)\b/.test(request)) {
    preset = 'fresh';
  } else if (/\b(bold|vibrant|pink|statement)\b/.test(request)) {
    preset = 'bold';
  } else if (/\b(dark|studio|premium|luxury)\b/.test(request)) {
    preset = 'studio';
  }

  const design = {
    ...(theme.design || {}),
    ...(preset
      ? presetStorefrontTheme(preset, { storefrontType }).design
      : {}),
  };
  setEnumFromRequest(design, 'imageRatio', request, [
    'square',
    'portrait',
    'landscape',
  ]);
  setEnumFromRequest(design, 'heroStyle', request, [
    'cover',
    'split',
    'minimal',
  ]);
  setEnumFromRequest(design, 'cardStyle', request, [
    'bordered',
    'elevated',
    'minimal',
  ]);
  setEnumFromRequest(design, 'cornerStyle', request, [
    'sharp',
    'soft',
    'rounded',
    'pill',
  ]);
  setEnumFromRequest(design, 'density', request, ['compact', 'comfortable']);
  setEnumFromRequest(design, 'fontFamily', request, [
    'inter',
    'modern',
    'serif',
    'rounded',
    'system',
  ]);
  const requestedColor = request.match(/#[0-9a-f]{6}\b/i)?.[0];
  if (requestedColor) design.accentColor = requestedColor.toLowerCase();

  return {
    name: limitText(theme.name, 80) || 'Piki storefront',
    summary:
      'Piki applied a safe storefront draft after the model returned an invalid format.',
    design: normalizeStorefrontThemeDesign(design, theme.design || {}),
    checkout: normalizeStorefrontCheckout({}, theme.checkout || {}),
    usedFallback: true,
  };
}

function storefrontJsonResponseFormat() {
  return { type: 'json_object' };
}

function isUnsupportedJsonModeResponse(status, body) {
  if (status !== 400) return false;
  const message = String(
    body?.error?.message ?? body?.message ?? body?.error ?? '',
  ).toLowerCase();
  return /response[_ -]?format|json mode|structured output|json_object/.test(
    message,
  );
}

function parseJsonValue(input, depth = 0) {
  if (depth > 2 || input == null) return null;
  if (Array.isArray(input)) {
    return input.find((item) => item && typeof item === 'object') || null;
  }
  if (typeof input === 'object') return input;

  const normalized = String(input).replace(/^\uFEFF/, '').trim();
  if (!normalized) return null;
  const candidates = [normalized];
  for (const match of normalized.matchAll(/```(?:json)?\s*([\s\S]*?)\s*```/gi)) {
    candidates.push(match[1].trim());
  }
  candidates.push(...balancedJsonSlices(normalized));

  for (const candidate of [...new Set(candidates)]) {
    for (const version of [candidate, repairCommonJson(candidate)]) {
      try {
        const parsed = JSON.parse(version);
        if (typeof parsed === 'string') {
          const nested = parseJsonValue(parsed, depth + 1);
          if (nested) return nested;
        }
        if (Array.isArray(parsed)) {
          const object = parsed.find(
            (item) => item && typeof item === 'object' && !Array.isArray(item),
          );
          if (object) return object;
        }
        if (parsed && typeof parsed === 'object') return parsed;
      } catch (_) {
        // Try the next isolated or repaired candidate.
      }
    }
  }
  return null;
}

function balancedJsonSlices(text) {
  const slices = [];
  for (let start = 0; start < text.length; start += 1) {
    if (text[start] !== '{' && text[start] !== '[') continue;
    const stack = [];
    let quote = null;
    let escaped = false;
    for (let index = start; index < text.length; index += 1) {
      const char = text[index];
      if (quote) {
        if (escaped) {
          escaped = false;
        } else if (char === '\\') {
          escaped = true;
        } else if (char === quote) {
          quote = null;
        }
        continue;
      }
      if (char === '"') {
        quote = char;
      } else if (char === '{' || char === '[') {
        stack.push(char);
      } else if (char === '}' || char === ']') {
        const expected = char === '}' ? '{' : '[';
        if (stack.pop() !== expected) break;
        if (stack.length === 0) {
          slices.push(text.slice(start, index + 1));
          start = index;
          break;
        }
      }
    }
  }
  return slices;
}

function repairCommonJson(value) {
  return value
    .replace(/[“”]/g, '"')
    .replace(/,\s*([}\]])/g, '$1')
    .trim();
}

function setEnumFromRequest(target, key, request, values) {
  const match = values.find((value) =>
    new RegExp(`\\b${value}\\b`, 'i').test(request),
  );
  if (match) target[key] = match;
}

function objectOrNull(value) {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value
    : null;
}

function objectValue(value) {
  return objectOrNull(value) || {};
}

function limitText(value, maxLength) {
  const clean = value == null ? '' : String(value).trim();
  return clean ? clean.slice(0, maxLength) : '';
}

module.exports = {
  extractStorefrontAiContent,
  fallbackStorefrontAiTheme,
  isUnsupportedJsonModeResponse,
  parseStorefrontAiThemeResponse,
  storefrontJsonResponseFormat,
};
