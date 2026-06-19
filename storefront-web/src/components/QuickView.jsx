import { useEffect, useState } from 'react'
import { classNames, isItemAvailable, primaryPrice } from '../utils'
import SafeImage from './SafeImage.jsx'

export default function QuickView({ item, money, onClose, onAdd }) {
  const [variantId, setVariantId] = useState(null)
  const [activeImageIndex, setActiveImageIndex] = useState(0)

  useEffect(() => {
    if (item && item.hasVariants && Array.isArray(item.variants) && item.variants.length > 0) {
      setVariantId(item.variants[0].id)
    } else {
      setVariantId(null)
    }
    setActiveImageIndex(0)
  }, [item])

  useEffect(() => {
    if (!item) return undefined
    const onKey = (e) => {
      if (e.key === 'Escape') onClose()
    }
    document.addEventListener('keydown', onKey)
    document.body.style.overflow = 'hidden'
    return () => {
      document.removeEventListener('keydown', onKey)
      document.body.style.overflow = ''
    }
  }, [item, onClose])

  if (!item) return null

  const variants = item.hasVariants && Array.isArray(item.variants) ? item.variants : []
  const selectedVariant = variantId ? variants.find((v) => v.id === variantId) : null
  const price = selectedVariant ? selectedVariant.price : primaryPrice(item)
  const available = selectedVariant ? selectedVariant.available !== false : isItemAvailable(item)
  const isService = item.type === 'service'
  const imageUrls = Array.isArray(item.imageUrls) && item.imageUrls.length
    ? item.imageUrls
    : item.imageUrl
      ? [item.imageUrl]
      : []
  const activeImage = imageUrls[activeImageIndex] || imageUrls[0]

  const handleAdd = () => {
    if (!available) return
    onAdd(item, variantId)
    onClose()
  }

  return (
    <div className="qv-backdrop" onClick={onClose} role="dialog" aria-modal="true" aria-label={item.name}>
      <div className="qv-modal" onClick={(e) => e.stopPropagation()}>
        <button type="button" className="qv-close" onClick={onClose} aria-label="Close">
          <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
        <div className="qv-media">
          <div className="qv-media-main">
            <SafeImage src={activeImage} alt={item.name} className="qv-img" />
          </div>
          {imageUrls.length > 1 && (
            <div className="qv-thumbs">
              {imageUrls.map((url, index) => (
                <button
                  type="button"
                  key={`${url}-${index}`}
                  className={classNames(index === activeImageIndex && 'active')}
                  onClick={() => setActiveImageIndex(index)}
                  aria-label={`Show product photo ${index + 1}`}
                >
                  <SafeImage src={url} alt="" className="qv-thumb-img" />
                </button>
              ))}
            </div>
          )}
        </div>
        <div className="qv-body">
          {item.brand && item.brand !== 'Service' && <div className="card-brand">{item.brand}</div>}
          <h2 className="qv-title">{item.name}</h2>
          {(item.description || item.summary) && <p className="qv-summary">{item.description || item.summary}</p>}
          <div className="qv-price-row">
            <span className="price">{money(price)}</span>
            <span className="price-sub">{isService ? 'per service' : item.unit || 'each'}</span>
          </div>
          {variants.length > 0 && (
            <label className="qv-variants">
              <span className="qv-label">Choose option</span>
              <select value={variantId || ''} onChange={(e) => setVariantId(e.target.value)}>
                {variants.map((v) => (
                  <option key={v.id} value={v.id} disabled={v.available === false}>
                    {v.name} - {money(v.price)}{v.available === false ? ' (out of stock)' : ''}
                  </option>
                ))}
              </select>
            </label>
          )}
          <button
            type="button"
            className={classNames('btn btn-primary btn-block', !available && 'is-disabled')}
            onClick={handleAdd}
            disabled={!available}
          >
            {available ? 'Add to cart' : 'Not available'}
          </button>
          <p className="qv-note">
            Send your order and the store will confirm availability, total, and payment before fulfillment.
          </p>
        </div>
      </div>
    </div>
  )
}
