"use client";

import { CircleUserRound, Moon, Search, ShoppingBag, Sun } from "lucide-react";
import type { Business, Storefront, StorefrontAppearance, StorefrontPageLink } from "@/lib/types";
import { useStore } from "./store-provider";
import { getInitials } from "@/lib/utils";

interface SiteHeaderProps {
  business?: Business;
  storefront?: Storefront;
  onTrackOrder: () => void;
  appearance: StorefrontAppearance;
  onAppearanceChange: (appearance: StorefrontAppearance) => void;
  showTracking?: boolean;
  pages?: StorefrontPageLink[];
}

export function SiteHeader({
  business,
  storefront,
  onTrackOrder,
  appearance,
  onAppearanceChange,
  showTracking = true,
  pages = [],
}: SiteHeaderProps) {
  const { cartCount, setIsCartOpen } = useStore();
  const brand = business?.brand;
  const logoUrl = brand?.logoUrl;

  const scrollToCatalog = () => {
    const catalog = document.getElementById("catalog");
    if (catalog) catalog.scrollIntoView({ behavior: "smooth" });
    else window.location.href = "/";
  };

  return (
    <header data-piki-component="site-header" data-piki-label="Website header" className="sticky top-0 z-40 border-b border-border-subtle bg-background/90 backdrop-blur-md">
      <div className="mx-auto flex h-16 items-center justify-between px-4 sm:px-6 lg:px-10">
        <div className="flex min-w-0 items-center gap-3">
          {logoUrl ? (
            <img
              src={logoUrl}
              alt={business?.name || "Store"}
              className="h-9 w-9 shrink-0 rounded-md object-cover ring-1 ring-border-strong"
            />
          ) : (
            <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-surface-elevated text-[13px] font-semibold tracking-tight text-foreground ring-1 ring-border-subtle">
              {getInitials(business?.name)}
            </div>
          )}
          <div className="min-w-0">
            <span className="block truncate text-[15px] font-semibold leading-tight tracking-tight">
              {business?.name || "Storefront"}
            </span>
            {(storefront?.label || brand?.tagline || business?.selectedBranch?.name) && (
              <span className="block truncate text-[11px] text-muted">
                {storefront?.label || brand?.tagline || business?.selectedBranch?.name}
              </span>
            )}
          </div>
        </div>

        <nav className="flex items-center gap-1 sm:gap-2">
          <button
            onClick={scrollToCatalog}
            className="hidden rounded-md px-3 py-2 text-[13px] font-medium text-muted-strong transition hover:text-foreground sm:inline-flex"
          >
            {storefront?.type === "services" ? "Services" : storefront?.type === "restaurant" ? "Menu" : "Shop"}
          </button>
          {pages.slice(0, 3).map((page) => (
            <a
              key={page.id}
              href={`/page/${encodeURIComponent(page.slug)}`}
              className="hidden rounded-md px-3 py-2 text-[13px] font-medium text-muted-strong transition hover:text-foreground lg:inline-flex"
            >
              {page.label || page.title}
            </a>
          ))}
          {showTracking && (
            <button
              onClick={onTrackOrder}
              aria-label={storefront?.type === "services" ? "Track booking" : "Track order"}
              className="inline-flex items-center gap-1.5 rounded-md px-3 py-2 text-[13px] font-medium text-muted-strong transition hover:text-foreground"
            >
              <Search className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">{storefront?.type === "services" ? "Track booking" : "Track order"}</span>
            </button>
          )}
          {business?.id && (
            <a
              href={`/portal?businessId=${encodeURIComponent(business.id)}`}
              aria-label="Open my customer account"
              className="inline-flex h-9 items-center gap-1.5 rounded-md px-2 text-[13px] font-medium text-muted-strong transition hover:bg-surface-elevated hover:text-foreground sm:px-3"
            >
              <CircleUserRound className="h-4 w-4" />
              <span className="hidden xl:inline">My account</span>
            </a>
          )}
          <button
            type="button"
            onClick={() => onAppearanceChange(appearance === "light" ? "dark" : "light")}
            aria-label={appearance === "light" ? "Switch to dark mode" : "Switch to light mode"}
            title={appearance === "light" ? "Dark mode" : "Light mode"}
            className="inline-flex h-9 w-9 items-center justify-center rounded-md border border-border-subtle bg-surface text-muted-strong transition hover:border-border-strong hover:text-foreground"
          >
            {appearance === "light" ? (
              <Moon className="h-4 w-4" />
            ) : (
              <Sun className="h-4 w-4" />
            )}
          </button>
          <button
            onClick={() => setIsCartOpen(true)}
            aria-label={storefront?.type === "services" ? "Open bookings" : storefront?.type === "restaurant" ? "Open order" : "Open cart"}
            className="relative inline-flex h-9 items-center gap-2 rounded-md bg-accent px-3.5 text-[13px] font-semibold text-background transition hover:opacity-90"
          >
            <ShoppingBag className="h-4 w-4" />
            <span className="hidden sm:inline">{storefront?.type === "services" ? "Bookings" : storefront?.type === "restaurant" ? "Order" : "Cart"}</span>
            {cartCount > 0 && (
              <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-background px-1 text-[11px] font-bold text-foreground ring-1 ring-border-strong">
                {cartCount > 9 ? "9+" : cartCount}
              </span>
            )}
          </button>
        </nav>
      </div>
    </header>
  );
}
