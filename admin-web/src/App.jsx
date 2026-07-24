import { useState, useEffect } from 'react'
import Login from './components/Login'
import Dashboard from './components/Dashboard'
import WhatsAppConnectCallback from './components/WhatsAppConnectCallback'
import WhatsAppConnectLauncher from './components/WhatsAppConnectLauncher'
import { apiUrl } from './utils/api'
import './index.css'

const CONNECT_PATHS = new Set(['/whatsapp/connect', '/whatsapp-connect'])
const CALLBACK_PATHS = new Set([
  '/whatsapp/connect/callback',
  '/whatsapp-connect/callback',
])

function App() {
  const [token, setToken] = useState(
    sessionStorage.getItem('platform_token') || null,
  )
  const isWhatsAppConnect = CONNECT_PATHS.has(window.location.pathname)
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
      const requestTarget = typeof args[0] === 'string'
        ? args[0]
        : (args[0]?.url || '')
      const nextArgs =
        typeof args[0] === 'string' ? [apiUrl(args[0]), ...args.slice(1)] : args
      const response = await origFetch(...nextArgs)
      if (response.status === 401 && requestTarget.includes('/api/platform')) {
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
      {isWhatsAppConnect ? (
        <WhatsAppConnectLauncher />
      ) : isWhatsAppCallback ? (
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
