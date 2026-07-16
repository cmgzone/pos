const test = require('node:test');
const assert = require('node:assert/strict');

const {
  inspectStorefrontSiteAiBody,
  inspectStorefrontSiteSource,
  storefrontSiteSourceFromBody,
} = require('../src/storefrontSiteAi');

function aiBody(value) {
  return {
    choices: [{ message: { content: JSON.stringify(value) } }],
  };
}

test('site AI accepts wrapped packages and harmless code wrappers', () => {
  const body = aiBody({
    result: JSON.stringify({
      name: 'Warm story store',
      html:
        '```html\n<main><piki-store-intro></piki-store-intro><piki-products></piki-products></main>\n```',
      css: '```css\n<style>main { display: grid; }</style>\n```',
    }),
  });

  const inspected = inspectStorefrontSiteAiBody(body);
  assert.equal(inspected.error, null);
  assert.equal(inspected.compiled.security.passed, true);
  assert.match(inspected.compiled.html, /^<main>/);
  assert.equal(inspected.compiled.css, 'main { display: grid; }');
});

test('site AI reports the exact compiler failure for automatic repair', () => {
  const body = aiBody({
    website: {
      html: '<main><h1>Story</h1></main>',
      css: 'main { display: block; }',
    },
  });

  const inspected = inspectStorefrontSiteAiBody(body);
  assert.equal(inspected.compiled, null);
  assert.match(inspected.error, /exactly one product binding/i);
  assert.match(inspected.source.html, /Story/);
});

test('site AI keeps the server-selected product outside generated code', () => {
  const body = aiBody({
    html: '<main><piki-single-product></piki-single-product></main>',
    css: 'main { display: grid; }',
  });

  const source = storefrontSiteSourceFromBody(body);
  assert.equal('singleProductId' in source, false);
  const inspected = inspectStorefrontSiteAiBody(body, {
    singleProductId: 'product-42',
  });
  assert.equal(inspected.compiled.singleProductId, 'product-42');
});

test('site AI validates independently generated structure and styling', () => {
  const structure = {
    html: '<main><piki-products></piki-products></main>',
    pageHtml: '<main><piki-page-content></piki-page-content></main>',
  };
  const inspected = inspectStorefrontSiteSource({
    ...structure,
    css: 'main { max-width: 80rem; margin: auto; }',
  });

  assert.equal(inspected.error, null);
  assert.equal(inspected.compiled.security.passed, true);
});
