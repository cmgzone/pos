function normalizeWebSearchInput(input = {}) {
  const query = normalizeText(input.query || input.q);
  const location = normalizeText(input.location);
  const gl = normalizeText(input.gl || input.countryCode);
  const hl = normalizeText(input.hl || input.language);
  const limit = clampInt(input.limit, 5, 1, 10);

  return { query, location, gl, hl, limit };
}

async function searchWithSerpApi({
  apiKey,
  fetchImpl,
  baseUrl = 'https://serpapi.com/search.json',
  input,
}) {
  if (!apiKey || !apiKey.trim()) {
    throw new Error('SerpAPI key is not configured');
  }

  const request = normalizeWebSearchInput(input);
  if (!request.query) {
    throw new Error('Search query is required');
  }

  const url = new URL(baseUrl);
  url.searchParams.set('engine', 'google');
  url.searchParams.set('q', request.query);
  url.searchParams.set('api_key', apiKey);
  url.searchParams.set('num', String(request.limit));
  if (request.location) {
    url.searchParams.set('location', request.location);
  }
  if (request.gl) {
    url.searchParams.set('gl', request.gl.toLowerCase());
  }
  if (request.hl) {
    url.searchParams.set('hl', request.hl.toLowerCase());
  }

  const response = await fetchImpl(url);
  const body = await response.json();

  if (!response.ok) {
    throw new Error(
      body?.error || body?.message || `SerpAPI request failed (${response.status})`,
    );
  }
  if (body?.error) {
    throw new Error(body.error);
  }

  return normalizeSerpApiResponse(body, request);
}

function normalizeSerpApiResponse(body, request) {
  const organicResults = Array.isArray(body?.organic_results)
    ? body.organic_results
    : [];
  const results = organicResults.slice(0, request.limit).map((item, index) => ({
    position: Number(item.position || index + 1),
    title: normalizeText(item.title) || 'Result',
    link: normalizeText(item.link),
    snippet: normalizeText(item.snippet),
    source: normalizeText(item.source),
    displayedLink: normalizeText(item.displayed_link),
  }));

  const answerBox = body?.answer_box
    ? {
        title: normalizeText(body.answer_box.title),
        answer:
          normalizeText(body.answer_box.answer) ||
          normalizeText(body.answer_box.snippet),
        link: normalizeText(body.answer_box.link),
      }
    : null;

  const relatedQuestions = Array.isArray(body?.related_questions)
    ? body.related_questions.slice(0, 3).map((item) => ({
        question: normalizeText(item.question),
        answer: normalizeText(item.snippet) || normalizeText(item.answer),
        link: normalizeText(item.link),
      }))
    : [];

  return {
    type: 'web_search',
    success: true,
    query: request.query,
    location: request.location,
    results,
    answerBox,
    relatedQuestions,
    searchMetadata: {
      id: body?.search_metadata?.id || null,
      status: body?.search_metadata?.status || null,
    },
    summary:
      results.length === 0
        ? `No web results found for "${request.query}"`
        : `${results.length} web result(s) found for "${request.query}"`,
  };
}

function normalizeText(value) {
  if (value == null) {
    return '';
  }
  return String(value).trim();
}

function clampInt(value, fallback, min, max) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, parsed));
}

module.exports = {
  normalizeSerpApiResponse,
  normalizeWebSearchInput,
  searchWithSerpApi,
};
