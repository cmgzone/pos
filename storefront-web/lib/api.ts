import type { Catalog, Order, OrderPayload } from "./types";

interface ApiJsonResponse {
  ok?: boolean;
  data?: unknown;
  message?: string;
  error?: string;
}

function getApiBase(): string {
  if (typeof window === "undefined") return "";
  if (process.env.NEXT_PUBLIC_API_BASE_URL) return process.env.NEXT_PUBLIC_API_BASE_URL;
  return "/api";
}

function buildUrl(path: string): string {
  return `${getApiBase()}${path}`;
}

async function readApiJson(res: Response): Promise<ApiJsonResponse> {
  const text = await res.text();
  if (!text.trim()) return {};
  try {
    return JSON.parse(text) as ApiJsonResponse;
  } catch {
    throw new Error("Server returned an invalid response. Please try again.");
  }
}

export async function fetchCatalog(
  businessId: string,
  branchId?: string
): Promise<Catalog> {
  const params = new URLSearchParams();
  if (branchId) params.set("branchId", branchId);
  const query = params.toString() ? `?${params.toString()}` : "";
  const res = await fetch(
    buildUrl(`/public/catalog/${encodeURIComponent(businessId)}${query}`)
  );
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Failed to load catalog");
  }
  return json.data as Catalog;
}

export async function placeOrder(
  businessId: string,
  payload: OrderPayload
): Promise<{ orderNumber: string }> {
  const res = await fetch(
    buildUrl(`/public/catalog/${encodeURIComponent(businessId)}/orders`),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }
  );
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Failed to place order");
  }
  return json.data as { orderNumber: string };
}

export async function trackOrder(
  businessId: string,
  orderNumber: string,
  phone: string
): Promise<Order> {
  const cleanOrderNumber = orderNumber.trim().replace(/^#+\s*/, "");
  const cleanPhone = phone.trim();
  if (!cleanOrderNumber) {
    throw new Error("Enter a valid order number.");
  }
  if (!cleanPhone) {
    throw new Error("Enter the phone number used for the order.");
  }
  const params = new URLSearchParams({ phone: cleanPhone });
  const res = await fetch(
    buildUrl(
      `/public/catalog/${encodeURIComponent(businessId)}/orders/${encodeURIComponent(
        cleanOrderNumber
      )}?${params.toString()}`
    )
  );
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Order not found");
  }
  return json.data as Order;
}
