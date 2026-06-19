"use client";

import { useState, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MapPin, Package } from "lucide-react";
import type { Business } from "@/lib/types";
import { FadeIn } from "./motion";

interface HeroProps {
  business?: Business;
  onBrowse: () => void;
}

export function Hero({ business, onBrowse }: HeroProps) {
  const brand = business?.brand;
  const coverUrls = brand?.coverUrls?.length ? brand.coverUrls : brand?.coverUrl ? [brand.coverUrl] : [];
  const hasSlides = coverUrls.length > 1;
  const [slideIndex, setSlideIndex] = useState(0);

  const nextSlide = useCallback(() => {
    setSlideIndex((prev) => (prev + 1) % coverUrls.length);
  }, [coverUrls.length]);

  useEffect(() => {
    if (!hasSlides) return;
    const timer = setInterval(nextSlide, 5000);
    return () => clearInterval(timer);
  }, [hasSlides, nextSlide]);

  return (
    <section className="relative overflow-hidden min-h-[300px]">
      {coverUrls.length > 0 ? (
        <div className="absolute inset-0">
          {hasSlides ? (
            <AnimatePresence mode="wait">
              {(() => {
                const url = coverUrls[slideIndex % coverUrls.length];
                return (
                  <motion.img
                    key={slideIndex}
                    src={url}
                    alt=""
                    initial={{ opacity: 0, scale: 1.04 }}
                    animate={{ opacity: 0.72, scale: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 1, ease: "easeInOut" }}
                    className="absolute inset-0 h-full w-full object-cover"
                  />
                );
              })()}
            </AnimatePresence>
          ) : (
            <img
              src={coverUrls[0]}
              alt=""
              className="h-full w-full object-cover opacity-[0.72]"
            />
          )}
          <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(8,8,10,0.18)_0%,rgba(8,8,10,0.42)_58%,rgba(8,8,10,0.84)_100%)]" />
        </div>
      ) : (
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--accent-glow)_0%,_transparent_50%)] opacity-30" />
      )}

      {hasSlides && (
        <div className="absolute bottom-4 left-1/2 z-20 flex -translate-x-1/2 gap-1.5">
          {coverUrls.map((_, i) => (
            <button
              key={i}
              onClick={() => setSlideIndex(i)}
              className={`h-1.5 rounded-full transition-all duration-300 ${
                i === slideIndex % coverUrls.length
                  ? "w-6 bg-accent"
                  : "w-1.5 bg-white/30 hover:bg-white/50"
              }`}
            />
          ))}
        </div>
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
            className="mt-6 inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-background transition hover:opacity-90"
          >
            <Package className="h-4 w-4" />
            Browse collection
          </button>
        </FadeIn>
      </div>
    </section>
  );
}
