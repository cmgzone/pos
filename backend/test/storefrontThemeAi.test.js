const test = require('node:test');
const assert = require('node:assert/strict');

const {
  applyStorefrontInstructionRequirements,
  extractStorefrontAiContent,
  fallbackStorefrontAiTheme,
  parseStorefrontAiThemeResponse,
} = require('../src/storefrontThemeAi');
const { defaultStorefrontTheme } = require('../src/storefrontThemes');

test('storefront AI parser accepts prose-wrapped fenced JSON and normalizes it', () => {
  const current = defaultStorefrontTheme({ storefrontType: 'retail' });
  const parsed = parseStorefrontAiThemeResponse(
    `Here is the theme:\n\`\`\`json
    {
      "name": "Clean shop",
      "summary": "Made the catalogue lighter.",
      "design": { "backgroundColor": "#ffffff", "imageRatio": "square", },
      "checkout": { "paymentMethods": ["manual"] }
    }
    \`\`\``,
    current,
  );

  assert.equal(parsed.name, 'Clean shop');
  assert.equal(parsed.design.backgroundColor, '#ffffff');
  assert.equal(parsed.design.imageRatio, 'square');
  assert.deepEqual(parsed.checkout.paymentMethods, ['manual']);
  assert.equal(parsed.usedFallback, false);
});

test('storefront AI can build a complete validated section plan from scratch', () => {
  const current = defaultStorefrontTheme({ storefrontType: 'retail' });
  const parsed = parseStorefrontAiThemeResponse(
    JSON.stringify({
      name: 'Complete shop',
      design: { backgroundColor: '#ffffff', accentColor: '#cc3300' },
      sections: [
        {
          id: 'opening',
          type: 'hero',
          title: 'Everything for the week',
          buttonLabel: 'Start shopping',
          buttonAction: 'catalog',
        },
        {
          id: 'offer',
          type: 'promoBanner',
          title: 'Simple online ordering',
          buttonAction: 'whatsapp',
        },
        { id: 'shop', type: 'catalog', title: 'All products' },
      ],
      checkout: { paymentMethods: ['manual'] },
    }),
    current,
    { buildFromScratch: true },
  );

  assert.deepEqual(
    parsed.sections.map((section) => section.type),
    ['hero', 'promoBanner', 'catalog'],
  );
  assert.equal(parsed.sections[0].buttonAction, 'catalog');
  assert.equal(parsed.sections[2].title, 'All products');
});

test('storefront AI content reads tool-call arguments', () => {
  const content = extractStorefrontAiContent({
    choices: [
      {
        message: {
          tool_calls: [
            {
              function: {
                arguments: '{"design":{"cornerStyle":"pill"},"checkout":{}}',
              },
            },
          ],
        },
      },
    ],
  });
  assert.match(content, /cornerStyle/);
});

test('invalid AI prose falls back to a safe requested style', () => {
  const current = defaultStorefrontTheme({ storefrontType: 'services' });
  assert.equal(
    parseStorefrontAiThemeResponse('I made it look great!', current),
    null,
  );

  const fallback = fallbackStorefrontAiTheme(
    current,
    'Make it clean and minimal with square images and pill corners',
  );
  assert.equal(fallback.design.imageRatio, 'square');
  assert.equal(fallback.design.cornerStyle, 'pill');
  assert.equal(fallback.design.heroStyle, 'minimal');
  assert.equal(fallback.usedFallback, true);
});

test('explicit category sidebar request wins without changing unrequested colours', () => {
  const current = defaultStorefrontTheme({ storefrontType: 'retail' });
  const proposal = {
    design: {
      ...current.design,
      backgroundColor: '#ff0000',
      accentColor: '#00ff00',
      catalogLayout: 'topbar',
    },
    sections: current.sections,
    checkout: current.checkout,
  };

  const enforced = applyStorefrontInstructionRequirements(
    proposal,
    'Add the categories in a sidebar on the left',
    current,
  );

  assert.equal(enforced.design.catalogLayout, 'sidebar');
  assert.equal(enforced.design.backgroundColor, current.design.backgroundColor);
  assert.equal(enforced.design.accentColor, current.design.accentColor);
});
