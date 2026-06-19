"use client";

import { motion } from "framer-motion";
import { Search, ShoppingBag, Sparkles } from "lucide-react";
import type { Business } from "@/lib/types";
import { useStore } from "./store-provider";

interface SiteHeaderProps {
  business?: Business;
  onTrackOrder: () => void;
}

export function SiteHeader({ business, onTrackOrder }: SiteHeaderProps) {
  const { cartCount, setIsCartOpen } = useStore();
  const brand = business?.brand;
  const logoUrl = brand?.logoUrl;

  return (
    <motion.header
      initial={{ opacity: 0, y: -12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.4 }}
      className="sticky top-0 z-40 glass"
    >
      <div className="mx-auto flex h-14 items-center justify-between px-4 sm:px-6 lg:px-8 xl:px-12">
        <div className="flex items-center gap-3 min-w-0">
          {logoUrl ? (
            <img
              src={logoUrl}
              alt={business?.name}
              className="h-8 w-8 shrink-0 rounded-full object-cover ring-1 ring-white/10"
            />
          ) : (
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-white/10">
              <Sparkles className="h-4 w-4 text-accent" />
            </div>
          )}
          <span className="truncate text-sm font-semibold tracking-tight sm:text-base">
            {business?.name || "Storefront"}
          </span>
        </div>

        <div className="flex items-center gap-1 sm:gap-2">
          <button
            onClick={onTrackOrder}
            className="flex h-9 items-center gap-1.5 rounded-full px-3 text-xs font-medium text-muted transition hover:bg-surface-elevated hover:text-foreground"
          >
            <Search className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Track</span>
          </button>
          <button
            onClick={() => setIsCartOpen(true)}
            className="relative flex h-9 items-center gap-1.5 rounded-full bg-accent px-3 text-xs font-semibold text-background transition hover:opacity-90"
          >
            <ShoppingBag className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Cart</span>
            {cartCount > 0 && (
              <span className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-background text-[9px] font-bold text-foreground ring-1 ring-accent">
                {cartCount > 9 ? "9+" : cartCount}
              </span>
            )}
          </button>
        </div>
      </div>
    </motion.header>
  );
}
