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
    <footer className="mt-auto border-t border-white/[0.06] px-4 py-8 sm:px-6 lg:px-8 xl:px-12">
      <div className="flex flex-col items-center justify-between gap-5 sm:flex-row">
        <div className="flex items-center gap-2.5">
          {business?.brand?.logoUrl ? (
            <img
              src={business.brand.logoUrl}
              alt={business.name}
              className="h-7 w-7 rounded-full object-cover ring-1 ring-white/10"
            />
          ) : (
            <div className="flex h-7 w-7 items-center justify-center rounded-full bg-surface ring-1 ring-white/10">
              <Sparkles className="h-3.5 w-3.5 text-accent" />
            </div>
          )}
          <span className="text-sm font-medium">
            {business?.name || "Storefront"}
          </span>
        </div>

        <button
          onClick={onTrackOrder}
          className="flex items-center gap-1.5 text-xs text-muted transition hover:text-foreground"
        >
          <Search className="h-3.5 w-3.5" />
          Track your order
        </button>
      </div>

      <div className="mt-6 text-center text-[11px] text-muted/60">
        &copy; {year} {business?.name || "Storefront"}. Powered by Piki POS.
      </div>
    </footer>
  );
}
