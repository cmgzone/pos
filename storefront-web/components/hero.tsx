"use client";

import { useState, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MapPin, ArrowRight } from "lucide-react";
import type { Business } from "@/lib/types";
import { FadeIn } from "./motion";

interface HeroProps {
  business?: Business;
  onBrowse: () => void;
}

export function Hero({ business, onBrowse }: HeroProps) {
  const brand = business?.brand;
  const coverUrls = brand?.coverUrls?.length
    ? brand.coverUrls
    : brand?.coverUrl
      ? [brand.coverUrl]
      : [];
  const hasSlides = coverUrls.length > 1;
  const [slideIndex, setSlideIndex] = useState(0);

  const nextSlide = useCallback(() => {
    setSlideIndex((prev) => (prev + 1) % coverUrls.length);
  }, [coverUrls.length]);

  useEffect(() => {
    if (!hasSlides) return;
    const timer = setInterval(nextSlide, 6000);
    return () => clearInterval(timer);
  }, [hasSlides, nextSlide]);

  const headline = brand?.tagline || business?.name || "Your online store";
  const description =
    brand?.description ||
    "Shop products, book services, choose variants, and place orders in seconds.";
  const branchName = business?.selectedBranch?.name;

  if (coverUrls.length > 0) {
    return (
      <section className="relative overflow-hidden">
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
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.8, ease: "easeInOut" }}
                    className="absolute inset-0 h-full w-full object-cover"
                  />
                );
              })()}
            </AnimatePresence>
          ) : (
            <img
              src={coverUrls[0]}
              alt=""
              className="h-full w-full object-cover"
            />
          )}
          <div className="absolute inset-0 bg-gradient-to-t from-background via-background/40 to-background/10" />
        </div>

        {hasSlides && (
          <div className="absolute bottom-5 left-1/2 z-20 flex -translate-x-1/2 gap-1.5">
            {coverUrls.map((_, i) => (
              <button
                key={i}
                onClick={() => setSlideIndex(i)}
                aria-label={`Go to slide ${i + 1}`}
                className={`h-1.5 rounded-full transition-all duration-300 ${
                  i === slideIndex % coverUrls.length
                    ? "w-6 bg-accent"
                    : "w-1.5 bg-accent/40 hover:bg-accent/60"
                }`}
              />
            ))}
          </div>
        )}

        <div className="relative z-10 mx-auto max-w-4xl px-4 py-24 sm:px-6 sm:py-32 lg:px-10 lg:py-40">
          <FadeIn delay={0.05}>
            {branchName && (
              <div className="mb-5 inline-flex items-center gap-1.5 text-[12px] font-medium uppercase tracking-[0.14em] text-muted-strong">
                <MapPin className="h-3.5 w-3.5" />
                {branchName}
              </div>
            )}
          </FadeIn>
          <FadeIn delay={0.1}>
            <h1 className="font-display text-4xl leading-[1.08] text-foreground sm:text-5xl lg:text-6xl">
              {headline}
            </h1>
          </FadeIn>
          <FadeIn delay={0.16}>
            <p className="mt-5 max-w-xl text-[15px] leading-relaxed text-muted-strong sm:text-base">
              {description}
            </p>
          </FadeIn>
          <FadeIn delay={0.22}>
            <button
              onClick={onBrowse}
              className="group mt-8 inline-flex items-center gap-2 rounded-md bg-accent px-6 py-3 text-[14px] font-semibold text-background transition hover:opacity-90"
            >
              Browse collection
              <ArrowRight className="h-4 w-4 transition group-hover:translate-x-0.5" />
            </button>
          </FadeIn>
        </div>
      </section>
    );
  }

  return (
    <section className="relative border-b border-border-subtle">
      <div className="mx-auto max-w-4xl px-4 py-20 sm:px-6 sm:py-28 lg:px-10 lg:py-32">
        <FadeIn delay={0.05}>
          {branchName && (
            <div className="mb-5 inline-flex items-center gap-1.5 text-[12px] font-medium uppercase tracking-[0.14em] text-muted-strong">
              <span className="h-1.5 w-1.5 rounded-full bg-accent" />
              {branchName}
            </div>
          )}
        </FadeIn>
        <FadeIn delay={0.1}>
          <h1 className="font-display text-4xl leading-[1.08] text-foreground sm:text-5xl lg:text-6xl">
            {headline}
          </h1>
        </FadeIn>
        <FadeIn delay={0.16}>
          <p className="mt-5 max-w-xl text-[15px] leading-relaxed text-muted-strong sm:text-base">
            {description}
          </p>
        </FadeIn>
        <FadeIn delay={0.22}>
          <button
            onClick={onBrowse}
            className="group mt-8 inline-flex items-center gap-2 rounded-md bg-accent px-6 py-3 text-[14px] font-semibold text-background transition hover:opacity-90"
          >
            Browse collection
            <ArrowRight className="h-4 w-4 transition group-hover:translate-x-0.5" />
          </button>
        </FadeIn>
      </div>
    </section>
  );
}
