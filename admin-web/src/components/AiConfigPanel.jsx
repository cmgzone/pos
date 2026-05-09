import { useState, useEffect } from 'react'

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

export default function AiConfigPanel({ token }) {
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [testing, setTesting] = useState(false)
  const [testResult, setTestResult] = useState(null)
  
  const [apiKey, setApiKey] = useState('')
  const [hasKey, setHasKey] = useState(false)
  const [model, setModel] = useState('openai/gpt-4o-mini')
  const [enabled, setEnabled] = useState(false)
  const [showKey, setShowKey] = useState(false)
  const [updatedAt, setUpdatedAt] = useState(null)

  const headers = { 'Authorization': `Bearer ${token}` }

  const hasUsableApiKey = () => {
    if (hasKey) return true
    const trimmed = apiKey.trim()
    return trimmed.length > 0 && !trimmed.startsWith('•')
  }

  useEffect(() => {
    fetchConfig()
  }, [])

  const fetchConfig = async () => {
    setLoading(true)
    try {
      const res = await fetch('/api/platform/ai-config', { headers })
      if (res.ok) {
        const data = await res.json()
        if (data.ok) {
          setApiKey(data.data.apiKey || '')
          setHasKey(data.data.hasKey)
          setModel(data.data.model || 'openai/gpt-4o-mini')
          setEnabled(Boolean(data.data.enabled && data.data.hasKey))
          setUpdatedAt(data.data.updatedAt)
        }
      }
    } catch (err) {
      console.error('Failed to fetch AI config:', err)
    } finally {
      setLoading(false)
    }
  }

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
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ apiKey, model, enabled }),
      })
      const data = await res.json()
      if (data.ok) {
        setTestResult({ type: 'success', message: 'Configuration saved successfully!' })
        await fetchConfig()
      } else {
        setTestResult({ type: 'error', message: data.error || 'Failed to save' })
      }
    } catch (err) {
      setTestResult({ type: 'error', message: 'Network error saving config' })
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
        headers: { ...headers, 'Content-Type': 'application/json' },
      })
      const data = await res.json()
      if (data.ok) {
        setTestResult({
          type: 'success',
          message: `✅ ${data.response} (Model: ${data.model})`,
        })
      } else {
        setTestResult({ type: 'error', message: `❌ ${data.error}` })
      }
    } catch (err) {
      setTestResult({ type: 'error', message: '❌ Network error — is the backend running?' })
    } finally {
      setTesting(false)
    }
  }

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '300px', color: 'var(--text-muted)' }}>
        Loading AI configuration...
      </div>
    )
  }

  const selectedModel = MODELS.find(m => m.id === model) || MODELS[0]

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
        
        {(() => {
          const selectedModel = MODELS.find(m => m.id === model) || {
            name: 'Custom Model',
            provider: 'Custom',
            tier: 'Custom'
          };
          return (
            <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem', flexWrap: 'wrap' }}>
              <span className={`badge ${selectedModel.tier === 'Budget' ? 'badge-success' : selectedModel.tier === 'Custom' ? 'badge-secondary' : 'badge-warning'}`}>
                {selectedModel.tier}
              </span>
              <span className="badge badge-info">{selectedModel.provider}</span>
            </div>
          );
        })()}
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
      <div style={{ display: 'flex', gap: '0.75rem', marginBottom: '1.5rem' }}>
        <button
          className="btn btn-primary"
          onClick={saveConfig}
          disabled={saving}
          style={{ flex: 1 }}
        >
          {saving ? 'Saving...' : '💾 Save Configuration'}
        </button>
        <button
          className="btn btn-secondary"
          onClick={testConnection}
          disabled={testing || !hasKey}
          style={{ flex: 1 }}
        >
          {testing ? 'Testing...' : '🧪 Test Connection'}
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
