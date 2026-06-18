import { classNames, isItemAvailable, primaryPrice } from '../utils'

function Placeholder() {
  return (
    <div className="card-media-ph" aria-hidden="true">
      <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={1.6}
          d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
        />
      </svg>
    </div>
  )
}

export function ProductCard({ item, money, onAdd, onQuickView }) {
  const available = isItemAvailable(item)
  const isService = item.type === 'service'
  const variants = item.hasVariants && Array.isArray(item.variants) ? item.variants : []
  const price = primaryPrice(item)

  return (
    <article
      className={classNames('card', !available && 'is-unavailable')}
      onClick={() => onQuickView(item)}
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          onQuickView(item)
        }
      }}
    >
      <div className="card-media">
        {item.imageUrl ? (
          <img src={item.imageUrl} loading="lazy" alt={item.name} />
        ) : (
          <Placeholder />
        )}
        <div className="tag-row">
          {isService ? (
            <span className="chip service">Service</span>
          ) : (
            item.category && <span className="chip cat">{item.category}</span>
          )}
          {!available && <span className="chip unavailable">Ask for availability</span>}
        </div>
        <button
          type="button"
          className="quick-view-btn"
          onClick={(e) => {
            e.stopPropagation()
            onQuickView(item)
          }}
          aria-label={`View ${item.name}`}
        >
          Quick view
        </button>
      </div>
      <div className="card-body">
        {item.brand && item.brand !== 'Service' && <div className="card-brand">{item.brand}</div>}
        <h3 className="card-title">{item.name}</h3>
        {isService && item.summary && <p className="card-summary">{item.summary}</p>}
        {item.hasVariants && variants.length > 1 && (
          <div className="card-variant-note">{variants.length} options from {money(variants[0].price)}</div>
        )}
        <div className="card-foot">
          <div className="price-stack">
            <span className="price">{money(price)}</span>
            <span className="price-sub">{isService ? 'per service' : item.unit || 'each'}</span>
          </div>
          <button
            type="button"
            className="add-round"
            onClick={(e) => {
              e.stopPropagation()
              if (item.hasVariants && variants.length > 0) {
                onQuickView(item)
              } else {
                onAdd(item, null)
              }
            }}
            aria-label={`Add ${item.name} to cart`}
          >
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.2} d="M12 4v16m8-8H4" />
            </svg>
          </button>
        </div>
      </div>
    </article>
  )
}

export default function ProductGrid({ items, loading, money, onAdd, onQuickView, hasFilters, onClear }) {
  if (loading) {
    return (
      <section className="grid-section">
        <div className="wrap">
          <div className="grid">
            {Array.from({ length: 8 }).map((_, i) => (
              <div className="card skeleton" key={i}>
                <div className="card-media skeleton-box" />
                <div className="card-body">
                  <div className="skeleton-line w-sm" />
                  <div className="skeleton-line w-lg" />
                  <div className="skeleton-line w-md" />
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>
    )
  }

  if (items.length === 0) {
    return (
      <section className="grid-section">
        <div className="wrap">
          <div className="empty-state">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.6}
                d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
              />
            </svg>
            <h2>No items match your search</h2>
            <p>Try a different keyword or clear the filters.</p>
            {hasFilters && (
              <button type="button" className="btn btn-primary" onClick={onClear}>
                Clear filters
              </button>
            )}
          </div>
        </div>
      </section>
    )
  }

  return (
    <section className="grid-section" id="catalog-head">
      <div className="wrap">
        <div className="grid">
          {items.map((item) => (
            <ProductCard key={item.id} item={item} money={money} onAdd={onAdd} onQuickView={onQuickView} />
          ))}
        </div>
      </div>
    </section>
  )
}
