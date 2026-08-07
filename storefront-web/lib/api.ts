import type { Catalog, Order, OrderPayload, StorefrontType } from "./types";

interface ApiJsonResponse {
  ok?: boolean;
  data?: unknown;
  order?: unknown;
  message?: string;
  error?: string;
}

export interface CustomerPortalStatement {
  customer: { id: string; name: string; email?: string | null; balance: number };
  sales: Array<{
    id: string;
    created_at: string;
    total_amount: number;
    amount_paid: number;
    balance_due: number;
    due_date?: string | null;
    status?: string | null;
  }>;
}

export interface CustomerPortalPayment {
  id: string;
  amount: number;
  currency: string;
  status: string;
  receiptNumber?: string | null;
  appliedAmount: number;
  unappliedAmount: number;
  createdAt?: string | null;
  completedAt?: string | null;
}

function getApiBase(): string {
  if (typeof window === "undefined") return "";
  if (process.env.NEXT_PUBLIC_API_BASE_URL) return process.env.NEXT_PUBLIC_API_BASE_URL;
  return "/api";
}

function buildUrl(path: string): string {
  return `${getApiBase()}${path}`;
}

export function storefrontTypeFromPath(pathname?: string): StorefrontType {
  const path = pathname ?? (typeof window === "undefined" ? "" : window.location.pathname);
  if (/(^|\/)services?\/?$/i.test(path)) return "services";
  if (/(^|\/)restaurant\/?$/i.test(path)) return "restaurant";
  return "retail";
}

export function campaignSlugFromPath(pathname?: string): string | undefined {
  const path = pathname ?? (typeof window === "undefined" ? "" : window.location.pathname);
  const match = path.match(/(?:^|\/)campaign\/([^/?#]+)\/?$/i);
  if (!match?.[1]) return undefined;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    return match[1];
  }
}

export function pageSlugFromPath(pathname?: string): string | undefined {
  const path = pathname ?? (typeof window === "undefined" ? "" : window.location.pathname);
  const match = path.match(/(?:^|\/)page\/([^/?#]+)\/?$/i);
  if (!match?.[1]) return undefined;
  try { return decodeURIComponent(match[1]); } catch { return match[1]; }
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
  branchId?: string,
  storefrontType: StorefrontType = storefrontTypeFromPath(),
  previewToken?: string,
  campaignSlug?: string,
  pageSlug?: string,
  pagePreviewToken?: string,
  sitePreviewToken?: string,
): Promise<Catalog> {
  const params = new URLSearchParams();
  if (branchId) params.set("branchId", branchId);
  if (previewToken) params.set("preview", previewToken);
  if (campaignSlug) params.set("campaign", campaignSlug);
  if (pageSlug) params.set("page", pageSlug);
  if (pagePreviewToken) params.set("pagePreview", pagePreviewToken);
  if (sitePreviewToken) params.set("sitePreview", sitePreviewToken);
  params.set("storefront", storefrontType);
  const query = params.toString() ? `?${params.toString()}` : "";
  const res = await fetch(
    buildUrl(`/public/catalog/${encodeURIComponent(businessId)}${query}`),
    { signal: AbortSignal.timeout(15000) }
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
): Promise<{
  orderNumber: string;
  trackingCode?: string;
  paymentMethod?: string;
  paymentStatus?: string;
  paymentRequestId?: string;
  checkoutUrl?: string;
}> {
  const res = await fetch(
    buildUrl(`/online-orders`),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        ...payload,
        storefrontType: payload.storefrontType || storefrontTypeFromPath(),
        businessId,
      }),
      signal: AbortSignal.timeout(30000),
    }
  );
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Failed to place order");
  }
  return (json.order || json.data) as {
    orderNumber: string;
    trackingCode?: string;
    paymentMethod?: string;
    paymentStatus?: string;
    paymentRequestId?: string;
    checkoutUrl?: string;
  };
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
    ),
    { signal: AbortSignal.timeout(15000) }
  );
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Order not found");
  }
  return json.data as Order;
}

export interface StorefrontSignupPayload {
  name: string;
  phone: string;
  email?: string;
  branchId?: string;
  marketingOptIn?: boolean;
}

export async function signupCustomer(
  businessId: string,
  payload: StorefrontSignupPayload,
): Promise<{ customerId: string; businessName: string; registered: boolean }> {
  const res = await fetch(
    buildUrl(`/public/catalog/${encodeURIComponent(businessId)}/signup`),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(30000),
    }
  );
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || "Unable to create your account.");
  }
  return json.data as {
    customerId: string;
    businessName: string;
    registered: boolean;
  };
}

export async function requestCustomerPortalCode(businessId: string, email: string) {
  const res = await fetch(buildUrl('/customer-portal/request-code'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ businessId, email }),
  });
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || 'Unable to send a verification code.');
  }
  return json as ApiJsonResponse & { sent?: boolean; retryAfterSeconds?: number };
}

export async function signInCustomerPortal(
  businessId: string,
  email: string,
  code: string,
): Promise<{ token: string; customer: CustomerPortalStatement['customer'] }> {
  const res = await fetch(buildUrl('/customer-portal/login'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ businessId, email, code }),
  });
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || 'Unable to sign in.');
  }
  return json as { token: string; customer: CustomerPortalStatement['customer'] };
}

export class SessionExpiredError extends Error {
  constructor() {
    super('Your session has expired. Please sign in again.');
    this.name = 'SessionExpiredError';
  }
}

async function customerPortalRequest(path: string, token: string, init?: RequestInit) {
  const res = await fetch(buildUrl(path), {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init?.headers || {}),
    },
    signal: AbortSignal.timeout(15000),
  });
  if (res.status === 401) {
    throw new SessionExpiredError();
  }
  const json = await readApiJson(res);
  if (!res.ok || !json.ok) {
    throw new Error(json?.message || json?.error || 'Customer portal request failed.');
  }
  return json;
}

export async function fetchCustomerPortalStatement(token: string): Promise<CustomerPortalStatement> {
  const json = await customerPortalRequest('/customer-portal/statement', token);
  return json as CustomerPortalStatement;
}

export async function startCustomerPortalMpesaPayment(
  token: string,
  amount: number,
  phoneNumber: string,
): Promise<CustomerPortalPayment> {
  const json = await customerPortalRequest('/customer-portal/payments/mpesa', token, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ amount, phoneNumber }),
  });
  return (json as { payment: CustomerPortalPayment }).payment;
}

export async function fetchCustomerPortalPayment(
  token: string,
  paymentId: string,
): Promise<CustomerPortalPayment> {
  const json = await customerPortalRequest(
    `/customer-portal/payments/${encodeURIComponent(paymentId)}`,
    token,
  );
  return (json as { payment: CustomerPortalPayment }).payment;
}
