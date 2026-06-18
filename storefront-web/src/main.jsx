import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import ErrorBoundary from './components/ErrorBoundary.jsx'

window.addEventListener('error', (e) => {
  const root = document.getElementById('root')
  if (root && root.children.length === 0) {
    root.innerHTML =
      '<div style="padding:40px 20px;max-width:640px;margin:0 auto;font-family:Inter,sans-serif">' +
      '<h1 style="font-size:22px;margin-bottom:12px">Something went wrong</h1>' +
      '<p style="color:#6b7280;margin-bottom:16px">The store could not be loaded.</p>' +
      '<pre style="background:#f6f7f9;padding:14px;border-radius:8px;font-size:12px;overflow:auto;color:#dc2626;white-space:pre-wrap;word-break:break-word">' +
      (e.error ? (e.error.stack || e.error.message) : e.message || 'Unknown error') +
      '</pre></div>'
  }
})

window.addEventListener('unhandledrejection', (e) => {
  console.error('Unhandled promise rejection:', e.reason)
})

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </StrictMode>,
)
