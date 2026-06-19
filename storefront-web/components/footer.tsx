"use client";

import { Sparkles, Search } from "lucide-react";
import type { Business } from "@/lib/types";

interface FooterProps {
  business?: Business;
  onTrackOrder: () => void;
}

export function Footer({ business, onTrackOrder }: FooterProps) {
  const year = new Date().getFullYear();

  return (
    <footer className="mt-auto border-t border-white/10 px-4 py-10 sm:px-6 lg:px-8 xl:px-12">
      <div className="flex flex-col items-center justify-between gap-6 sm:flex-row">
        <div className="flex items-center gap-3">
          {business?.brand?.logoUrl ? (
            <img
              src={business.brand.logoUrl}
              alt={business.name}
              className="h-8 w-8 rounded-full object-cover ring-1 ring-white/10"
            />
          ) : (
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-surface ring-1 ring-white/10">
              <Sparkles className="h-4 w-4 text-accent" />
            </div>
          )}
          <span className="text-sm font-medium">
            {business?.name || "Storefront"}
          </span>
        </div>

        <button
          onClick={onTrackOrder}
          className="flex items-center gap-2 text-sm text-muted transition hover:text-foreground"
        >
          <Search className="h-4 w-4" />
          Track your order
        </button>
      </div>

      <div className="mt-8 text-center text-xs text-muted">
        © {year} {business?.name || "Storefront"}. Powered by Piki POS.
      </div>
    </footer>
  );
}
