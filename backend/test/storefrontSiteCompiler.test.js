const test = require('node:test');
const assert = require('node:assert/strict');

const {
  compileStorefrontSitePackage,
  defaultStorefrontSitePackage,
} = require('../src/storefrontSiteCompiler');

test('site compiler accepts a genuinely custom category-sidebar structure', () => {
  const compiled = compileStorefrontSitePackage({
    name: 'Editorial sidebar store',
    summary: 'Categories stay beside the live product catalogue.',
    html: `
      <div class="shell">
        <header><piki-brand></piki-brand><piki-cart-button></piki-cart-button></header>
        <main class="catalog-shell">
          <aside><piki-categories></piki-categories></aside>
          <section><piki-search></piki-search><piki-products></piki-products></section>
        </main>
      </div>`,
    css: '.catalog-shell { display:grid; grid-template-columns:240px 1fr; gap:48px; }',
  });

  assert.equal(compiled.security.passed, true);
  assert.equal(compiled.compilerVersion, 'piki-site-1');
  assert.match(compiled.codeHash, /^[a-f0-9]{64}$/);
  assert.deepEqual(compiled.slots, [
    'piki-brand',
    'piki-categories',
    'piki-search',
    'piki-products',
    'piki-cart-button',
  ]);
  assert.equal(compiled.pageSlots.includes('piki-page-content'), true);
  assert.match(compiled.pageHtml, /piki-page-content/);
});

test('site compiler creates a complete safe starter from live business context', () => {
  const compiled = defaultStorefrontSitePackage({ businessName: 'Piki Retail' });
  assert.match(compiled.name, /Piki Retail/);
  assert.match(compiled.html, /<aside class="category-sidebar">/);
  assert.equal(compiled.slots.includes('piki-products'), true);
  assert.equal(compiled.slots.includes('piki-store-intro'), true);
  assert.equal(compiled.slots.includes('piki-cover'), true);
});

test('site compiler rejects executable, document-level, form, and network code', async (t) => {
  const unsafePackages = [
    ['script', '<script>alert(1)</script>', '.shop{}'],
    ['closing script boundary', '<div></script><piki-products></piki-products></div>', '.shop{}'],
    ['form', '<form><piki-products></piki-products></form>', '.shop{}'],
    ['inline handler', '<div onclick="run()"><piki-products></piki-products></div>', '.shop{}'],
    ['inline style', '<div style="color:red"><piki-products></piki-products></div>', '.shop{}'],
    ['document style tag', '<style>.x{}</style><piki-products></piki-products>', '.shop{}'],
    ['external link', '<a href="https://example.com">Leave</a><piki-products></piki-products>', '.shop{}'],
    ['legacy background URL', '<table background="https://example.com/pixel"><tr><td></td></tr></table><piki-products></piki-products>', '.shop{}'],
    ['external CSS asset', '<piki-products></piki-products>', '.hero{background:url(https://example.com/a.png)}'],
    ['external CSS image set', '<piki-products></piki-products>', '.hero{background-image:image-set("https://example.com/a.png" 1x)}'],
  ];

  for (const [name, html, css] of unsafePackages) {
    await t.test(name, () => {
      assert.throws(
        () => compileStorefrontSitePackage({ html, css }),
        (error) => error.statusCode === 400,
      );
    });
  }
});

test('site compiler requires exactly one trusted product catalogue binding', () => {
  assert.throws(
    () => compileStorefrontSitePackage({ html: '<main>Nothing here</main>', css: 'main{}' }),
    /exactly one/i,
  );
  assert.throws(
    () => compileStorefrontSitePackage({
      html: '<piki-products></piki-products><piki-products></piki-products>',
      css: 'piki-products{}',
    }),
    /exactly one/i,
  );
  assert.throws(
    () => compileStorefrontSitePackage({
      html: '<main><piki-products></main>',
      css: 'main{}',
    }),
    /paired or self-closing/i,
  );
});

test('site compiler rejects unsupported bindings but permits local page anchors', () => {
  const compiled = compileStorefrontSitePackage({
    html: '<a href="#catalog">Shop</a><section id="catalog"><piki-products></piki-products></section>',
    css: 'section{display:block}',
  });
  assert.equal(compiled.security.passed, true);
  assert.throws(
    () => compileStorefrontSitePackage({
      html: '<piki-reviews></piki-reviews><piki-products></piki-products>',
      css: 'main{}',
    }),
    /Unsupported Piki binding/i,
  );
});

test('site compiler security-checks the matching custom-page shell', () => {
  assert.throws(
    () => compileStorefrontSitePackage({
      html: '<piki-products></piki-products>',
      pageHtml:
        '<piki-page-content></piki-page-content><script>steal()</script>',
      css: 'main{}',
    }),
    /scripts are not allowed/i,
  );
  assert.throws(
    () => compileStorefrontSitePackage({
      html: '<piki-products></piki-products>',
      pageHtml: '<main>No live page binding</main>',
      css: 'main{}',
    }),
    /exactly one.*piki-page-content/i,
  );
});
