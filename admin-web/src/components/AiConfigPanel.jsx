import { useState, useEffect, useCallback } from 'react'
import { friendlyError } from '../utils/errors'

const MODELS = [
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

const STT_MODELS = [
  { id: 'openai/whisper-1', name: 'Whisper 1', provider: 'OpenAI', tier: 'Voice' },
]

const TTS_MODELS = [
  { id: 'openai/tts-1', name: 'TTS 1', provider: 'OpenAI', tier: 'Voice' },
  { id: 'openai/tts-1-hd', name: 'TTS 1 HD', provider: 'OpenAI', tier: 'Premium' },
]

const IMAGE_MODELS = [
  { id: 'google/gemini-2.5-flash-image', name: 'Gemini 2.5 Flash Image', provider: 'Google', tier: 'Image' },
  { id: 'google/gemini-3.1-flash-image-preview', name: 'Gemini 3.1 Flash Image Preview', provider: 'Google', tier: 'Image' },
  { id: 'black-forest-labs/flux.2-pro', name: 'Flux 2 Pro', provider: 'Black Forest Labs', tier: 'Image' },
  { id: 'black-forest-labs/flux.2-flex', name: 'Flux 2 Flex', provider: 'Black Forest Labs', tier: 'Image' },
  { id: 'recraft/recraft-v3', name: 'Recraft V3', provider: 'Recraft', tier: 'Image' },
]

const TTS_VOICES = ['alloy', 'echo', 'fable', 'nova', 'onyx', 'shimmer']

export default function AiConfigPanel({ token }) {
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [testingWebSearch, setTestingWebSearch] = useState(false)
  const [testResult, setTestResult] = useState(null)
  
  const [apiKey, setApiKey] = useState('')
  const [hasKey, setHasKey] = useState(false)
  const [serpApiKey, setSerpApiKey] = useState('')
  const [hasSerpApiKey, setHasSerpApiKey] = useState(false)
  const [serpApiKeySource, setSerpApiKeySource] = useState('none')
  const [model, setModel] = useState('openai/gpt-4o-mini')
  const [imageModel, setImageModel] = useState('google/gemini-2.5-flash-image')
  const [sttModel, setSttModel] = useState('openai/whisper-1')
  const [ttsModel, setTtsModel] = useState('openai/tts-1')
  const [ttsVoice, setTtsVoice] = useState('alloy')
  const [enabled, setEnabled] = useState(false)
  const [showKey, setShowKey] = useState(false)
  const [showSerpApiKey, setShowSerpApiKey] = useState(false)
  const [updatedAt, setUpdatedAt] = useState(null)

  const authHeaders = useCallback(() => ({ 'Authorization': `Bearer ${token}` }), [token])

  const hasUsableApiKey = () => {
    if (hasKey) return true
    const trimmed = apiKey.trim()
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
          setSerpApiKey(data.data.serpApiKey || '')
          setHasSerpApiKey(Boolean(data.data.hasSerpApiKey))
          setSerpApiKeySource(data.data.serpApiKeySource || 'none')
          setModel(data.data.model || 'openai/gpt-4o-mini')
          setImageModel(data.data.imageModel || 'google/gemini-2.5-flash-image')
          setSttModel(data.data.sttModel || 'openai/whisper-1')
          setTtsModel(data.data.ttsModel || 'openai/tts-1')
          setTtsVoice(data.data.ttsVoice || 'alloy')
          setEnabled(Boolean(data.data.enabled && data.data.hasKey))
          setUpdatedAt(data.data.updatedAt)
        }
      }
    } catch (err) {
      console.error('Failed to fetch AI config:', err)
    } finally {
      setLoading(false)
    }
  }, [authHeaders])

  useEffect(() => {
    fetchConfig()
  }, [fetchConfig])

  const saveConfig = async () => {
    setSaving(true)
    setTestResult(null)
    if (enabled && !hasUsableApiKey()) {
      setTestResult({ type: 'error', message: 'Add and save a real OpenRouter API key before enabling AI.' })
      setSaving(false)
      return
    }
    try {
      const res = await fetch('/api/platform/ai-config', {
        method: 'PUT',
        headers: { ...authHeaders(), 'Content-Type': 'application/json' },
        body: JSON.stringify({ apiKey, serpApiKey, model, imageModel, sttModel, ttsModel, ttsVoice, enabled }),
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
          message: `✅ ${data.response} (Model: ${data.model})`,
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

  const renderModelBadges = (catalog, value) => {
    const selectedModel = catalog.find(m => m.id === value) || {
      provider: 'Custom',
      tier: 'Custom',
    }

    return (
      <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem', flexWrap: 'wrap' }}>
        <span className={`badge ${selectedModel.tier === 'Budget' || selectedModel.tier === 'Voice' ? 'badge-success' : selectedModel.tier === 'Custom' ? 'badge-secondary' : 'badge-warning'}`}>
          {selectedModel.tier}
        </span>
        <span className="badge badge-info">{selectedModel.provider}</span>
      </div>
    )
  }

  return (
    <div className="animate-fade-in" style={{ maxWidth: '680px' }}>
      <div style={{ marginBottom: '2rem' }}>
        <h3 style={{ fontSize: '1.25rem', marginBottom: '0.5rem' }}>
          <span style={{ marginRight: '0.5rem' }}>🤖</span>
          AI Configuration
        </h3>
        <p style={{ color: 'var(--text-muted)', fontSize: '0.875rem' }}>
          Configure OpenRouter to power the Piki AI agent across all client apps.
          The API key is stored server-side and never exposed to client devices.
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
            {enabled ? '🟢 AI Enabled' : '🔴 AI Disabled'}
          </div>
          <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
            {enabled ? 'All clients can use AI-powered responses' : 'Clients will use local pattern matching only'}
          </div>
          {!enabled && !hasUsableApiKey() && (
            <div style={{ fontSize: '0.75rem', color: 'var(--accent-warning)', marginTop: '0.25rem' }}>
              Add an OpenRouter API key before enabling AI.
            </div>
          )}
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

      {/* API Key */}
      <div className="form-group">
        <label className="form-label">
          OpenRouter API Key
          {hasKey && <span style={{ color: 'var(--accent-success)', marginLeft: '0.5rem', fontSize: '0.75rem' }}>✓ Configured</span>}
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
            {showKey ? '🙈' : '👁️'}
          </button>
        </div>
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
          Get your key from <a href="https://openrouter.ai/keys" target="_blank" rel="noopener noreferrer" style={{ color: 'var(--accent-secondary)' }}>openrouter.ai/keys</a>
        </span>
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
          Lets Piki use live web search for current outside facts. Source: {serpApiKeySource === 'environment' ? 'server environment' : serpApiKeySource === 'database' ? 'admin setting' : 'not configured'}.
        </span>
      </div>

      {/* Model selector */}
      <div className="form-group">
        <label className="form-label">AI Model</label>
        <input
          list="ai-models-list"
          className="form-input"
          value={model}
          onChange={(e) => setModel(e.target.value)}
          placeholder="Type or select a model ID (e.g. anthropic/claude-3-haiku)"
        />
        <datalist id="ai-models-list">
          {MODELS.map(m => (
            <option key={m.id} value={m.id}>
              {m.name} — {m.provider}
            </option>
          ))}
        </datalist>
        {renderModelBadges(MODELS, model)}
      </div>

      <div className="form-group">
        <label className="form-label">Product Image Model</label>
        <input
          list="image-models-list"
          className="form-input"
          value={imageModel}
          onChange={(e) => setImageModel(e.target.value)}
          placeholder="google/gemini-2.5-flash-image"
        />
        <datalist id="image-models-list">
          {IMAGE_MODELS.map(m => (
            <option key={m.id} value={m.id}>
              {m.name} - {m.provider}
            </option>
          ))}
        </datalist>
        {renderModelBadges(IMAGE_MODELS, imageModel)}
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
          Used when Piki enhances product photos and saves the improved catalog image.
        </span>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '1rem' }}>
        <div className="form-group">
          <label className="form-label">Speech-to-Text Model</label>
          <input
            list="stt-models-list"
            className="form-input"
            value={sttModel}
            onChange={(e) => setSttModel(e.target.value)}
            placeholder="openai/whisper-1"
          />
          <datalist id="stt-models-list">
            {STT_MODELS.map(m => (
              <option key={m.id} value={m.id}>
                {m.name} - {m.provider}
              </option>
            ))}
          </datalist>
          {renderModelBadges(STT_MODELS, sttModel)}
        </div>

        <div className="form-group">
          <label className="form-label">Text-to-Speech Model</label>
          <input
            list="tts-models-list"
            className="form-input"
            value={ttsModel}
            onChange={(e) => setTtsModel(e.target.value)}
            placeholder="openai/tts-1"
          />
          <datalist id="tts-models-list">
            {TTS_MODELS.map(m => (
              <option key={m.id} value={m.id}>
                {m.name} - {m.provider}
              </option>
            ))}
          </datalist>
          {renderModelBadges(TTS_MODELS, ttsModel)}
        </div>
      </div>

      <div className="form-group">
        <label className="form-label">TTS Voice</label>
        <input
          list="tts-voices-list"
          className="form-input"
          value={ttsVoice}
          onChange={(e) => setTtsVoice(e.target.value)}
          placeholder="alloy"
        />
        <datalist id="tts-voices-list">
          {TTS_VOICES.map(voice => (
            <option key={voice} value={voice}>
              {voice}
            </option>
          ))}
        </datalist>
        <span style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.25rem' }}>
          Used by Piki when speaking back to hands-free POS users.
        </span>
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
          {saving ? 'Saving...' : '💾 Save Configuration'}
        </button>
        <button
          className="btn btn-secondary"
          onClick={testConnection}
          disabled={testing || !hasKey}
          style={{ flex: '1 1 12rem' }}
        >
          {testing ? 'Testing...' : '🧪 Test Connection'}
        </button>
        <button
          className="btn btn-secondary"
          onClick={testWebSearch}
          disabled={testingWebSearch || !hasUsableSerpApiKey()}
          style={{ flex: '1 1 12rem' }}
        >
          {testingWebSearch ? 'Testing web...' : 'Test Web Search'}
        </button>
      </div>

      {/* Rate limiting info */}
      <div style={{
        padding: '1rem', borderRadius: 'var(--radius-md)',
        background: 'var(--bg-tertiary)', border: '1px solid var(--border-subtle)',
        fontSize: '0.8rem', color: 'var(--text-muted)', lineHeight: 1.6,
      }}>
        <strong style={{ color: 'var(--text-secondary)' }}>ℹ️ Rate Limits:</strong> Each business is limited to <strong style={{ color: 'var(--text-primary)' }}>30 AI requests per hour</strong>.
        {updatedAt && (
          <span style={{ display: 'block', marginTop: '0.5rem' }}>
            Last updated: {new Date(updatedAt).toLocaleString()}
          </span>
        )}
      </div>
    </div>
  )
}
