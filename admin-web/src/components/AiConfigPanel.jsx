import { useState, useEffect, useCallback } from 'react'
import { friendlyError } from '../utils/errors'

const OPENROUTER_MODELS = [
  { id: 'openai/gpt-4o-mini', name: 'GPT-4o Mini', provider: 'OpenAI', tier: 'Budget' },
  { id: 'openai/gpt-4o', name: 'GPT-4o', provider: 'OpenAI', tier: 'Pro' },
  { id: 'anthropic/claude-sonnet-4', name: 'Claude Sonnet 4', provider: 'Anthropic', tier: 'Pro' },
  { id: 'anthropic/claude-3.5-haiku', name: 'Claude 3.5 Haiku', provider: 'Anthropic', tier: 'Budget' },
  { id: 'google/gemini-2.5-flash', name: 'Gemini 2.5 Flash', provider: 'Google', tier: 'Budget' },
  { id: 'google/gemini-2.5-pro', name: 'Gemini 2.5 Pro', provider: 'Google', tier: 'Pro' },
  { id: 'meta-llama/llama-3.1-70b-instruct', name: 'Llama 3.1 70B', provider: 'Meta', tier: 'Budget' },
  { id: 'mistralai/mistral-large', name: 'Mistral Large', provider: 'Mistral', tier: 'Pro' },
  { id: 'deepseek/deepseek-chat', name: 'DeepSeek V3', provider: 'DeepSeek', tier: 'Budget' },
]

const OPENROUTER_IMAGE_MODELS = [
  { id: 'google/gemini-2.5-flash-image', name: 'Gemini 2.5 Flash Image', provider: 'Google', tier: 'Image' },
  { id: 'google/gemini-3.1-flash-image-preview', name: 'Gemini 3.1 Flash Image Preview', provider: 'Google', tier: 'Image' },
  { id: 'black-forest-labs/flux.2-pro', name: 'Flux 2 Pro', provider: 'Black Forest Labs', tier: 'Image' },
  { id: 'black-forest-labs/flux.2-flex', name: 'Flux 2 Flex', provider: 'Black Forest Labs', tier: 'Image' },
  { id: 'recraft/recraft-v3', name: 'Recraft V3', provider: 'Recraft', tier: 'Image' },
]

const OPENROUTER_STT_MODELS = [
  { id: 'openai/whisper-1', name: 'Whisper 1', provider: 'OpenAI', tier: 'Voice' },
]

const OPENROUTER_TTS_MODELS = [
  { id: 'openai/tts-1', name: 'TTS 1', provider: 'OpenAI', tier: 'Voice' },
  { id: 'openai/tts-1-hd', name: 'TTS 1 HD', provider: 'OpenAI', tier: 'Premium' },
]

const OPENROUTER_TTS_VOICES = ['alloy', 'echo', 'fable', 'nova', 'onyx', 'shimmer']

const PROVIDERS = [
  { id: 'openrouter', name: 'OpenRouter', description: 'Multi-provider gateway (OpenAI, Anthropic, Google, etc.)' },
  { id: 'dashscope', name: 'Alibaba Cloud (DashScope)', description: 'Qwen models, Wanx image generation, CosyVoice TTS, Paraformer STT' },
]

export default function AiConfigPanel({ token }) {
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [testingDashScope, setTestingDashScope] = useState(false)
  const [testingWebSearch, setTestingWebSearch] = useState(false)
  const [testResult, setTestResult] = useState(null)
  const [fetchingModels, setFetchingModels] = useState(false)

  const [apiKey, setApiKey] = useState('')
  const [hasKey, setHasKey] = useState(false)
  const [dashscopeApiKey, setDashscopeApiKey] = useState('')
  const [hasDashScopeKey, setHasDashScopeKey] = useState(false)
  const [serpApiKey, setSerpApiKey] = useState('')
  const [hasSerpApiKey, setHasSerpApiKey] = useState(false)
  const [serpApiKeySource, setSerpApiKeySource] = useState('none')
  const [model, setModel] = useState('openai/gpt-4o-mini')
  const [imageModel, setImageModel] = useState('google/gemini-2.5-flash-image')
  const [sttModel, setSttModel] = useState('openai/whisper-1')
  const [ttsModel, setTtsModel] = useState('openai/tts-1')
  const [ttsVoice, setTtsVoice] = useState('alloy')
  const [chatProvider, setChatProvider] = useState('openrouter')
  const [imageProvider, setImageProvider] = useState('openrouter')
  const [sttProvider, setSttProvider] = useState('openrouter')
  const [ttsProvider, setTtsProvider] = useState('openrouter')
  const [enabled, setEnabled] = useState(false)
  const [showKey, setShowKey] = useState(false)
  const [showDashScopeKey, setShowDashScopeKey] = useState(false)
  const [showSerpApiKey, setShowSerpApiKey] = useState(false)
  const [updatedAt, setUpdatedAt] = useState(null)

  const DASHSCOPE_CHAT_FALLBACK = [
    { id: 'qwen-max', name: 'Qwen Max', tier: 'Pro' },
    { id: 'qwen-plus', name: 'Qwen Plus', tier: 'Balanced' },
    { id: 'qwen-turbo', name: 'Qwen Turbo', tier: 'Budget' },
    { id: 'qwen-long', name: 'Qwen Long', tier: 'Budget' },
    { id: 'qwen3-235b-a22b', name: 'Qwen3 235B', tier: 'Pro' },
    { id: 'qwen3-32b', name: 'Qwen3 32B', tier: 'Balanced' },
    { id: 'qwq-plus', name: 'QwQ Plus (Reasoning)', tier: 'Pro' },
    { id: 'deepseek-r1', name: 'DeepSeek R1', tier: 'Pro' },
    { id: 'deepseek-v3', name: 'DeepSeek V3', tier: 'Balanced' },
  ]
  const DASHSCOPE_IMAGE_FALLBACK = [
    { id: 'qwen-image-2.0-pro', name: 'Qwen Image 2.0 Pro', tier: 'Image' },
    { id: 'qwen-image-2.0', name: 'Qwen Image 2.0', tier: 'Image' },
    { id: 'qwen-image-max', name: 'Qwen Image Max', tier: 'Image' },
    { id: 'qwen-image-plus', name: 'Qwen Image Plus', tier: 'Image' },
    { id: 'wan2.7-image-pro', name: 'Wan 2.7 Image Pro', tier: 'Image' },
    { id: 'wan2.7-image', name: 'Wan 2.7 Image', tier: 'Image' },
    { id: 'z-image-turbo', name: 'Z-Image Turbo', tier: 'Image' },
    { id: 'wanx2.1-t2i-turbo', name: 'Wanx 2.1 Turbo', tier: 'Image' },
    { id: 'wanx2.1-t2i-plus', name: 'Wanx 2.1 Plus', tier: 'Image' },
    { id: 'flux-schnell', name: 'Flux Schnell', tier: 'Image' },
  ]
  const DASHSCOPE_STT_FALLBACK = [
    { id: 'paraformer-v2', name: 'Paraformer V2', tier: 'STT' },
    { id: 'sensevoice-v1', name: 'SenseVoice V1', tier: 'STT' },
  ]
  const DASHSCOPE_TTS_FALLBACK = [
    { id: 'cosyvoice-v2', name: 'CosyVoice V2', tier: 'TTS' },
    { id: 'sambert-zhichu-v1', name: 'Sambert ZhiChu (Male)', tier: 'TTS' },
    { id: 'sambert-zhimiao-v1', name: 'Sambert ZhiMiao (Female)', tier: 'TTS' },
  ]

  const [dashscopeChatModels, setDashscopeChatModels] = useState(DASHSCOPE_CHAT_FALLBACK)
  const [dashscopeImageModels, setDashscopeImageModels] = useState(DASHSCOPE_IMAGE_FALLBACK)
  const [dashscopeSttModels, setDashscopeSttModels] = useState(DASHSCOPE_STT_FALLBACK)
  const [dashscopeTtsModels, setDashscopeTtsModels] = useState(DASHSCOPE_TTS_FALLBACK)
  const [dashscopeTtsVoices, setDashscopeTtsVoices] = useState([])

  const authHeaders = useCallback(() => ({ 'Authorization': `Bearer ${token}` }), [token])

  const hasUsableApiKey = () => {
    if (hasKey) return true
    const trimmed = apiKey.trim()
    return trimmed.length > 0 && !trimmed.startsWith('•')
  }

  const hasUsableDashScopeKey = () => {
    if (hasDashScopeKey) return true
    const trimmed = dashscopeApiKey.trim()
    return trimmed.length > 0 && !trimmed.startsWith('•')
  }

  const hasUsableSerpApiKey = () => {
    if (hasSerpApiKey) return true
    const trimmed = serpApiKey.trim()
    return trimmed.length > 0 && !trimmed.startsWith('*')
  }

  const fetchConfig = useCallback(async () => {
    setLoading(true)
    try {
      const res = await fetch('/api/platform/ai-config', { headers: authHeaders() })
      if (res.ok) {
        const data = await res.json()
        if (data.ok) {
          setApiKey(data.data.apiKey || '')
          setHasKey(data.data.hasKey)
          setDashscopeApiKey(data.data.dashscopeApiKey || '')
          setHasDashScopeKey(data.data.hasDashScopeKey)
          setSerpApiKey(data.data.serpApiKey || '')
          setHasSerpApiKey(Boolean(data.data.hasSerpApiKey))
          setSerpApiKeySource(data.data.serpApiKeySource || 'none')
          setModel(data.data.model || 'openai/gpt-4o-mini')
          setImageModel(data.data.imageModel || 'google/gemini-2.5-flash-image')
          setSttModel(data.data.sttModel || 'openai/whisper-1')
          setTtsModel(data.data.ttsModel || 'openai/tts-1')
          setTtsVoice(data.data.ttsVoice || 'alloy')
          setChatProvider(data.data.chatProvider || 'openrouter')
          setImageProvider(data.data.imageProvider || 'openrouter')
          setSttProvider(data.data.sttProvider || 'openrouter')
          setTtsProvider(data.data.ttsProvider || 'openrouter')
          setEnabled(Boolean(data.data.enabled && (data.data.hasKey || data.data.hasDashScopeKey)))
          setUpdatedAt(data.data.updatedAt)
        }
      }
    } catch (err) {
      console.error('Failed to fetch AI config:', err)
    } finally {
      setLoading(false)
    }
  }, [authHeaders])

  const fetchDashScopeModels = useCallback(async (type) => {
    setFetchingModels(true)
    try {
      const res = await fetch(`/api/platform/ai-models?provider=dashscope&type=${type}`, { headers: authHeaders() })
      if (res.ok) {
        const data = await res.json()
        if (data.ok && data.models && data.models.length > 0) {
          if (type === 'chat') setDashscopeChatModels(data.models)
          if (type === 'image') setDashscopeImageModels(data.models)
          if (type === 'stt') setDashscopeSttModels(data.models)
          if (type === 'tts') {
            setDashscopeTtsModels(data.models)
            if (data.voices) setDashscopeTtsVoices(data.voices)
          }
          return data.models
        }
      }
      // Fallback to curated lists if API fails or returns empty
      if (type === 'chat') return DASHSCOPE_CHAT_FALLBACK
      if (type === 'image') return DASHSCOPE_IMAGE_FALLBACK
      if (type === 'stt') return DASHSCOPE_STT_FALLBACK
      if (type === 'tts') return DASHSCOPE_TTS_FALLBACK
      return []
    } catch (err) {
      console.error('Failed to fetch DashScope models:', err)
      // Return fallback lists on error
      if (type === 'chat') return DASHSCOPE_CHAT_FALLBACK
      if (type === 'image') return DASHSCOPE_IMAGE_FALLBACK
      if (type === 'stt') return DASHSCOPE_STT_FALLBACK
      if (type === 'tts') return DASHSCOPE_TTS_FALLBACK
      return []
    } finally {
      setFetchingModels(false)
    }
  }, [authHeaders])

  useEffect(() => {
    fetchConfig()
  }, [fetchConfig])

  useEffect(() => {
    if (chatProvider === 'dashscope') {
      fetchDashScopeModels('chat')
    }
  }, [chatProvider, fetchDashScopeModels])

  useEffect(() => {
    if (imageProvider === 'dashscope') {
      fetchDashScopeModels('image')
    }
  }, [imageProvider, fetchDashScopeModels])

  useEffect(() => {
    if (sttProvider === 'dashscope') {
      fetchDashScopeModels('stt')
    }
  }, [sttProvider, fetchDashScopeModels])

  useEffect(() => {
    if (ttsProvider === 'dashscope') {
      fetchDashScopeModels('tts')
    }
  }, [ttsProvider, fetchDashScopeModels])

  const saveConfig = async () => {
    setSaving(true)
    setTestResult(null)
    const needsOpenRouter = [chatProvider, imageProvider, sttProvider, ttsProvider].some(p => p === 'openrouter')
    const needsDashScope = [chatProvider, imageProvider, sttProvider, ttsProvider].some(p => p === 'dashscope')
    if (enabled && needsOpenRouter && !hasUsableApiKey()) {
      setTestResult({ type: 'error', message: 'Add and save a real OpenRouter API key before enabling AI with OpenRouter provider.' })
      setSaving(false)
      return
    }
    if (enabled && needsDashScope && !hasUsableDashScopeKey()) {
      setTestResult({ type: 'error', message: 'Add and save a real DashScope API key before enabling AI with Alibaba provider.' })
      setSaving(false)
      return
    }
    try {
      const res = await fetch('/api/platform/ai-config', {
        method: 'PUT',
        headers: { ...authHeaders(), 'Content-Type': 'application/json' },
        body: JSON.stringify({
          apiKey, dashscopeApiKey, serpApiKey, model, imageModel, sttModel, ttsModel, ttsVoice,
          chatProvider, imageProvider, sttProvider, ttsProvider, enabled,
        }),
      })
      const data = await res.json()
      if (data.ok) {
        setTestResult({ type: 'success', message: 'Configuration saved successfully!' })
        await fetchConfig()
      } else {
        setTestResult({ type: 'error', message: friendlyError(data.error, 'Failed to save configuration.') })
      }
    } catch (error) {
      setTestResult({ type: 'error', message: friendlyError(error, 'Network error saving config.') })
    } finally {
      setSaving(false)
    }
  }

  const testConnection = async () => {
    setTesting(true)
    setTestResult(null)
    try {
      const res = await fetch('/api/platform/ai-test', {
        method: 'POST',
        headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      })
      const data = await res.json()
      if (data.ok) {
        setTestResult({
          type: 'success',
          message: `${data.response} (Model: ${data.model}, Provider: ${data.provider || 'openrouter'})`,
        })
      } else {
        setTestResult({ type: 'error', message: friendlyError(data.error, 'AI test failed.') })
      }
    } catch (error) {
      setTestResult({ type: 'error', message: friendlyError(error, 'Network error. Is the backend running?') })
    } finally {
      setTesting(false)
    }
  }

  const testDashScope = async () => {
    setTestingDashScope(true)
    setTestResult(null)
    try {
      const res = await fetch('/api/platform/dashscope-test', {
        method: 'POST',
        headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      })
      const data = await res.json()
      if (data.ok) {
        setTestResult({
          type: 'success',
          message: `DashScope connected! Model: ${data.model}. Response: ${data.response}`,
        })
      } else {
        setTestResult({ type: 'error', message: friendlyError(data.error, 'DashScope test failed.') })
      }
    } catch (error) {
      setTestResult({ type: 'error', message: friendlyError(error, 'Network error testing DashScope.') })
    } finally {
      setTestingDashScope(false)
    }
  }

  const testWebSearch = async () => {
    setTestingWebSearch(true)
    setTestResult(null)
    try {
      const res = await fetch('/api/platform/web-search-test', {
        method: 'POST',
        headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      })
      const data = await res.json()
      if (data.ok) {
        setTestResult({
          type: 'success',
          message: `Web search connected. Found ${data.resultCount} result(s) for "${data.query}".`,
        })
      } else {
        setTestResult({ type: 'error', message: friendlyError(data.error, 'Web search test failed.') })
      }
    } catch (error) {
      setTestResult({ type: 'error', message: friendlyError(error, 'Network error testing web search.') })
    } finally {
      setTestingWebSearch(false)
    }
  }

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '300px', color: 'var(--text-muted)' }}>
        Loading AI configuration...
      </div>
    )
  }

  const getModelsForProvider = (provider, type) => {
    if (provider === 'dashscope') {
      if (type === 'chat') return dashscopeChatModels
      if (type === 'image') return dashscopeImageModels
      if (type === 'stt') return dashscopeSttModels
      if (type === 'tts') return dashscopeTtsModels
    }
    if (type === 'chat') return OPENROUTER_MODELS
    if (type === 'image') return OPENROUTER_IMAGE_MODELS
    if (type === 'stt') return OPENROUTER_STT_MODELS
    if (type === 'tts') return OPENROUTER_TTS_MODELS
    return []
  }

  const getModelListId = (type, provider) => `${type}-${provider}-models-list`

  const renderProviderSelector = (label, value, onChange, type) => (
    <div className="form-group" style={{ marginBottom: '1rem' }}>
      <label className="form-label" style={{ fontSize: '0.8rem', fontWeight: 600 }}>{label}</label>
      <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
        {PROVIDERS.map(p => (
          <button
            key={p.id}
            type="button"
            onClick={() => onChange(p.id)}
            style={{
              padding: '0.5rem 1rem',
              borderRadius: 'var(--radius-sm)',
              border: `2px solid ${value === p.id ? 'var(--accent-secondary)' : 'var(--border-subtle)'}`,
              background: value === p.id ? 'rgba(99, 102, 241, 0.1)' : 'var(--bg-tertiary)',
              color: value === p.id ? 'var(--accent-secondary)' : 'var(--text-secondary)',
              cursor: 'pointer',
              fontSize: '0.8rem',
              fontWeight: value === p.id ? 600 : 400,
              transition: 'all 0.2s ease',
            }}
          >
            {p.name}
          </button>
        ))}
      </div>
    </div>
  )

  const renderModelSelector = (label, value, onChange, provider, type, placeholder) => {
    const models = getModelsForProvider(provider, type)
    const listId = getModelListId(type, provider)
    const isDashScope = provider === 'dashscope'
    return (
      <div className="form-group">
        <label className="form-label">{label}</label>
        <div style={{ display: 'flex', gap: '0.5rem' }}>
          <input
            list={listId}
            className="form-input"
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder}
            style={{ flex: 1 }}
          />
          {isDashScope && (
            <button
              type="button"
              onClick={() => fetchDashScopeModels(type)}
              disabled={fetchingModels}
              style={{
                padding: '0.5rem 0.75rem',
                borderRadius: 'var(--radius-sm)',
                border: '1px solid var(--border-subtle)',
                background: 'var(--bg-tertiary)',
                color: 'var(--text-secondary)',
                cursor: fetchingModels ? 'wait' : 'pointer',
                fontSize: '0.8rem',
                whiteSpace: 'nowrap',
              }}
              title="Refresh models from DashScope API"
            >
              {fetchingModels ? 'Loading...' : 'Refresh'}
            </button>
          )}
        </div>
        <datalist id={listId}>
          {models.map(m => (
            <option key={m.id} value={m.id}>
              {m.name} — {m.tier || m.provider || provider}
            </option>
          ))}
        </datalist>
        {models.length > 0 && (
          <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
            <span className="badge badge-info">{isDashScope ? 'Alibaba' : 'OpenRouter'}</span>
            <span style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>
              {models.length} model{models.length !== 1 ? 's' : ''} available
            </span>
            {isDashScope && (
              <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)', fontStyle: 'italic' }}>
                (Type to search or click Refresh to fetch latest)
              </span>
            )}
          </div>
        )}
        {isDashScope && models.length === 0 && (
          <div style={{ fontSize: '0.75rem', color: 'var(--accent-warning)', marginTop: '0.5rem' }}>
            No models loaded. Click Refresh to fetch from DashScope API.
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="animate-fade-in" style={{ maxWidth: '720px' }}>
      <div style={{ marginBottom: '2rem' }}>
        <h3 style={{ fontSize: '1.25rem', marginBottom: '0.5rem' }}>
          AI Configuration
        </h3>
        <p style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>
          Configure AI providers to power the Piki AI agent. Supports OpenRouter (multi-provider gateway)
          and Alibaba Cloud DashScope (Qwen models, Wanx image generation, CosyVoice TTS, Paraformer STT).
        </p>
      </div>

      {/* Enable toggle */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '1rem 1.25rem', borderRadius: 'var(--radius-md)',
        background: enabled ? 'rgba(46, 213, 115, 0.08)' : 'var(--bg-tertiary)',
        border: `1px solid ${enabled ? 'rgba(46, 213, 115, 0.25)' : 'var(--border-subtle)'}`,
        marginBottom: '1.5rem', transition: 'all 0.3s ease',
      }}>
        <div>
          <div style={{ fontWeight: 600, color: enabled ? 'var(--accent-success)' : 'var(--text-primary)' }}>
            {enabled ? 'AI Enabled' : 'AI Disabled'}
          </div>
          <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
            {enabled ? 'All clients can use AI-powered responses' : 'Clients will use local pattern matching only'}
          </div>
        </div>
        <label style={{ position: 'relative', display: 'inline-block', width: '52px', height: '28px', cursor: 'pointer' }}>
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => setEnabled(e.target.checked)}
            style={{ opacity: 0, width: 0, height: 0 }}
          />
          <span style={{
            position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
            backgroundColor: enabled ? 'var(--accent-success)' : 'var(--bg-tertiary)',
            borderRadius: '14px', transition: 'all 0.3s ease',
            border: `1px solid ${enabled ? 'rgba(46,213,115,0.5)' : 'var(--border-subtle)'}`,
          }}>
            <span style={{
              position: 'absolute', content: '', height: '20px', width: '20px',
              left: enabled ? '27px' : '3px', bottom: '3px',
              backgroundColor: 'white', borderRadius: '50%', transition: 'all 0.3s ease',
              boxShadow: '0 2px 4px rgba(0,0,0,0.3)',
            }} />
          </span>
        </label>
      </div>

      {/* OpenRouter API Key */}
      <div style={{
        padding: '1.25rem', borderRadius: 'var(--radius-md)',
        background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        marginBottom: '1.5rem',
      }}>
        <h4 style={{ fontSize: '0.95rem', marginBottom: '1rem', fontWeight: 600 }}>OpenRouter</h4>
        <div className="form-group">
          <label className="form-label">
            API Key
            {hasKey && <span style={{ color: 'var(--accent-success)', marginLeft: '0.5rem', fontSize: '0.75rem' }}>Configured</span>}
          </label>
          <div style={{ position: 'relative' }}>
            <input
              type={showKey ? 'text' : 'password'}
              className="form-input"
              placeholder="sk-or-v1-..."
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              style={{ paddingRight: '3rem' }}
            />
            <button
              onClick={() => setShowKey(!showKey)}
              style={{
                position: 'absolute', right: '0.75rem', top: '50%', transform: 'translateY(-50%)',
                background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer',
                fontSize: '0.875rem',
              }}
            >
              {showKey ? 'Hide' : 'Show'}
            </button>
          </div>
          <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
            Get your key from <a href="https://openrouter.ai/keys" target="_blank" rel="noopener noreferrer" style={{ color: 'var(--accent-secondary)' }}>openrouter.ai/keys</a>
          </span>
        </div>
      </div>

      {/* DashScope API Key */}
      <div style={{
        padding: '1.25rem', borderRadius: 'var(--radius-md)',
        background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        marginBottom: '1.5rem',
      }}>
        <h4 style={{ fontSize: '0.95rem', marginBottom: '0.5rem', fontWeight: 600 }}>Alibaba Cloud (DashScope)</h4>
        <p style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: '1rem' }}>
          Qwen text models, Wanx image generation, CosyVoice text-to-speech, Paraformer speech-to-text.
        </p>
        <div className="form-group">
          <label className="form-label">
            API Key
            {hasDashScopeKey && <span style={{ color: 'var(--accent-success)', marginLeft: '0.5rem', fontSize: '0.75rem' }}>Configured</span>}
          </label>
          <div style={{ position: 'relative' }}>
            <input
              type={showDashScopeKey ? 'text' : 'password'}
              className="form-input"
              placeholder="sk-..."
              value={dashscopeApiKey}
              onChange={(e) => setDashscopeApiKey(e.target.value)}
              style={{ paddingRight: '3rem' }}
            />
            <button
              onClick={() => setShowDashScopeKey(!showDashScopeKey)}
              style={{
                position: 'absolute', right: '0.75rem', top: '50%', transform: 'translateY(-50%)',
                background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer',
                fontSize: '0.875rem',
              }}
            >
              {showDashScopeKey ? 'Hide' : 'Show'}
            </button>
          </div>
          <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
            Get your key from <a href="https://dashscope.console.aliyun.com/apiKey" target="_blank" rel="noopener noreferrer" style={{ color: 'var(--accent-secondary)' }}>DashScope Console</a>
          </span>
        </div>
      </div>

      {/* Web Search Key */}
      <div className="form-group">
        <label className="form-label">
          SerpAPI Key for Web Search
          {hasUsableSerpApiKey() && <span style={{ color: 'var(--accent-success)', marginLeft: '0.5rem', fontSize: '0.75rem' }}>Configured</span>}
        </label>
        <div style={{ position: 'relative' }}>
          <input
            type={showSerpApiKey ? 'text' : 'password'}
            className="form-input"
            placeholder="serpapi-key..."
            value={serpApiKey}
            onChange={(e) => setSerpApiKey(e.target.value)}
            style={{ paddingRight: '3rem' }}
          />
          <button
            onClick={() => setShowSerpApiKey(!showSerpApiKey)}
            style={{
              position: 'absolute', right: '0.75rem', top: '50%', transform: 'translateY(-50%)',
              background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer',
              fontSize: '0.875rem',
            }}
          >
            {showSerpApiKey ? 'Hide' : 'Show'}
          </button>
        </div>
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
          Source: {serpApiKeySource === 'environment' ? 'server environment' : serpApiKeySource === 'database' ? 'admin setting' : 'not configured'}.
        </span>
      </div>

      {/* Chat Model */}
      <div style={{
        padding: '1.25rem', borderRadius: 'var(--radius-md)',
        background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        marginBottom: '1.5rem',
      }}>
        <h4 style={{ fontSize: '0.95rem', marginBottom: '1rem', fontWeight: 600 }}>Chat / Text Model</h4>
        {renderProviderSelector('Provider', chatProvider, setChatProvider, 'chat')}
        {renderModelSelector('Model', model, setModel, chatProvider, 'chat', 'Select or type model ID...')}
      </div>

      {/* Image Model */}
      <div style={{
        padding: '1.25rem', borderRadius: 'var(--radius-md)',
        background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        marginBottom: '1.5rem',
      }}>
        <h4 style={{ fontSize: '0.95rem', marginBottom: '1rem', fontWeight: 600 }}>Image Generation</h4>
        {renderProviderSelector('Provider', imageProvider, setImageProvider, 'image')}
        {renderModelSelector('Model', imageModel, setImageModel, imageProvider, 'image', 'Select image model...')}
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
          Used when Piki enhances product photos and saves the improved catalog image.
        </span>
      </div>

      {/* STT and TTS */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '1rem', marginBottom: '1.5rem' }}>
        <div style={{
          padding: '1.25rem', borderRadius: 'var(--radius-md)',
          background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        }}>
          <h4 style={{ fontSize: '0.95rem', marginBottom: '1rem', fontWeight: 600 }}>Speech-to-Text</h4>
          {renderProviderSelector('Provider', sttProvider, setSttProvider, 'stt')}
          {renderModelSelector('Model', sttModel, setSttModel, sttProvider, 'stt', 'Select STT model...')}
        </div>

        <div style={{
          padding: '1.25rem', borderRadius: 'var(--radius-md)',
          background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        }}>
          <h4 style={{ fontSize: '0.95rem', marginBottom: '1rem', fontWeight: 600 }}>Text-to-Speech</h4>
          {renderProviderSelector('Provider', ttsProvider, setTtsProvider, 'tts')}
          {renderModelSelector('Model', ttsModel, setTtsModel, ttsProvider, 'tts', 'Select TTS model...')}
          {ttsProvider === 'dashscope' && dashscopeTtsVoices.length > 0 && (
            <div className="form-group" style={{ marginTop: '0.75rem' }}>
              <label className="form-label" style={{ fontSize: '0.8rem' }}>Voice</label>
              <input
                list="dashscope-tts-voices-list"
                className="form-input"
                value={ttsVoice}
                onChange={(e) => setTtsVoice(e.target.value)}
                placeholder="Select voice..."
              />
              <datalist id="dashscope-tts-voices-list">
                {dashscopeTtsVoices.map(v => <option key={v} value={v}>{v}</option>)}
              </datalist>
            </div>
          )}
          {ttsProvider === 'openrouter' && (
            <div className="form-group" style={{ marginTop: '0.75rem' }}>
              <label className="form-label" style={{ fontSize: '0.8rem' }}>Voice</label>
              <input
                list="openrouter-tts-voices-list"
                className="form-input"
                value={ttsVoice}
                onChange={(e) => setTtsVoice(e.target.value)}
                placeholder="alloy"
              />
              <datalist id="openrouter-tts-voices-list">
                {OPENROUTER_TTS_VOICES.map(v => <option key={v} value={v}>{v}</option>)}
              </datalist>
            </div>
          )}
        </div>
      </div>

      {/* Test result */}
      {testResult && (
        <div style={{
          padding: '0.875rem 1rem', borderRadius: 'var(--radius-md)',
          marginBottom: '1.25rem',
          background: testResult.type === 'success' ? 'rgba(46, 213, 115, 0.1)' : 'rgba(255, 71, 87, 0.1)',
          border: `1px solid ${testResult.type === 'success' ? 'rgba(46, 213, 115, 0.3)' : 'rgba(255, 71, 87, 0.3)'}`,
          color: testResult.type === 'success' ? 'var(--accent-success)' : 'var(--accent-danger)',
          fontSize: '0.875rem',
        }}>
          {testResult.message}
        </div>
      )}

      {/* Action buttons */}
      <div style={{ display: 'flex', gap: '0.75rem', marginBottom: '1.5rem', flexWrap: 'wrap' }}>
        <button
          className="btn btn-primary"
          onClick={saveConfig}
          disabled={saving}
          style={{ flex: '1 1 12rem' }}
        >
          {saving ? 'Saving...' : 'Save Configuration'}
        </button>
        <button
          className="btn btn-secondary"
          onClick={testConnection}
          disabled={testing || (!hasKey && chatProvider === 'openrouter')}
          style={{ flex: '1 1 12rem' }}
        >
          {testing ? 'Testing...' : 'Test Connection'}
        </button>
        <button
          className="btn btn-secondary"
          onClick={testDashScope}
          disabled={testingDashScope || !hasUsableDashScopeKey()}
          style={{ flex: '1 1 12rem' }}
        >
          {testingDashScope ? 'Testing...' : 'Test DashScope'}
        </button>
        <button
          className="btn btn-secondary"
          onClick={testWebSearch}
          disabled={testingWebSearch || !hasUsableSerpApiKey()}
          style={{ flex: '1 1 12rem' }}
        >
          {testingWebSearch ? 'Testing...' : 'Test Web Search'}
        </button>
      </div>

      {/* Rate limiting info */}
      <div style={{
        padding: '1rem', borderRadius: 'var(--radius-md)',
        background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        fontSize: '0.8rem', color: 'var(--text-muted)', lineHeight: 1.6,
      }}>
        <strong style={{ color: 'var(--text-secondary)' }}>Rate Limits:</strong> Each business is limited to <strong style={{ color: 'var(--text-primary)' }}>30 AI requests per hour</strong>.
        {updatedAt && (
          <span style={{ display: 'block', marginTop: '0.5rem' }}>
            Last updated: {new Date(updatedAt).toLocaleString()}
          </span>
        )}
      </div>
    </div>
  )
}
