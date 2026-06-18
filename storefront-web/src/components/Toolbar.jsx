import { classNames } from '../utils'

export default function Toolbar({
  categories,
  activeCategory,
  onCategory,
  searchQuery,
  onSearch,
  sort,
  onSort,
  sortOptions,
  onClear,
  branches,
  branchId,
  onBranch,
  switchingBranch,
  cartCount,
  onOpenCart,
  resultCount,
}) {
  const hasFilters = Boolean(searchQuery) || activeCategory !== 'all'

  return (
    <div className="top-stack">
      <div className="navbar">
        <div className="wrap nav-inner">
          <label className="search search-desktop">
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M21 21l-4.35-4.35M11 19a8 8 0 100-16 8 8 0 000 16z"
              />
            </svg>
            <input
              type="search"
              placeholder="Search products, brands, categories..."
              value={searchQuery}
              onChange={(e) => onSearch(e.target.value)}
              aria-label="Search products"
            />
          </label>

          {branches.length > 1 && (
            <label className="branch-select">
              <span className="sr-only">Branch</span>
              <select value={branchId || ''} onChange={(e) => onBranch(e.target.value)} disabled={switchingBranch}>
                {branches.map((branch) => (
                  <option key={branch.id} value={branch.id}>
                    {branch.name}
                  </option>
                ))}
              </select>
            </label>
          )}

          <div className="sort">
            <label className="sr-only" htmlFor="sort-select">
              Sort
            </label>
            <select id="sort-select" value={sort} onChange={(e) => onSort(e.target.value)}>
              {sortOptions.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label}
                </option>
              ))}
            </select>
          </div>

          <button type="button" className="cart-btn" onClick={onOpenCart} aria-label={`Cart, ${cartCount} items`}>
            <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-9 2a2 2 0 11-4 0 2 2 0 014 0z"
              />
            </svg>
            <span className={classNames('cart-count', cartCount === 0 && 'is-empty')}>{cartCount}</span>
          </button>
        </div>
      </div>

      <div className="cat-bar">
        <div className="wrap cat-inner">
          <button
            type="button"
            className={classNames('cat-btn', activeCategory === 'all' && 'active')}
            onClick={() => onCategory('all')}
          >
            All
          </button>
          {categories.map((cat) => (
            <button
              key={cat.name}
              type="button"
              className={classNames('cat-btn', activeCategory === cat.name && 'active')}
              onClick={() => onCategory(cat.name)}
            >
              {cat.name}
              <span className="cat-count">{cat.count}</span>
            </button>
          ))}
        </div>
      </div>

      <div className="wrap result-row">
        <span className="result-count">
          {resultCount} item{resultCount === 1 ? '' : 's'}
        </span>
        {hasFilters && (
          <button type="button" className="clear-btn" onClick={onClear}>
            Clear filters
          </button>
        )}
      </div>

      <label className="search search-mobile">
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M21 21l-4.35-4.35M11 19a8 8 0 100-16 8 8 0 000 16z"
          />
        </svg>
        <input
          type="search"
          placeholder="Search this store..."
          value={searchQuery}
          onChange={(e) => onSearch(e.target.value)}
          aria-label="Search products"
        />
      </label>
    </div>
  )
}
