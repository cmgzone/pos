export function formatPrice(
  amount: number,
  currencySymbol: string,
  currencyCode: string
): string {
  const value = Number(amount) || 0;
  const formatted = value.toLocaleString(undefined, {
    minimumFractionDigits: value % 1 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  });
  return `${currencySymbol || currencyCode} ${formatted}`;
}

export function getBusinessIdFromPath(): string | undefined {
  if (typeof window === "undefined") return undefined;
  const match = window.location.pathname.match(/\/catalog\/([^/]+)/);
  return match?.[1];
}

export function getBootstrap(): { businessId?: string; catalog?: import("./types").Catalog } {
  if (typeof window === "undefined") return {};
  const bootstrap = window.__STOREFRONT__;
  if (bootstrap?.catalog) {
    return { businessId: bootstrap.businessId, catalog: bootstrap.catalog };
  }
  if (bootstrap?.businessId) {
    return { businessId: bootstrap.businessId };
  }
  if (window.__STOREFRONT_CATALOG__) {
    return { catalog: window.__STOREFRONT_CATALOG__ };
  }
  const fromPath = getBusinessIdFromPath();
  if (fromPath) {
    return { businessId: fromPath };
  }
  return {};
}

export function clamp(num: number, min: number, max: number): number {
  return Math.min(Math.max(num, min), max);
}

export function classNames(...classes: Array<string | false | null | undefined>): string {
  return classes.filter(Boolean).join(" ");
}
