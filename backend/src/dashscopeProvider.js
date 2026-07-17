const DASHSCOPE_BASE_URL =
  process.env.DASHSCOPE_BASE_URL || 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';

const DASHSCOPE_CHAT_MODELS = [
  { id: 'qwen-max', name: 'Qwen Max', tier: 'Pro', context: '32K' },
  { id: 'qwen-max-latest', name: 'Qwen Max Latest', tier: 'Pro', context: '32K' },
  { id: 'qwen-plus', name: 'Qwen Plus', tier: 'Balanced', context: '131K' },
  { id: 'qwen-plus-latest', name: 'Qwen Plus Latest', tier: 'Balanced', context: '131K' },
  { id: 'qwen-turbo', name: 'Qwen Turbo', tier: 'Budget', context: '131K' },
  { id: 'qwen-turbo-latest', name: 'Qwen Turbo Latest', tier: 'Budget', context: '131K' },
  { id: 'qwen-long', name: 'Qwen Long', tier: 'Budget', context: '10M' },
  { id: 'qwen3-235b-a22b', name: 'Qwen3 235B A22B', tier: 'Pro', context: '262K' },
  { id: 'qwen3-32b', name: 'Qwen3 32B', tier: 'Balanced', context: '131K' },
  { id: 'qwen3-30b-a3b', name: 'Qwen3 30B A3B', tier: 'Balanced', context: '131K' },
  { id: 'qwen3-14b', name: 'Qwen3 14B', tier: 'Budget', context: '131K' },
  { id: 'qwen3-8b', name: 'Qwen3 8B', tier: 'Budget', context: '131K' },
  { id: 'qwen3-4b', name: 'Qwen3 4B', tier: 'Budget', context: '131K' },
  { id: 'qwen3-1.7b', name: 'Qwen3 1.7B', tier: 'Budget', context: '32K' },
  { id: 'qwen3-0.6b', name: 'Qwen3 0.6B', tier: 'Budget', context: '32K' },
  { id: 'qwq-plus', name: 'QwQ Plus (Reasoning)', tier: 'Pro', context: '131K' },
  { id: 'qwq-32b', name: 'QwQ 32B (Reasoning)', tier: 'Balanced', context: '131K' },
  { id: 'qwen-coder-plus', name: 'Qwen Coder Plus', tier: 'Pro', context: '131K' },
  { id: 'qwen-coder-turbo', name: 'Qwen Coder Turbo', tier: 'Budget', context: '131K' },
  { id: 'qwen-math-plus', name: 'Qwen Math Plus', tier: 'Pro', context: '4K' },
  { id: 'qwen-math-turbo', name: 'Qwen Math Turbo', tier: 'Budget', context: '4K' },
  { id: 'deepseek-r1', name: 'DeepSeek R1', tier: 'Pro', context: '64K' },
  { id: 'deepseek-v3', name: 'DeepSeek V3', tier: 'Balanced', context: '64K' },
];

const DASHSCOPE_IMAGE_MODELS = [
  { id: 'wanx2.1-t2i-turbo', name: 'Wanx 2.1 T2I Turbo', tier: 'Image', sizes: '1024*1024' },
  { id: 'wanx2.1-t2i-plus', name: 'Wanx 2.1 T2I Plus', tier: 'Image', sizes: '1024*1024' },
  { id: 'wanx-v1', name: 'Wanx V1', tier: 'Image', sizes: '1024*1024' },
  { id: 'flux-schnell', name: 'Flux Schnell', tier: 'Image', sizes: '1024*1024' },
  { id: 'flux-dev', name: 'Flux Dev', tier: 'Image', sizes: '1024*1024' },
  { id: 'stable-diffusion-xl', name: 'Stable Diffusion XL', tier: 'Image', sizes: '1024*1024' },
  { id: 'stable-diffusion-v1.5', name: 'Stable Diffusion V1.5', tier: 'Image', sizes: '512*512' },
];

const DASHSCOPE_STT_MODELS = [
  { id: 'paraformer-v2', name: 'Paraformer V2', tier: 'STT', languages: 'Multi-language' },
  { id: 'paraformer-realtime-v2', name: 'Paraformer Realtime V2', tier: 'STT', languages: 'Multi-language' },
  { id: 'paraformer-v1', name: 'Paraformer V1', tier: 'STT', languages: 'Chinese/English' },
  { id: 'sensevoice-v1', name: 'SenseVoice V1', tier: 'STT', languages: 'Multi-language' },
];

const DASHSCOPE_TTS_MODELS = [
  { id: 'cosyvoice-v2', name: 'CosyVoice V2', tier: 'TTS' },
  { id: 'cosyvoice-v1', name: 'CosyVoice V1', tier: 'TTS' },
  { id: 'sambert-zhichu-v1', name: 'Sambert ZhiChu V1 (Chinese Male)', tier: 'TTS' },
  { id: 'sambert-zhimiao-v1', name: 'Sambert ZhiMiao V1 (Chinese Female)', tier: 'TTS' },
  { id: 'sambert-zhixiang-v1', name: 'Sambert ZhiXiang V1 (Chinese Male)', tier: 'TTS' },
  { id: 'sambert-zhiwei-v1', name: 'Sambert ZhiWei V1 (Chinese Female)', tier: 'TTS' },
];

const DASHSCOPE_TTS_VOICES = [
  'longxiaochun', 'longxiaoxia', 'longxiaochen', 'longxiaobai',
  'longlaotie', 'longshu', 'longjiejie', 'longyue',
  'longfei', 'longjing', 'longshuo', 'longtong',
  'longxiang', 'longjielidou', 'longmiao',
];

function getDashScopeModels(type) {
  switch (type) {
    case 'chat': return DASHSCOPE_CHAT_MODELS;
    case 'image': return DASHSCOPE_IMAGE_MODELS;
    case 'stt': return DASHSCOPE_STT_MODELS;
    case 'tts': return DASHSCOPE_TTS_MODELS;
    default: return [];
  }
}

async function fetchDashScopeModels(apiKey, type) {
  if (!apiKey) return getDashScopeModels(type);
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);
    const res = await fetch(`${DASHSCOPE_BASE_URL}/models`, {
      headers: { 'Authorization': `Bearer ${apiKey}` },
      signal: controller.signal,
    });
    clearTimeout(timeout);
    if (!res.ok) return getDashScopeModels(type);
    const data = await res.json();
    if (!data?.data?.length) return getDashScopeModels(type);
    return data.data
      .filter((m) => {
        const id = m.id || '';
        if (type === 'chat') return !id.includes('audio') && !id.includes('vl') && !id.includes('image') && !id.includes('livetranslate') && !id.includes('omni') && !id.includes('realtime');
        if (type === 'image') return id.includes('image') || id.includes('wanx') || id.includes('flux') || id.includes('stable-diffusion') || id.includes('z-image');
        if (type === 'stt') return id.includes('paraformer') || id.includes('sensevoice') || id.includes('whisper');
        if (type === 'tts') return id.includes('cosyvoice') || id.includes('sambert') || id.includes('longxia');
        return true;
      })
      .map((m) => ({
        id: m.id,
        name: m.id.replace(/[-_]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
        tier: type === 'chat' ? 'API' : type.toUpperCase(),
        ...(m.owned_by ? { provider: m.owned_by } : {}),
      }));
  } catch {
    return getDashScopeModels(type);
  }
}

async function sendDashScopeChat({ apiKey, model, messages, maxTokens = 1024, temperature = 0.7, responseFormat, baseUrl }) {
  const url = `${baseUrl || DASHSCOPE_BASE_URL}/chat/completions`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 60000);
  const body = {
    model,
    messages,
    max_tokens: maxTokens,
    temperature,
  };
  if (responseFormat) body.response_format = responseFormat;
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    if (!res.ok) {
      const errorBody = await res.text().catch(() => '');
      const error = new Error(`DashScope API error: ${res.status}`);
      error.statusCode = res.status;
      error.dashScopeStatus = res.status;
      error.dashScopeMessage = errorBody;
      throw error;
    }
    return res.json();
  } catch (error) {
    clearTimeout(timeout);
    throw error;
  }
}

async function sendDashScopeImage({ apiKey, model, prompt, size = '1024*1024', baseUrl }) {
  const url = `${baseUrl || DASHSCOPE_BASE_URL}/images/generations`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 120000);
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ model, prompt, size, n: 1 }),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    if (!res.ok) {
      const errorBody = await res.text().catch(() => '');
      const error = new Error(`DashScope image error: ${res.status}`);
      error.statusCode = res.status;
      error.dashScopeMessage = errorBody;
      throw error;
    }
    return res.json();
  } catch (error) {
    clearTimeout(timeout);
    throw error;
  }
}

async function testDashScopeConnection(apiKey, model = 'qwen-turbo', baseUrl) {
  const result = await sendDashScopeChat({
    apiKey,
    model,
    messages: [
      { role: 'system', content: 'Reply with exactly: DashScope connected.' },
      { role: 'user', content: 'Say the confirmation phrase.' },
    ],
    maxTokens: 30,
    temperature: 0,
    baseUrl,
  });
  const content = result?.choices?.[0]?.message?.content || '';
  return { ok: true, response: content.trim(), model: result?.model || model };
}

module.exports = {
  DASHSCOPE_BASE_URL,
  DASHSCOPE_CHAT_MODELS,
  DASHSCOPE_IMAGE_MODELS,
  DASHSCOPE_STT_MODELS,
  DASHSCOPE_TTS_MODELS,
  DASHSCOPE_TTS_VOICES,
  getDashScopeModels,
  fetchDashScopeModels,
  sendDashScopeChat,
  sendDashScopeImage,
  testDashScopeConnection,
};
