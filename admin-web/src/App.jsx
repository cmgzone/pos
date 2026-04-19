import { useState, useEffect } from 'react'
import Login from './components/Login'
import Dashboard from './components/Dashboard'
import './index.css'

function App() {
  const [token, setToken] = useState(localStorage.getItem('platform_token') || null)

  const handleLogin = (newToken) => {
    localStorage.setItem('platform_token', newToken)
    setToken(newToken)
  }

  const handleLogout = () => {
    localStorage.removeItem('platform_token')
    setToken(null)
  }

  // Intercept api errors globally to handle token expiration
  useEffect(() => {
    const origFetch = window.fetch;
    window.fetch = async (...args) => {
      const response = await origFetch(...args);
      if (response.status === 401 && args[0].startsWith('/api/platform')) {
        handleLogout();
      }
      return response;
    };
  }, []);

  return (
    <div className="app-container">
      {token ? (
        <Dashboard token={token} onLogout={handleLogout} />
      ) : (
        <Login onLogin={handleLogin} />
      )}
    </div>
  )
}

export default App
