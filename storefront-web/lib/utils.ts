import type { CatalogItem } from "./types";

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

export function getBootstrap(): {
  businessId?: string;
  branchId?: string;
  catalog?: import("./types").Catalog;
} {
  if (typeof window === "undefined") return {};
  const bootstrap = window.__STOREFRONT__;
  if (bootstrap?.catalog) {
    return {
      businessId: bootstrap.businessId,
      branchId: bootstrap.branchId,
      catalog: bootstrap.catalog,
    };
  }
  if (bootstrap?.businessId) {
    return { businessId: bootstrap.businessId, branchId: bootstrap.branchId };
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

export function getBranchIdFromQuery(): string | undefined {
  if (typeof window === "undefined") return undefined;
  const params = new URLSearchParams(window.location.search);
  const branchId = params.get("branchId")?.trim();
  return branchId || undefined;
}

export function getPreviewTokenFromQuery(): string | undefined {
  if (typeof window === "undefined") return undefined;
  const params = new URLSearchParams(window.location.search);
  const token = params.get("preview")?.trim();
  return token || undefined;
}

export function getPagePreviewTokenFromQuery(): string | undefined {
  if (typeof window === "undefined") return undefined;
  const params = new URLSearchParams(window.location.search);
  const token = params.get("pagePreview")?.trim();
  return token || undefined;
}

export function getSitePreviewTokenFromQuery(): string | undefined {
  if (typeof window === "undefined") return undefined;
  const value = new URLSearchParams(window.location.search).get("sitePreview");
  return value || undefined;
}

export function clamp(num: number, min: number, max: number): number {
  return Math.min(Math.max(num, min), max);
}

export function classNames(...classes: Array<string | false | null | undefined>): string {
  return classes.filter(Boolean).join(" ");
}

export function getInitials(name?: string | null): string {
  if (!name) return "S";
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "S";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

export function getCatalogItemImages(
  item: Pick<CatalogItem, "imageUrl" | "imageUrls">
): string[] {
  const seen = new Set<string>();
  const urls = [item.imageUrl, ...(Array.isArray(item.imageUrls) ? item.imageUrls : [])];

  return urls.reduce<string[]>((images, url) => {
    const value = typeof url === "string" ? url.trim() : "";
    if (!value || seen.has(value)) return images;
    seen.add(value);
    images.push(value);
    return images;
  }, []);
}
