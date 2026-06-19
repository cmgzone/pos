import type { Catalog, Order, OrderPayload } from "./types";

function getApiBase(): string {
  if (typeof window === "undefined") return "";
  return "/api";
}

function buildUrl(path: string): string {
  return `${getApiBase()}${path}`;
}

export async function fetchCatalog(
  businessId: string,
  branchId?: string
): Promise<Catalog> {
  const params = new URLSearchParams();
  if (branchId) params.set("branchId", branchId);
  const query = params.toString() ? `?${params.toString()}` : "";
  const res = await fetch(buildUrl(`/public/catalog/${businessId}${query}`));
  const json = await res.json();
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Failed to load catalog");
  }
  return json.data;
}

export async function placeOrder(
  businessId: string,
  payload: OrderPayload
): Promise<{ orderNumber: string }> {
  const res = await fetch(
    buildUrl(`/public/catalog/${businessId}/orders`),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }
  );
  const json = await res.json();
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Failed to place order");
  }
  return json.data;
}

export async function trackOrder(
  businessId: string,
  orderNumber: string,
  phone: string
): Promise<Order> {
  const res = await fetch(
    buildUrl(
      `/public/catalog/${businessId}/orders/${orderNumber}?phone=${encodeURIComponent(
        phone
      )}`
    )
  );
  const json = await res.json();
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Order not found");
  }
  return json.data;
}
