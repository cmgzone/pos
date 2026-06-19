"use client";

import { motion } from "framer-motion";
import { MapPin, Package, Sparkles, Search } from "lucide-react";
import type { Business } from "@/lib/types";
import { FadeIn } from "./motion";

interface HeroProps {
  business?: Business;
  onTrackOrder: () => void;
}

export function Hero({ business, onTrackOrder }: HeroProps) {
  const brand = business?.brand;
  const primaryColor = brand?.primaryColor || "#d4af37";

  return (
    <section className="relative overflow-hidden">
      {brand?.coverUrl ? (
        <div className="absolute inset-0">
          <img
            src={brand.coverUrl}
            alt=""
            className="h-full w-full object-cover opacity-40"
          />
          <div className="absolute inset-0 bg-gradient-to-b from-background/60 via-background/80 to-background" />
        </div>
      ) : (
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--accent)_0%,_transparent_50%)] opacity-10" />
      )}

      <div className="relative z-10 w-full px-4 sm:px-6 lg:px-8 xl:px-12 pt-10 pb-14">
        <motion.nav
          initial={{ opacity: 0, y: -12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="flex items-center justify-between py-4 mb-10"
        >
          <div className="flex items-center gap-3">
            {brand?.logoUrl ? (
              <img
                src={brand.logoUrl}
                alt={business?.name}
                className="h-10 w-10 rounded-full object-cover ring-1 ring-white/10"
              />
            ) : (
              <div className="flex h-10 w-10 items-center justify-center rounded-full bg-surface ring-1 ring-white/10">
                <Sparkles className="h-5 w-5 text-accent" />
              </div>
            )}
            <span className="text-lg font-semibold tracking-tight">
              {business?.name || "Storefront"}
            </span>
          </div>
          <button
            onClick={onTrackOrder}
            className="hidden sm:flex items-center gap-2 rounded-full bg-surface px-4 py-2 text-sm font-medium ring-1 ring-white/10 transition hover:bg-surface-elevated"
          >
            <Search className="h-4 w-4 text-accent" />
            Track order
          </button>
        </motion.nav>

        <div className="max-w-3xl">
          <FadeIn delay={0.1}>
            <div className="mb-4 inline-flex items-center gap-2 rounded-full bg-surface/80 px-3 py-1 text-xs font-medium text-muted ring-1 ring-white/10">
              <MapPin className="h-3.5 w-3.5" />
              {business?.selectedBranch?.name || "Online store"}
            </div>
          </FadeIn>

          <FadeIn delay={0.2}>
            <h1 className="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight leading-[1.1]">
              {brand?.tagline || `Welcome to ${business?.name || "our store"}`}
            </h1>
          </FadeIn>

          <FadeIn delay={0.3}>
            <p className="mt-5 max-w-xl text-base sm:text-lg text-muted leading-relaxed">
              {brand?.description ||
                "Browse our curated collection of products and services, crafted for quality and convenience."}
            </p>
          </FadeIn>

          <FadeIn delay={0.4}>
            <div className="mt-8 flex flex-wrap items-center gap-4">
              <a
                href="#catalog"
                className="inline-flex items-center gap-2 rounded-full px-6 py-3 text-sm font-semibold text-background transition hover:opacity-90"
                style={{ backgroundColor: primaryColor }}
              >
                <Package className="h-4 w-4" />
                Browse collection
              </a>
              <button
                onClick={onTrackOrder}
                className="inline-flex items-center gap-2 rounded-full bg-surface px-6 py-3 text-sm font-semibold ring-1 ring-white/10 transition hover:bg-surface-elevated sm:hidden"
              >
                <Search className="h-4 w-4" />
                Track order
              </button>
            </div>
          </FadeIn>
        </div>
      </div>
    </section>
  );
}
