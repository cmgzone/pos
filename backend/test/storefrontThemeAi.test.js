const test = require('node:test');
const assert = require('node:assert/strict');

const {
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
