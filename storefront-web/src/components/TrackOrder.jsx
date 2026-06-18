import { useState } from 'react'

export default function TrackOrder({ onTrackOrder }) {
  const [orderNumber, setOrderNumber] = useState('')
  const [phone, setPhone] = useState('')
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState(null)
  const [error, setError] = useState(null)

  const submit = async (e) => {
    e.preventDefault()
    if (loading) return
    setError(null)
    setResult(null)
    if (!orderNumber.trim() || !phone.trim()) {
      setError('Enter your order number and phone.')
      return
    }
    setLoading(true)
    try {
      const order = await onTrackOrder({ orderNumber: orderNumber.trim(), phone: phone.trim() })
      setResult(order)
    } catch (err) {
      setError(err.message || 'Order not found.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="track-panel">
      <form className="checkout-form" onSubmit={submit}>
        <p className="track-intro">Enter the reference number from your order and the phone you used.</p>
        <label className="field">
          <span className="field-label">Order reference</span>
          <input
            type="text"
            value={orderNumber}
            onChange={(e) => setOrderNumber(e.target.value)}
            placeholder="e.g. 1a2b3c4d"
            required
          />
        </label>
        <label className="field">
          <span className="field-label">Phone number</span>
          <input
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="e.g. 0712 345 678"
            required
          />
        </label>
        <button type="submit" className="btn btn-primary btn-block" disabled={loading}>
          {loading ? 'Tracking...' : 'Track order'}
        </button>

        {error && (
          <div className="alert alert-error">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
              />
            </svg>
            <span>{error}</span>
          </div>
        )}

        {result && (
          <div className="alert alert-success">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            <div>
              Order status:{' '}
              <span className={`status-pill status-${(result.status || 'pending').replace(/_/g, '-')}`}>
                {(result.status || 'pending').replace(/_/g, ' ')}
              </span>
              {result.updatedAt && (
                <>
                  <br />
                  Last updated: {new Date(result.updatedAt).toLocaleString()}
                </>
              )}
            </div>
          </div>
        )}
      </form>
    </div>
  )
}
