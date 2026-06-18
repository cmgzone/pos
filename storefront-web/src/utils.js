// Shared helpers for the storefront UI.

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
