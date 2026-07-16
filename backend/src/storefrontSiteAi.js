const {
  extractStorefrontAiContent,
  parseJsonValue,
} = require('./storefrontThemeAi');
const { compileStorefrontSitePackage } = require('./storefrontSiteCompiler');

const WRAPPER_KEYS = Object.freeze([
  'site',
  'storefront',
  'website',
  'package',
  'data',
  'result',
]);

function inspectStorefrontSiteAiBody(body, options = {}) {
  const source = storefrontSiteSourceFromBody(body);
  if (!source) {
    return {
      source: null,
      compiled: null,
      error: 'The response did not contain a JSON storefront package.',
    };
  }
  try {
    return {
      source,
      compiled: compileStorefrontSitePackage({
        ...source,
        ...(options.singleProductId
          ? { singleProductId: options.singleProductId }
          : {}),
      }),
      error: null,
    };
  } catch (error) {
    return {
      source,
      compiled: null,
      error: limitText(error?.message, 400) || 'The package failed validation.',
    };
  }
}

function storefrontSiteSourceFromBody(body) {
  const parsed = parseJsonValue(extractStorefrontAiContent(body));
  const candidate = unwrapSiteSource(parsed);
  if (!candidate) return null;
  return {
    name: textField(candidate.name),
    summary: textField(candidate.summary),
    html: codeField(candidate.html ?? candidate.markup, 'html'),
    pageHtml:
      codeField(candidate.pageHtml ?? candidate.pageMarkup, 'html') ||
      undefined,
    css: cssField(candidate.css ?? candidate.styles),
  };
}

function compactStorefrontSiteSource(source) {
  if (!source || typeof source !== 'object') return null;
  return {
    name: limitText(source.name, 100),
    summary: limitText(source.summary, 300),
    html: limitText(source.html ?? source.markup, 18_000),
    pageHtml: limitText(source.pageHtml ?? source.pageMarkup, 10_000),
    css: limitText(source.css ?? source.styles, 18_000),
  };
}

function unwrapSiteSource(value) {
  let current = objectValue(value);
  for (let depth = 0; depth < 3; depth += 1) {
    if (hasSiteFields(current)) return current;
    const wrapped = WRAPPER_KEYS.map((key) => parsedObject(current[key])).find(
      (item) => Object.keys(item).length > 0,
    );
    if (!wrapped) break;
    current = wrapped;
  }
  return Object.keys(current).length ? current : null;
}

function hasSiteFields(value) {
  return Boolean(
    value.html || value.markup || value.css || value.styles || value.pageHtml,
  );
}

function codeField(value, language) {
  const text = textField(value);
  if (!text) return '';
  const opening = new RegExp('^\\s*```(?:' + language + ')?\\s*', 'i');
  return text.replace(opening, '').replace(/\s*```\s*$/, '').trim();
}

function cssField(value) {
  const text = codeField(value, 'css');
  const wrapped = text.match(/^\s*<style(?:\s[^>]*)?>([\s\S]*)<\/style>\s*$/i);
  return (wrapped?.[1] ?? text).trim();
}

function textField(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function objectValue(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function parsedObject(value) {
  const direct = objectValue(value);
  if (Object.keys(direct).length) return direct;
  return objectValue(parseJsonValue(value));
}

function limitText(value, maxLength) {
  return String(value ?? '').trim().slice(0, maxLength);
}

module.exports = {
  compactStorefrontSiteSource,
  inspectStorefrontSiteAiBody,
  storefrontSiteSourceFromBody,
};
