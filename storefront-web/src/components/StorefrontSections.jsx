import { classNames, itemCategory, primaryPrice } from '../utils'

function itemImages(item) {
  if (Array.isArray(item.imageUrls) && item.imageUrls.length) return item.imageUrls
  return item.imageUrl ? [item.imageUrl] : []
}

function MiniProduct({ item, money, onQuickView, badge }) {
  const imageUrls = itemImages(item)
  const imageUrl = imageUrls[0]
  const soldQty = Number(item.soldQty || 0)

  return (
    <button type="button" className="mini-product" onClick={() => onQuickView(item)}>
      <span className="mini-media">
        {imageUrl ? <img src={imageUrl} alt="" loading="lazy" /> : <span>{String(item.name || 'P').charAt(0)}</span>}
        {imageUrls.length > 1 && <em>{imageUrls.length}</em>}
      </span>
      <span className="mini-copy">
        <span className="mini-badge">{badge || (soldQty > 0 ? `${soldQty.toLocaleString()} sold` : 'Featured')}</span>
        <strong>{item.name}</strong>
        {item.description && <small>{item.description}</small>}
        <b>{money(primaryPrice(item))}</b>
      </span>
    </button>
  )
}

function ProductRail({ title, items, money, onQuickView, badge }) {
  if (!items.length) return null
  return (
    <section className="feature-section">
      <div className="wrap">
        <div className="section-title-row">
          <h2>{title}</h2>
        </div>
        <div className="mini-rail">
          {items.map((item) => (
            <MiniProduct key={`${title}-${item.id}`} item={item} money={money} onQuickView={onQuickView} badge={badge} />
          ))}
        </div>
      </div>
    </section>
  )
}

export default function StorefrontSections({
  categories,
  featuredItems,
  bestSellingItems,
  money,
  onCategory,
  onQuickView,
}) {
  const hasCategories = categories.length > 0
  const hasRails = featuredItems.length > 0 || bestSellingItems.length > 0
  if (!hasCategories && !hasRails) return null

  return (
    <div className="store-sections">
      <ProductRail title="Featured products" items={featuredItems} money={money} onQuickView={onQuickView} badge="Featured" />
      <ProductRail title="Most selling products" items={bestSellingItems} money={money} onQuickView={onQuickView} />
      {hasCategories && (
        <section className={classNames('feature-section', !hasRails && 'is-first')}>
          <div className="wrap">
            <div className="section-title-row">
              <h2>Categories</h2>
            </div>
            <div className="category-tiles">
              {categories.map((cat) => (
                <button key={cat.name} type="button" className="category-tile" onClick={() => onCategory(cat.name)}>
                  <span>{itemCategory({ category: cat.name }).charAt(0)}</span>
                  <strong>{cat.name}</strong>
                  <small>{cat.count} item{cat.count === 1 ? '' : 's'}</small>
                </button>
              ))}
            </div>
          </div>
        </section>
      )}
    </div>
  )
}
