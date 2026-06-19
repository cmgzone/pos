"use client";

import { MapPin, Package } from "lucide-react";
import type { Business } from "@/lib/types";
import { FadeIn } from "./motion";

interface HeroProps {
  business?: Business;
  onBrowse: () => void;
}

export function Hero({ business, onBrowse }: HeroProps) {
  const brand = business?.brand;
  const primaryColor = brand?.primaryColor || "#f4c430";
  const coverUrl = brand?.coverUrl;

  return (
    <section className="relative overflow-hidden min-h-[300px]">
      {coverUrl ? (
        <div className="absolute inset-0">
          <img
            src={coverUrl}
            alt=""
            className="h-full w-full object-cover opacity-25"
          />
          <div className="absolute inset-0 bg-gradient-to-b from-background/80 to-background" />
        </div>
      ) : (
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--accent-glow)_0%,_transparent_50%)] opacity-30" />
      )}

      <div className="relative z-10 mx-auto max-w-3xl px-4 py-14 sm:px-6 lg:px-8 xl:px-12">
        <FadeIn delay={0.05}>
          <div className="mb-3 inline-flex items-center gap-1.5 rounded-full bg-surface/70 px-3 py-1 text-[11px] font-medium text-muted ring-1 ring-white/10">
            <MapPin className="h-3 w-3 text-accent" />
            {business?.selectedBranch?.name || "Online store"}
          </div>
        </FadeIn>

        <FadeIn delay={0.1}>
          <h1 className="text-3xl font-bold tracking-tight leading-[1.15] sm:text-4xl">
            {brand?.tagline || business?.name || "Your online store"}
          </h1>
        </FadeIn>

        <FadeIn delay={0.15}>
          <p className="mt-3 max-w-xl text-sm leading-relaxed text-muted sm:text-base">
            {brand?.description ||
              "Shop products, book services, choose variants, and place orders in seconds."}
          </p>
        </FadeIn>

        <FadeIn delay={0.2}>
          <button
            onClick={onBrowse}
            className="mt-6 inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold text-background transition hover:opacity-90"
            style={{ backgroundColor: primaryColor }}
          >
            <Package className="h-4 w-4" />
            Browse collection
          </button>
        </FadeIn>
      </div>
    </section>
  );
}
