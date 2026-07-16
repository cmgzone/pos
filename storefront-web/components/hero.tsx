"use client";

import { useState, useEffect, useCallback } from "react";
import type { ReactNode } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MapPin, ArrowRight } from "lucide-react";
import type {
  Business,
  Storefront,
  StorefrontSection,
  StorefrontSectionAction,
} from "@/lib/types";
import { FadeIn } from "./motion";

interface HeroProps {
  business?: Business;
  storefront?: Storefront;
  section?: StorefrontSection;
  onAction: (action: StorefrontSectionAction) => void;
}

export function Hero({ business, storefront, section, onAction }: HeroProps) {
  const brand = business?.brand;
  const coverUrls = section?.showImage === false
    ? []
    : brand?.coverUrls?.length
      ? brand.coverUrls
      : brand?.coverUrl
        ? [brand.coverUrl]
        : [];
  const hasSlides = coverUrls.length > 1;
  const [slideIndex, setSlideIndex] = useState(0);

  const nextSlide = useCallback(() => {
    setSlideIndex((previous) => (previous + 1) % coverUrls.length);
  }, [coverUrls.length]);

  useEffect(() => {
    if (!hasSlides) return;
    const timer = setInterval(nextSlide, 6000);
    return () => clearInterval(timer);
  }, [hasSlides, nextSlide]);

  const defaultHeadline = storefront?.type === "services"
    ? "Book a service that fits your day"
    : storefront?.type === "restaurant"
      ? "Made fresh. Ready when you are."
      : "Your online store";
  const headline =
    section?.title || brand?.tagline || business?.name || defaultHeadline;
  const description =
    section?.body ||
    brand?.description ||
    storefront?.description ||
    "Browse, choose what you need, and send your order in seconds.";
  const branchName = business?.selectedBranch?.name;
  const eyebrow = section
    ? section.eyebrow
    : [storefront?.label, branchName].filter(Boolean).join(" · ");
  const alignment = section?.alignment || "left";
  const copyAlignment = alignment === "center"
    ? "mx-auto items-center text-center"
    : alignment === "right"
      ? "ml-auto items-end text-right"
      : "items-start text-left";
  const primaryAction = section?.buttonAction || "catalog";
  const primaryLabel =
    section?.buttonLabel || storefront?.browseLabel || "Browse collection";
  const secondaryAction = section?.secondaryButtonAction || "none";
  const secondaryLabel = section?.secondaryButtonLabel || "";
  const imagePosition = section?.imagePosition || "background";

  const actions = (
    <div
      className={`mt-8 flex flex-wrap gap-3 ${
        alignment === "center"
          ? "justify-center"
          : alignment === "right"
            ? "justify-end"
            : "justify-start"
      }`}
    >
      {primaryAction !== "none" && primaryLabel && (
        <button
          onClick={() => onAction(primaryAction)}
          className="group inline-flex items-center gap-2 rounded-md bg-accent px-6 py-3 text-[14px] font-semibold text-background transition hover:opacity-90"
        >
          {primaryLabel}
          <ArrowRight className="h-4 w-4 transition group-hover:translate-x-0.5" />
        </button>
      )}
      {secondaryAction !== "none" && secondaryLabel && (
        <button
          onClick={() => onAction(secondaryAction)}
          className="inline-flex items-center rounded-md border border-border-strong bg-background/40 px-6 py-3 text-[14px] font-semibold text-foreground backdrop-blur-sm transition hover:border-accent"
        >
          {secondaryLabel}
        </button>
      )}
    </div>
  );

  if (coverUrls.length > 0 && imagePosition !== "background") {
    const image = coverUrls[slideIndex % coverUrls.length];
    const isTop = imagePosition === "top";
    return (
      <section className="theme-hero mx-auto max-w-[var(--site-max-width)] overflow-hidden">
        <div className={`grid items-stretch ${isTop ? "" : "lg:grid-cols-2"}`}>
          <div
            className={`min-h-[320px] overflow-hidden bg-surface-elevated ${
              imagePosition === "left" || isTop ? "order-first" : "lg:order-last"
            }`}
          >
            <img src={image} alt="" className="h-full w-full object-cover" />
          </div>
          <div
            className={`flex min-h-[360px] flex-col justify-center px-6 py-16 sm:px-10 lg:px-16 ${copyAlignment}`}
          >
            <HeroCopy
              eyebrow={eyebrow}
              headline={headline}
              description={description}
              actions={actions}
            />
          </div>
        </div>
      </section>
    );
  }

  if (coverUrls.length > 0) {
    return (
      <section className="theme-hero relative overflow-hidden">
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
            <img src={coverUrls[0]} alt="" className="h-full w-full object-cover" />
          )}
          <div className="absolute inset-0 bg-gradient-to-t from-background via-background/40 to-background/10" />
        </div>

        {hasSlides && (
          <div className="absolute bottom-5 left-1/2 z-20 flex -translate-x-1/2 gap-1.5">
            {coverUrls.map((_, index) => (
              <button
                key={index}
                onClick={() => setSlideIndex(index)}
                aria-label={`Go to slide ${index + 1}`}
                className={`h-1.5 rounded-full transition-all duration-300 ${
                  index === slideIndex % coverUrls.length
                    ? "w-6 bg-accent"
                    : "w-1.5 bg-accent/40 hover:bg-accent/60"
                }`}
              />
            ))}
          </div>
        )}

        <div
          className={`relative z-10 mx-auto flex max-w-4xl flex-col px-4 py-24 sm:px-6 sm:py-32 lg:px-10 lg:py-40 ${copyAlignment}`}
        >
          <HeroCopy
            eyebrow={eyebrow}
            headline={headline}
            description={description}
            actions={actions}
          />
        </div>
      </section>
    );
  }

  return (
    <section className="theme-hero relative border-b border-border-subtle">
      <div
        className={`mx-auto flex max-w-4xl flex-col px-4 py-20 sm:px-6 sm:py-28 lg:px-10 lg:py-32 ${copyAlignment}`}
      >
        <HeroCopy
          eyebrow={eyebrow}
          headline={headline}
          description={description}
          actions={actions}
        />
      </div>
    </section>
  );
}

function HeroCopy({
  eyebrow,
  headline,
  description,
  actions,
}: {
  eyebrow?: string;
  headline: string;
  description: string;
  actions: ReactNode;
}) {
  return (
    <>
      <FadeIn delay={0.05}>
        {eyebrow && (
          <div className="mb-5 inline-flex items-center gap-1.5 text-[12px] font-medium uppercase tracking-[0.14em] text-muted-strong">
            <MapPin className="h-3.5 w-3.5" />
            {eyebrow}
          </div>
        )}
      </FadeIn>
      <FadeIn delay={0.1}>
        <h1 className="theme-hero-heading font-display text-4xl leading-[1.08] text-foreground sm:text-5xl lg:text-6xl">
          {headline}
        </h1>
      </FadeIn>
      <FadeIn delay={0.16}>
        <p className="mt-5 max-w-xl text-[15px] leading-relaxed text-muted-strong sm:text-base">
          {description}
        </p>
      </FadeIn>
      <FadeIn delay={0.22}>{actions}</FadeIn>
    </>
  );
}
