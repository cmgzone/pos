import { useState } from 'react'
import { apiUrl, readApiJson } from '../utils/api'
import { friendlyError } from '../utils/errors'

export default function Login({ onLogin }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [activeAboutTab, setActiveAboutTab] = useState('about')

  const aboutTabs = {
    about: {
      label: 'About Us',
      title: 'Piki POS is built for real shop work.',
      body:
        'Piki POS helps small and growing businesses manage sales, products, services, stock, catalog orders, receipts, reports, staff, and payments from one dependable platform.',
      points: [
        'Kenya-ready workflows for KSh, M-Pesa, receipts, and tax reporting.',
        'Offline-first tools so the shop can keep moving when internet drops.',
        'Simple admin controls for subscriptions, releases, and business support.'
      ]
    },
    foundersMission: {
      label: 'Our Founders Mission',
      title: 'Make professional business tools accessible to every local owner.',
      body:
        "Our founders' mission is to give shop owners the same confidence as large retailers without forcing them into complex, expensive systems.",
      points: [
        'Reduce daily stress by making sales, stock, invoices, and customer follow-up easier.',
        'Help owners understand their business through clear reports and Piki AI insights.',
        'Build trust with production-ready payments, subscription clarity, backups, and compliance support.'
      ]
    }
  }

  const activeAbout = aboutTabs[activeAboutTab]

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const res = await fetch(apiUrl('/api/platform/login'), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ email, password })
      })

      const data = await readApiJson(res)

      if (res.ok && data.ok) {
        onLogin(data.token)
      } else {
        setError(friendlyError(data.error, 'Login failed.'))
      }
    } catch (error) {
      setError(friendlyError(error, 'Network error. Could not reach backend.'))
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-layout">
        <section className="glass-panel animate-fade-in about-card">
          <div className="about-eyebrow">Piki POS Platform</div>
          <h1>Business tools that feel close to the counter.</h1>
          <p>
            From the first product to the end-of-day report, Piki is designed
            to help owners sell, track, recover, and grow with less confusion.
          </p>

          <div className="about-tabs" role="tablist" aria-label="About Piki POS">
            {Object.entries(aboutTabs).map(([key, tab]) => (
              <button
                key={key}
                type="button"
                role="tab"
                aria-selected={activeAboutTab === key}
                className={`about-tab ${activeAboutTab === key ? 'is-active' : ''}`}
                onClick={() => setActiveAboutTab(key)}
              >
                {tab.label}
              </button>
            ))}
          </div>

          <div className="about-tab-panel" role="tabpanel">
            <h2>{activeAbout.title}</h2>
            <p>{activeAbout.body}</p>
            <ul>
              {activeAbout.points.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
          </div>
        </section>

        <div className="glass-panel animate-fade-in auth-card">
          <div className="auth-header">
            <div className="brand">
              <div className="brand-icon">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5"/>
                </svg>
              </div>
            </div>
            <h2 className="brand-name">Piki POS Platform</h2>
            <p className="auth-kicker">Admin Portal Login</p>
          </div>

          {error && (
            <div className="auth-error">
              {error}
            </div>
          )}

          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label className="form-label">Admin Email</label>
              <input 
                type="email" 
                className="form-input" 
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required 
              />
            </div>
            
            <div className="form-group">
              <label className="form-label">Password</label>
              <input
                type="password"
                className="form-input"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>

            <button 
              type="submit" 
              className="btn btn-primary" 
              style={{ width: '100%', marginTop: '1rem' }}
              disabled={loading}
            >
              {loading ? 'Authenticating...' : 'Sign In'}
            </button>
          </form>
        </div>
      </div>
    </div>
  )
}
