import { useCallback, useEffect, useMemo, useRef, useState } from 'react'

import { fetchCatalog, placeOrder, readInitialCatalog, trackOrder, resolveStorefrontTarget } from './api'
import {
  cartKey,
  classNames,
  clearPersistedCart,
  formatMoney,
  isItemAvailable,
  itemCategory,
  loadPersistedCart,
  persistCart,
  primaryPrice,
  reconcileCart,
  useDebounce,
  whatsappUrl,
} from './utils'
import Header from './components/Header.jsx'
import Toolbar from './components/Toolbar.jsx'
import StorefrontSections from './components/StorefrontSections.jsx'
import ProductGrid from './components/ProductGrid.jsx'
import QuickView from './components/QuickView.jsx'
import Cart from './components/Cart.jsx'
import Toasts from './components/Toasts.jsx'

const FREE_SHIP_FALLBACK = 0
const SORT_OPTIONS = [
  { value: 'default', label: 'Featured' },
  { value: 'price-asc', label: 'Price: Low to High' },
  { value: 'price-desc', label: 'Price: High to Low' },
  { value: 'name-asc', label: 'Name: A to Z' },
  { value: 'name-desc', label: 'Name: Z to A' },
]

export default function App() {
  const target = useMemo(() => resolveStorefrontTarget(), [])
  const initialCatalog = useMemo(() => readInitialCatalog(), [])
  const initialBranchId = initialCatalog?.business?.selectedBranch?.id || target.branchId || null

  const [catalog, setCatalog] = useState(initialCatalog)
  const [loading, setLoading] = useState(!initialCatalog)
  const [loadError, setLoadError] = useState(null)
  const [branchId, setBranchId] = useState(initialBranchId)
  const [switchingBranch, setSwitchingBranch] = useState(false)

  const [activeCategory, setActiveCategory] = useState('all')
  const [searchQuery, setSearchQuery] = useState('')
  const debouncedSearchQuery = useDebounce(searchQuery, 250)
  const [sort, setSort] = useState('default')

  const [cart, setCart] = useState(() => loadPersistedCart(target.businessId) || new Map())
  const [isCartOpen, setIsCartOpen] = useState(false)
  const [quickView, setQuickView] = useState(null)
  const [toasts, setToasts] = useState([])
  const toastIdRef = useRef(0)

  const [lastOrder, setLastOrder] = useState(null)
  const hasLoadedRef = useRef(Boolean(initialCatalog))

  const pushToast = useCallback((message, type = 'success') => {
    toastIdRef.current += 1
    const id = toastIdRef.current
    setToasts((prev) => [...prev, { id, message, type }])
    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id))
    }, 2600)
  }, [])

  const loadCatalog = useCallback(
    async (options = {}) => {
      const useBranchId = options.branchId !== undefined ? options.branchId : branchId
      if (!options.silent) {
        if (hasLoadedRef.current) setSwitchingBranch(true)
        else setLoading(true)
      }
      try {
        const data = await fetchCatalog({
          businessId: target.businessId || null,
          branchId: useBranchId,
        })
        setCatalog(data)
        setBranchId(data.business?.selectedBranch?.id || useBranchId || null)
        setLoadError(null)
        hasLoadedRef.current = true
      } catch (error) {
        if (options.silent && hasLoadedRef.current) {
          console.warn('Could not refresh storefront catalog:', error)
        } else {
          setLoadError(error.message || 'Could not load the store catalog.')
          setCatalog(null)
        }
      } finally {
        setLoading(false)
        setSwitchingBranch(false)
      }
    },
    [branchId, target.businessId],
  )

  useEffect(() => {
    loadCatalog({ silent: Boolean(initialCatalog) })
  }, [initialCatalog, loadCatalog])

  useEffect(() => {
    if (!catalog?.business?.id) return
    persistCart(catalog.business.id, cart)
  }, [catalog?.business?.id, cart])

  useEffect(() => {
    if (!catalog?.products) return
    setCart((prev) => reconcileCart(prev, catalog.products))
  }, [catalog?.products])

  const brand = catalog?.business?.brand || {}
  const primaryColor = brand.primaryColor || '#111827'
  const freeShipThreshold = catalog?.freeShipThreshold || FREE_SHIP_FALLBACK
  const currencyCode = catalog?.currencyCode || catalog?.currency || 'KES'
  const currencySymbol = catalog?.currencySymbol || ''
  const branches = catalog?.business?.branches || []
  const whatsappNumber = catalog?.business?.whatsappNumber || ''

  const money = useCallback(
    (amount) => formatMoney(amount, { currencyCode, currencySymbol }),
    [currencyCode, currencySymbol],
  )

  useEffect(() => {
    if (primaryColor) {
      document.documentElement.style.setProperty('--primary', primaryColor)
      document.documentElement.style.setProperty(
        '--primary-soft',
        `color-mix(in srgb, ${primaryColor} 12%, #ffffff)`,
      )
      document.documentElement.style.setProperty(
        '--primary-ring',
        `color-mix(in srgb, ${primaryColor} 32%, #ffffff)`,
      )
      const themeMeta = document.querySelector('meta[name="theme-color"]')
      if (themeMeta) themeMeta.setAttribute('content', primaryColor)
    }
    if (catalog?.business?.name) {
      document.title = `${catalog.business.name} - Online Store`
    }
  }, [primaryColor, catalog?.business?.name])

  const categories = useMemo(() => {
    if (!catalog?.products) return []
    const counts = new Map()
    catalog.products.forEach((item) => {
      const cat = itemCategory(item)
      counts.set(cat, (counts.get(cat) || 0) + 1)
    })
    return Array.from(counts.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([name, count]) => ({ name, count }))
  }, [catalog])

  const visibleItems = useMemo(() => {
    if (!catalog?.products) return []
    const query = debouncedSearchQuery.toLowerCase().trim()
    let items = catalog.products.filter((item) => {
      const cat = itemCategory(item)
      const matchCat = activeCategory === 'all' || cat === activeCategory
      const matchSearch =
        !query ||
        String(item.name || '').toLowerCase().includes(query) ||
        String(item.brand || '').toLowerCase().includes(query) ||
        String(item.description || '').toLowerCase().includes(query) ||
        cat.toLowerCase().includes(query)
      return matchCat && matchSearch
    })
    switch (sort) {
      case 'price-asc':
        items = items.slice().sort((a, b) => primaryPrice(a) - primaryPrice(b))
        break
      case 'price-desc':
        items = items.slice().sort((a, b) => primaryPrice(b) - primaryPrice(a))
        break
      case 'name-asc':
        items = items.slice().sort((a, b) => String(a.name || '').localeCompare(String(b.name || '')))
        break
      case 'name-desc':
        items = items.slice().sort((a, b) => String(b.name || '').localeCompare(String(a.name || '')))
        break
      default:
        items = items.slice().sort((a, b) => {
          const featured = Number(Boolean(b.isFeatured)) - Number(Boolean(a.isFeatured))
          if (featured !== 0) return featured
          const sold = Number(b.soldQty || 0) - Number(a.soldQty || 0)
          if (sold !== 0) return sold
          return String(a.name || '').localeCompare(String(b.name || ''))
        })
        break
    }
    return items
  }, [catalog, activeCategory, debouncedSearchQuery, sort])

  const featuredItems = useMemo(() => {
    if (!catalog?.products || debouncedSearchQuery || activeCategory !== 'all') return []
    return catalog.products.filter((item) => item.isFeatured).slice(0, 8)
  }, [catalog, debouncedSearchQuery, activeCategory])

  const bestSellingItems = useMemo(() => {
    if (!catalog?.products || debouncedSearchQuery || activeCategory !== 'all') return []
    return catalog.products
      .filter((item) => Number(item.soldQty || 0) > 0)
      .slice()
      .sort((a, b) => Number(b.soldQty || 0) - Number(a.soldQty || 0))
      .slice(0, 8)
  }, [catalog, debouncedSearchQuery, activeCategory])

  const cartItems = useMemo(() => Array.from(cart.values()), [cart])
  const cartCount = useMemo(() => cartItems.reduce((sum, entry) => sum + entry.qty, 0), [cartItems])
  const cartTotal = useMemo(
    () =>
      cartItems.reduce((sum, entry) => {
        const price = entry.variant ? entry.variant.price : entry.item.price
        return sum + price * entry.qty
      }, 0),
    [cartItems],
  )

  const addToCart = useCallback(
    (item, variantId = null) => {
      if (!isItemAvailable(item)) {
        pushToast('This item is not available right now', 'error')
        return
      }
      const variant = variantId && item.variants ? item.variants.find((v) => v.id === variantId) : null
      if (variant && variant.available === false) {
        pushToast('This variant is out of stock', 'error')
        return
      }
      const key = cartKey(item, variantId)
      setCart((prev) => {
        const next = new Map(prev)
        const existing = next.get(key)
        next.set(key, {
          item,
          variant,
          qty: existing ? existing.qty + 1 : 1,
        })
        return next
      })
      setLastOrder(null)
      const label = variant ? `${item.name} (${variant.name}) added` : `${item.name} added`
      pushToast(label)
      if (window.innerWidth <= 768) setIsCartOpen(true)
    },
    [pushToast],
  )

  const updateQty = useCallback((key, delta) => {
    setCart((prev) => {
      const next = new Map(prev)
      const existing = next.get(key)
      if (!existing) return prev
      const newQty = existing.qty + delta
      if (newQty <= 0) next.delete(key)
      else next.set(key, { ...existing, qty: newQty })
      return next
    })
  }, [])

  const removeItem = useCallback((key) => {
    setCart((prev) => {
      const next = new Map(prev)
      next.delete(key)
      return next
    })
  }, [])

  const clearFilters = useCallback(() => {
    setSearchQuery('')
    setActiveCategory('all')
    setSort('default')
  }, [])

  const submitOrder = useCallback(
    async ({ customerName, phone, fulfillmentMethod, deliveryAddress, note }) => {
      if (!catalog?.business?.id || cartItems.length === 0) return
      const items = cartItems.map((entry) => ({
        itemType: entry.item.type || 'product',
        productId: entry.item.type === 'service' ? null : entry.item.id,
        serviceId: entry.item.type === 'service' ? entry.item.serviceId : null,
        variantId: entry.variant ? entry.variant.id : null,
        quantity: entry.qty,
      }))
      const order = await placeOrder({
        businessId: catalog.business.id,
        branchId: catalog.business.selectedBranch?.id || branchId,
        customerName,
        phone,
        fulfillmentMethod,
        deliveryAddress,
        note,
        items,
      })
      setCart(new Map())
      if (catalog?.business?.id) clearPersistedCart(catalog.business.id)
      setLastOrder(order)
      return order
    },
    [catalog, cartItems, branchId],
  )

  const handleTrackOrder = useCallback(
    async ({ orderNumber, phone }) => {
      if (!catalog?.business?.id) throw new Error('Store is not loaded yet.')
      return trackOrder({
        businessId: catalog.business.id,
        orderNumber,
        phone,
      })
    },
    [catalog],
  )

  const switchBranch = useCallback(
    (nextBranchId) => {
      if (!nextBranchId || nextBranchId === branchId) return
      setBranchId(nextBranchId)
      loadCatalog({ branchId: nextBranchId })
    },
    [branchId, loadCatalog],
  )

  const closeCart = useCallback(() => setIsCartOpen(false), [])
  const openCart = useCallback(() => setIsCartOpen(true), [])

  const confirmWhatsApp = useCallback(
    (orderNumber) => {
      if (!whatsappNumber) return null
      return whatsappUrl(whatsappNumber, `Hi, I just placed an order (${orderNumber}) on your online store. Please confirm.`)
    },
    [whatsappNumber],
  )

  return (
    <div className={classNames('app', loading && 'is-loading')}>
      <Header catalog={catalog} loading={loading} error={loadError} />

      {!loadError && (
        <Toolbar
          categories={categories}
          activeCategory={activeCategory}
          onCategory={setActiveCategory}
          searchQuery={searchQuery}
          onSearch={setSearchQuery}
          sort={sort}
          onSort={setSort}
          sortOptions={SORT_OPTIONS}
          onClear={clearFilters}
          branches={branches}
          branchId={branchId}
          onBranch={switchBranch}
          switchingBranch={switchingBranch}
          cartCount={cartCount}
          onOpenCart={openCart}
          resultCount={visibleItems.length}
        />
      )}

      {!loadError && !loading && !switchingBranch && (
        <StorefrontSections
          categories={categories}
          featuredItems={featuredItems}
          bestSellingItems={bestSellingItems}
          money={money}
          onCategory={setActiveCategory}
          onQuickView={setQuickView}
        />
      )}

      {!loadError && (
        <ProductGrid
          items={visibleItems}
          loading={loading || switchingBranch}
          money={money}
          onAdd={addToCart}
          onQuickView={setQuickView}
          activeCategory={activeCategory}
          hasFilters={Boolean(searchQuery) || activeCategory !== 'all'}
          onClear={clearFilters}
        />
      )}

      <Cart
        open={isCartOpen}
        onClose={closeCart}
        items={cartItems}
        total={cartTotal}
        money={money}
        onUpdateQty={updateQty}
        onRemove={removeItem}
        onSubmitOrder={submitOrder}
        onTrackOrder={handleTrackOrder}
        lastOrder={lastOrder}
        whatsappConfirmUrl={lastOrder ? confirmWhatsApp(lastOrder.orderNumber) : null}
        freeShipThreshold={freeShipThreshold}
        pushToast={pushToast}
      />

      <QuickView item={quickView} money={money} onClose={() => setQuickView(null)} onAdd={addToCart} />

      <Toasts toasts={toasts} />

      <button
        type="button"
        className={classNames('cart-fab', cartCount > 0 && 'is-visible')}
        onClick={openCart}
        aria-label={`Open cart, ${cartCount} items`}
      >
        <svg fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-9 2a2 2 0 11-4 0 2 2 0 014 0z"
          />
        </svg>
        <span className={classNames('cart-fab-count', cartCount === 0 && 'is-empty')}>{cartCount}</span>
      </button>
    </div>
  )
}
