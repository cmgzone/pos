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
  baseUrl = 'https://google.serper.dev/search',
  input,
}) {
  if (!apiKey || !apiKey.trim()) {
    throw new Error('Serper API key is not configured');
  }

  const request = normalizeWebSearchInput(input);
  if (!request.query) {
    throw new Error('Search query is required');
  }

  const payload = {
    q: request.query,
    num: request.limit,
  };
  if (request.location) {
    payload.location = request.location;
  }
  if (request.gl) {
    payload.gl = request.gl.toLowerCase();
  }
  if (request.hl) {
    payload.hl = request.hl.toLowerCase();
  }

  const response = await fetchImpl(baseUrl, {
    method: 'POST',
    headers: {
      'X-API-KEY': apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const body = await response.json();

  if (!response.ok) {
    throw new Error(
      body?.message || body?.error || `Serper request failed (${response.status})`,
    );
  }
  if (body?.message && response.status !== 200) {
    throw new Error(body.message);
  }

  return normalizeSerpApiResponse(body, request);
}

function normalizeSerpApiResponse(body, request) {
  const organicResults = Array.isArray(body?.organic)
    ? body.organic
    : (Array.isArray(body?.organic_results) ? body.organic_results : []);
    
  const results = organicResults.slice(0, request.limit).map((item, index) => ({
    position: Number(item.position || index + 1),
    title: normalizeText(item.title) || 'Result',
    link: normalizeText(item.link),
    snippet: normalizeText(item.snippet),
    source: normalizeText(item.source),
    displayedLink: normalizeText(item.displayed_link),
    imageUrl: normalizeText(item.imageUrl || item.image_url || item.thumbnail),
  }));

  const answerBox = body?.answerBox || body?.answer_box
    ? {
        title: normalizeText(body.answerBox?.title || body.answer_box?.title),
        answer:
          normalizeText(body.answerBox?.answer || body.answer_box?.answer) ||
          normalizeText(body.answerBox?.snippet || body.answer_box?.snippet),
        link: normalizeText(body.answerBox?.link || body.answer_box?.link),
      }
    : null;

  const relatedQuestionsSource = Array.isArray(body?.peopleAlsoAsk) 
    ? body.peopleAlsoAsk 
    : (Array.isArray(body?.related_questions) ? body.related_questions : []);
    
  const relatedQuestions = relatedQuestionsSource.slice(0, 3).map((item) => ({
        question: normalizeText(item.question),
        answer: normalizeText(item.snippet) || normalizeText(item.answer),
        link: normalizeText(item.link),
      }));

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
