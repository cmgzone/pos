"use client";

import { motion } from "framer-motion";
import { MapPin, Package, CreditCard, Smartphone } from "lucide-react";
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
  const logoUrl = brand?.logoUrl;

  return (
    <section className="relative overflow-hidden min-h-[360px]">
      {coverUrl ? (
        <div className="absolute inset-0">
          <img
            src={coverUrl}
            alt=""
            className="h-full w-full object-cover opacity-25"
          />
          <div className="absolute inset-0 bg-gradient-to-r from-background via-background/90 to-background/60" />
        </div>
      ) : (
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,_var(--accent-glow)_0%,_transparent_50%)] opacity-30" />
      )}

      <div className="relative z-10 mx-auto grid min-h-[360px] items-center gap-8 px-4 py-12 sm:px-6 lg:grid-cols-[1fr_380px] lg:px-8 xl:grid-cols-[1fr_440px] xl:px-12">
        <div>
          <FadeIn delay={0.05}>
            <div className="mb-3 inline-flex items-center gap-1.5 rounded-full bg-surface/70 px-3 py-1 text-[11px] font-medium text-muted ring-1 ring-white/10">
              <MapPin className="h-3 w-3 text-accent" />
              {business?.selectedBranch?.name || "Online store"}
            </div>
          </FadeIn>

          <FadeIn delay={0.1}>
            <h1 className="text-3xl font-bold tracking-tight leading-[1.15] sm:text-4xl lg:text-5xl">
              {brand?.tagline || business?.name || "Your online store"}
            </h1>
          </FadeIn>

          <FadeIn delay={0.15}>
            <p className="mt-3 max-w-lg text-sm leading-relaxed text-muted sm:text-base">
              {brand?.description ||
                "Shop products, book services, choose variants, and place orders in seconds."}
            </p>
          </FadeIn>

          <FadeIn delay={0.2}>
            <div className="mt-6 flex flex-wrap items-center gap-3">
              <button
                onClick={onBrowse}
                className="inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold text-background transition hover:opacity-90"
                style={{ backgroundColor: primaryColor }}
              >
                <Package className="h-4 w-4" />
                Browse collection
              </button>
            </div>
          </FadeIn>
        </div>

        <FadeIn delay={0.2} direction="left">
          <div className="hidden lg:block">
            <CheckoutPreviewCard logoUrl={logoUrl} businessName={business?.name} />
          </div>
        </FadeIn>
      </div>
    </section>
  );
}

function CheckoutPreviewCard({
  logoUrl,
  businessName,
}: {
  logoUrl?: string | null;
  businessName?: string;
}) {
  return (
    <motion.div
      animate={{ y: [0, -6, 0] }}
      transition={{ duration: 4, repeat: Infinity, ease: "easeInOut" }}
      className="relative mx-auto w-full max-w-[320px] overflow-hidden rounded-2xl bg-surface-elevated/90 p-5 ring-1 ring-white/[0.08] shadow-xl shadow-black/40"
    >
      <div className="mb-4 flex items-center gap-2.5">
        {logoUrl ? (
          <img src={logoUrl} alt="" className="h-7 w-7 rounded-full object-cover" />
        ) : (
          <div className="flex h-7 w-7 items-center justify-center rounded-full bg-surface ring-1 ring-white/10">
            <span className="text-[10px] font-bold text-accent">P</span>
          </div>
        )}
        <div>
          <p className="text-xs font-semibold">
            {businessName || "Online store"}
          </p>
          <p className="text-[10px] text-muted">Fast checkout</p>
        </div>
      </div>

      <div className="space-y-3">
        <div className="rounded-xl bg-surface p-3 ring-1 ring-white/[0.05]">
          <div className="flex items-center justify-between text-xs">
            <span className="text-muted">Selected item</span>
            <span className="font-semibold text-accent">KSH 2,450</span>
          </div>
          <div className="mt-2 h-2 w-3/4 rounded-full bg-surface-elevated shimmer" />
        </div>

        <div className="rounded-xl bg-surface p-3 ring-1 ring-white/[0.05]">
          <div className="flex items-center gap-2 text-xs text-muted">
            <CreditCard className="h-3.5 w-3.5 text-accent" />
            Pay with M-Pesa, card, or bank
          </div>
        </div>

        <div className="rounded-xl bg-accent p-3 text-center text-xs font-semibold text-background">
          Place order
        </div>
      </div>

      <div className="mt-3 flex items-center justify-center gap-2 text-[10px] text-muted">
        <Smartphone className="h-3 w-3" />
        Order tracking + WhatsApp updates
      </div>
    </motion.div>
  );
}
