import { Component } from 'react'

export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props)
    this.state = { hasError: false, error: null }
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error }
  }

  componentDidCatch(error, info) {
    console.error('Storefront crashed:', error, info)
  }

  render() {
    if (this.state.hasError) {
      const err = this.state.error
      return (
        <div style={{ padding: '40px 20px', maxWidth: '640px', margin: '0 auto', fontFamily: 'Inter, sans-serif' }}>
          <h1 style={{ fontSize: '22px', marginBottom: '12px' }}>Something went wrong</h1>
          <p style={{ color: '#6b7280', marginBottom: '16px' }}>
            The store could not be loaded. Please refresh the page or try again later.
          </p>
          <pre
            style={{
              background: '#f6f7f9',
              padding: '14px',
              borderRadius: '8px',
              fontSize: '12px',
              overflow: 'auto',
              color: '#dc2626',
              whiteSpace: 'pre-wrap',
              wordBreak: 'break-word',
            }}
          >
            {err?.message || String(err)}
            {err?.stack ? '\n\n' + err.stack : ''}
          </pre>
          <button
            type="button"
            onClick={() => window.location.reload()}
            style={{
              marginTop: '16px',
              padding: '10px 20px',
              borderRadius: '999px',
              border: 0,
              background: '#111827',
              color: '#fff',
              fontSize: '14px',
              fontWeight: 700,
              cursor: 'pointer',
            }}
          >
            Refresh page
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
