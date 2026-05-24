const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeSerpApiResponse,
  normalizeWebSearchInput,
  searchWithSerpApi,
} = require('../src/serpApi');

test('normalizes web search input', () => {
  const input = normalizeWebSearchInput({
    query: '  maize flour price Kenya  ',
    location: ' Nairobi, Kenya ',
    countryCode: 'KE',
    language: 'EN',
    limit: 50,
  });

  assert.deepEqual(input, {
    query: 'maize flour price Kenya',
    location: 'Nairobi, Kenya',
    gl: 'KE',
    hl: 'EN',
    limit: 10,
  });
});

test('normalizes SerpAPI response into safe web results', () => {
  const result = normalizeSerpApiResponse(
    {
      search_metadata: { id: 'abc', status: 'Success' },
      answer_box: {
        title: 'Quick answer',
        answer: 'KES 200',
        link: 'https://example.com/answer',
      },
      organic_results: [
        {
          position: 1,
          title: 'Maize flour prices',
          link: 'https://example.com/prices',
          snippet: 'Retail prices today',
          source: 'Example',
          displayed_link: 'example.com',
        },
      ],
      related_questions: [{ question: 'What is unga?', snippet: 'Flour' }],
    },
    { query: 'maize flour price Kenya', limit: 5, location: 'Kenya' },
  );

  assert.equal(result.type, 'web_search');
  assert.equal(result.success, true);
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].title, 'Maize flour prices');
  assert.equal(result.answerBox.answer, 'KES 200');
  assert.equal(result.relatedQuestions[0].question, 'What is unga?');
});

test('searchWithSerpApi calls the Google engine with protected key', async () => {
  let requestedUrl;
  let requestedOptions;
  const result = await searchWithSerpApi({
    apiKey: 'secret-key',
    baseUrl: 'https://serpapi.com/search.json',
    input: {
      query: 'VAT Kenya 2026',
      countryCode: 'KE',
      language: 'en',
      limit: 3,
    },
    fetchImpl: async (url, options) => {
      requestedUrl = url;
      requestedOptions = options;
      return {
        ok: true,
        status: 200,
        json: async () => ({
          searchParameters: { status: 'Success' },
          organic: [
            {
              title: 'VAT guide',
              link: 'https://example.com/vat',
              snippet: 'Tax guide',
            },
          ],
        }),
      };
    },
  });

  const url = new URL(requestedUrl);
  assert.equal(requestedOptions.method, 'GET');
  assert.equal(url.origin + url.pathname, 'https://serpapi.com/search.json');
  assert.equal(url.searchParams.get('engine'), 'google');
  assert.equal(url.searchParams.get('api_key'), 'secret-key');
  assert.equal(url.searchParams.get('q'), 'VAT Kenya 2026');
  assert.equal(url.searchParams.get('gl'), 'ke');
  assert.equal(url.searchParams.get('hl'), 'en');
  assert.equal(url.searchParams.get('num'), '3');
  assert.equal(result.results.length, 1);
});
