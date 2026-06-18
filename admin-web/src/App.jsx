import { useState, useEffect } from 'react'
import Login from './components/Login'
import Dashboard from './components/Dashboard'
import WhatsAppConnectCallback from './components/WhatsAppConnectCallback'
import { apiUrl } from './utils/api'
import './index.css'

const CALLBACK_PATHS = new Set([
  '/whatsapp/connect/callback',
  '/whatsapp-connect/callback',
])

function App() {
  const [token, setToken] = useState(
    sessionStorage.getItem('platform_token') || null,
  )
  const isWhatsAppCallback = CALLBACK_PATHS.has(window.location.pathname)

  const handleLogin = (newToken) => {
    sessionStorage.setItem('platform_token', newToken)
    setToken(newToken)
  }

  const handleLogout = () => {
    sessionStorage.removeItem('platform_token')
    localStorage.removeItem('platform_token')
    setToken(null)
  }

  // Intercept api errors globally to handle token expiration
  useEffect(() => {
    localStorage.removeItem('platform_token')
    const origFetch = window.fetch
    window.fetch = async (...args) => {
      const requestTarget = typeof args[0] === 'string' ? args[0] : ''
      const nextArgs =
        typeof args[0] === 'string' ? [apiUrl(args[0]), ...args.slice(1)] : args
      const response = await origFetch(...nextArgs)
      if (response.status === 401 && requestTarget.startsWith('/api/platform')) {
        handleLogout()
      }
      return response
    }
    return () => {
      window.fetch = origFetch
    }
  }, [])

  return (
    <div className="app-container">
      {isWhatsAppCallback ? (
        <WhatsAppConnectCallback />
      ) : token ? (
        <Dashboard token={token} onLogout={handleLogout} />
      ) : (
        <Login onLogin={handleLogin} />
      )}
    </div>
  )
}

export default App
