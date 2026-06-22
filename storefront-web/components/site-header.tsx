"use client";

import { ShoppingBag, Search } from "lucide-react";
import type { Business } from "@/lib/types";
import { useStore } from "./store-provider";
import { getInitials } from "@/lib/utils";

interface SiteHeaderProps {
  business?: Business;
  onTrackOrder: () => void;
}

export function SiteHeader({ business, onTrackOrder }: SiteHeaderProps) {
  const { cartCount, setIsCartOpen } = useStore();
  const brand = business?.brand;
  const logoUrl = brand?.logoUrl;

  const scrollToCatalog = () => {
    document.getElementById("catalog")?.scrollIntoView({ behavior: "smooth" });
  };

  return (
    <header className="sticky top-0 z-40 border-b border-border-subtle bg-background/90 backdrop-blur-md">
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
            {(brand?.tagline || business?.selectedBranch?.name) && (
              <span className="block truncate text-[11px] text-muted">
                {brand?.tagline || business?.selectedBranch?.name}
              </span>
            )}
          </div>
        </div>

        <nav className="flex items-center gap-1 sm:gap-2">
          <button
            onClick={scrollToCatalog}
            className="hidden rounded-md px-3 py-2 text-[13px] font-medium text-muted-strong transition hover:text-foreground sm:inline-flex"
          >
            Shop
          </button>
          <button
            onClick={onTrackOrder}
            className="inline-flex items-center gap-1.5 rounded-md px-3 py-2 text-[13px] font-medium text-muted-strong transition hover:text-foreground"
          >
            <Search className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Track order</span>
          </button>
          <button
            onClick={() => setIsCartOpen(true)}
            className="relative inline-flex h-9 items-center gap-2 rounded-md bg-foreground px-3.5 text-[13px] font-semibold text-background transition hover:opacity-90"
          >
            <ShoppingBag className="h-4 w-4" />
            <span className="hidden sm:inline">Cart</span>
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
