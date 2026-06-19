// Shared helpers for the storefront UI.
import { useEffect, useState } from 'react'

export function formatMoney(amount, { currencyCode, currencySymbol } = {}) {
  const value = Number(amount || 0)
  if (currencySymbol && String(currencySymbol).trim()) {
    return `${currencySymbol}${value.toLocaleString('en', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })}`
  }
  try {
    return new Intl.NumberFormat('en', { style: 'currency', currency: currencyCode || 'KES' }).format(value)
  } catch {
    return `${currencyCode || 'KES'} ${value.toLocaleString('en', { minimumFractionDigits: 2 })}`
  }
}

export function classNames(...parts) {
  return parts.filter(Boolean).join(' ')
}

export function itemCategory(item) {
  if (item && item.category && item.category !== 'Services') return item.category
  if (item && item.type === 'service') return 'Services'
  return 'Other'
}

export function isItemAvailable(item) {
  return Boolean(item) && item.availability === 'Available'
}

export function primaryPrice(item) {
  if (!item) return 0
  if (item.hasVariants && Array.isArray(item.variants) && item.variants.length > 0) {
    return Number(item.variants[0].price || 0)
  }
  return Number(item.price || 0)
}

export function cartKey(item, variantId) {
  return `${item.id}:${variantId || ''}`
}

export function normalizePhone(value) {
  return String(value || '').replace(/\D/g, '')
}

export function whatsappUrl(number, text) {
  const digits = normalizePhone(number)
  if (!digits) return null
  const url = new URL(`https://wa.me/${digits}`)
  if (text) url.searchParams.set('text', text)
  return url.toString()
}

export function cartStorageKey(businessId) {
  return `piki-storefront-cart:${businessId || 'unknown'}`
}

export function serializeCart(cart) {
  return Array.from(cart.values()).map((entry) => ({
    item: entry.item,
    variant: entry.variant || null,
    qty: entry.qty,
  }))
}

export function deserializeCart(items) {
  const map = new Map()
  if (!Array.isArray(items)) return map
  for (const entry of items) {
    if (!entry || !entry.item) continue
    const variant = entry.variant || null
    const key = cartKey(entry.item, variant ? variant.id : null)
    map.set(key, {
      item: entry.item,
      variant,
      qty: Math.max(1, Math.round(Number(entry.qty) || 1)),
    })
  }
  return map
}

export function loadPersistedCart(businessId) {
  if (typeof window === 'undefined' || !businessId) return null
  try {
    const raw = window.localStorage.getItem(cartStorageKey(businessId))
    if (!raw) return null
    return deserializeCart(JSON.parse(raw))
  } catch {
    return null
  }
}

export function persistCart(businessId, cart) {
  if (typeof window === 'undefined' || !businessId) return
  try {
    window.localStorage.setItem(cartStorageKey(businessId), JSON.stringify(serializeCart(cart)))
  } catch {
    // Ignore storage errors (e.g. quota exceeded).
  }
}

export function clearPersistedCart(businessId) {
  if (typeof window === 'undefined' || !businessId) return
  try {
    window.localStorage.removeItem(cartStorageKey(businessId))
  } catch {
    // Ignore.
  }
}

export function useDebounce(value, delay = 300) {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(timer)
  }, [value, delay])
  return debounced
}

export function reconcileCart(cart, products) {
  if (!products || products.length === 0) return cart
  const catalogMap = new Map(products.map((item) => [String(item.id), item]))
  const next = new Map()
  for (const [, entry] of cart.entries()) {
    const currentItem = catalogMap.get(String(entry.item.id))
    if (!currentItem) continue
    const variant = entry.variant
      ? (currentItem.variants || []).find((v) => String(v.id) === String(entry.variant.id))
      : null
    if (entry.variant && !variant) continue
    next.set(cartKey(currentItem, variant ? variant.id : null), {
      item: currentItem,
      variant,
      qty: entry.qty,
    })
  }
  return next
}
