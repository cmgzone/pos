import { useState } from 'react'

const FULFILLMENT_OPTIONS = [
  { value: 'pickup', label: 'Pickup at store' },
  { value: 'delivery', label: 'Delivery to my address' },
]

export default function Checkout({ total, money, lastOrder, whatsappConfirmUrl, onSubmitOrder, pushToast }) {
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [method, setMethod] = useState('pickup')
  const [note, setNote] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState(null)

  const submitted = Boolean(lastOrder)

  const submit = async (e) => {
    e.preventDefault()
    if (submitting) return
    setError(null)
    if (!name.trim()) {
      setError('Enter your name.')
      return
    }
    if (!phone.trim()) {
      setError('Enter a phone number so the store can reach you.')
      return
    }
    setSubmitting(true)
    try {
      await onSubmitOrder({
        customerName: name.trim(),
        phone: phone.trim(),
        fulfillmentMethod: method,
        deliveryAddress: method === 'delivery' ? note.trim() : null,
        note: note.trim(),
      })
      pushToast('Order placed successfully')
    } catch (err) {
      setError(err.message || 'Could not submit your order.')
    } finally {
      setSubmitting(false)
    }
  }

  if (submitted) {
    const ref = lastOrder?.orderNumber || ''
    return (
      <div className="cart-footer">
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
            Order placed successfully!
            <br />
            Reference: <b>{ref}</b>
          </div>
        </div>
        {whatsappConfirmUrl && (
          <a
            className="btn btn-whatsapp btn-block"
            href={whatsappConfirmUrl}
            target="_blank"
            rel="noopener noreferrer"
          >
            <svg fill="currentColor" viewBox="0 0 24 24">
              <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51l-.57-.01c-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893A11.821 11.821 0 0020.464 3.488" />
            </svg>
            Confirm order on WhatsApp
          </a>
        )}
        <button type="button" className="btn btn-ghost btn-block" onClick={() => window.location.reload()}>
          Place another order
        </button>
      </div>
    )
  }

  return (
    <div className="cart-footer">
      <form className="checkout-form" onSubmit={submit}>
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

        <label className="field">
          <span className="field-label">Your name</span>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Jane Wanjiru"
            autoComplete="name"
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
            autoComplete="tel"
            required
          />
        </label>

        <div className="field">
          <span className="field-label">Fulfillment</span>
          <div className="radio-row">
            {FULFILLMENT_OPTIONS.map((opt) => (
              <label key={opt.value} className="radio-pill">
                <input
                  type="radio"
                  name="fulfillment"
                  value={opt.value}
                  checked={method === opt.value}
                  onChange={() => setMethod(opt.value)}
                />
                <span>{opt.label}</span>
              </label>
            ))}
          </div>
        </div>

        <label className="field">
          <span className="field-label">
            {method === 'delivery' ? 'Delivery address' : 'Order note (optional)'}
          </span>
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder={method === 'delivery' ? 'Building, street, area, landmark...' : 'Any special instructions'}
            rows={2}
          />
        </label>

        <div className="checkout-total">
          <span>Total</span>
          <strong>{money(total)}</strong>
        </div>

        <button type="submit" className="btn btn-primary btn-block" disabled={submitting}>
          {submitting ? 'Processing...' : 'Place order'}
        </button>
        <p className="checkout-disclaimer">
          The store will confirm availability and payment before fulfillment.
        </p>
      </form>
    </div>
  )
}
