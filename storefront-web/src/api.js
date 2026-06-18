// Storefront API client. Consumes the existing backend catalog endpoints:
//   GET  /api/public/catalog            (subdomain-resolved)
//   GET  /api/public/catalog/:businessId (legacy path link)
//   POST /api/public/catalog/:businessId/orders
//   GET  /api/public/catalog/:businessId/orders/:orderNumber?phone=...

function readBootstrap() {
  if (typeof window !== 'undefined' && window.__STOREFRONT__) {
    return window.__STOREFRONT__
  }
  return null
}

function readBusinessIdFromPath() {
  if (typeof window === 'undefined') return null
  const match = window.location.pathname.match(/^\/catalog\/([^/?#]+)/)
  return match ? decodeURIComponent(match[1]) : null
}

export function resolveStorefrontTarget() {
  const boot = readBootstrap()
  if (boot && boot.businessId) {
    return { businessId: boot.businessId, branchId: boot.branchId || null, subdomain: boot.subdomain || null }
  }
  return { businessId: readBusinessIdFromPath(), branchId: null, subdomain: null }
}

async function parseJson(res) {
  const text = await res.text()
  let data = null
  if (text) {
    try {
      data = JSON.parse(text)
    } catch {
      data = null
    }
  }
  return data
}

function errorMessage(data, fallback) {
  if (!data) return fallback
  return data.message || data.error || fallback
}

export async function fetchCatalog({ businessId, branchId } = {}) {
  const target = businessId
    ? `/api/public/catalog/${encodeURIComponent(businessId)}`
    : '/api/public/catalog'
  const params = new URLSearchParams()
  if (branchId) params.set('branchId', branchId)
  const qs = params.toString()
  const url = qs ? `${target}?${qs}` : target

  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  const data = await parseJson(res)
  if (!res.ok || !data || data.ok === false) {
    throw new Error(errorMessage(data, 'Could not load the store catalog.'))
  }
  return data.data
}

export async function placeOrder({ businessId, branchId, customerName, phone, fulfillmentMethod, deliveryAddress, note, items }) {
  const res = await fetch(`/api/public/catalog/${encodeURIComponent(businessId)}/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      branchId: branchId || null,
      customerName,
      phone,
      fulfillmentMethod,
      deliveryAddress,
      note,
      items,
    }),
  })
  const data = await parseJson(res)
  if (!res.ok || !data || data.ok === false) {
    throw new Error(errorMessage(data, 'Could not submit your order.'))
  }
  return data.data
}

export async function trackOrder({ businessId, orderNumber, phone }) {
  const params = new URLSearchParams({ phone })
  const res = await fetch(
    `/api/public/catalog/${encodeURIComponent(businessId)}/orders/${encodeURIComponent(orderNumber)}?${params.toString()}`,
  )
  const data = await parseJson(res)
  if (!res.ok || !data || data.ok === false) {
    throw new Error(errorMessage(data, 'Order not found. Check the order number and phone.'))
  }
  return data.data
}
