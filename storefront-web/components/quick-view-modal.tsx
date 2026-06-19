"use client";

import { useEffect, useMemo, useState } from "react";
import { motion } from "framer-motion";
import { ChevronLeft, ChevronRight, X, Plus, Package } from "lucide-react";
import type { CatalogItem, ProductVariant } from "@/lib/types";
import { classNames, formatPrice, getCatalogItemImages } from "@/lib/utils";
import { ScaleIn } from "./motion";

interface QuickViewModalProps {
  item: CatalogItem;
  currencySymbol: string;
  currencyCode: string;
  selectedVariant?: ProductVariant;
  onVariantChange: (variant: ProductVariant | undefined) => void;
  onClose: () => void;
  onAdd: () => void;
}

export function QuickViewModal({
  item,
  currencySymbol,
  currencyCode,
  selectedVariant,
  onVariantChange,
  onClose,
  onAdd,
}: QuickViewModalProps) {
  const images = useMemo(() => getCatalogItemImages(item), [item]);
  const variants = useMemo(() => item.variants || [], [item.variants]);
  const availableVariants = useMemo(
    () => variants.filter((variant) => variant.available !== false),
    [variants]
  );
  const [selectedImageIndex, setSelectedImageIndex] = useState(0);
  const [imageError, setImageError] = useState(false);
  const requiresVariant = Boolean(item.hasVariants && variants.length > 0);
  const selectedAvailableVariant =
    selectedVariant && selectedVariant.available !== false ? selectedVariant : undefined;
  const fallbackVariant = availableVariants[0] || variants[0];
  const price = selectedAvailableVariant?.price ?? fallbackVariant?.price ?? item.price;
  const image = images[selectedImageIndex];
  const hasMultipleImages = images.length > 1;
  const canAdd = !requiresVariant || Boolean(selectedAvailableVariant);

  useEffect(() => {
    setSelectedImageIndex(0);
    setImageError(false);
  }, [item.id]);

  useEffect(() => {
    if (selectedImageIndex >= images.length) {
      setSelectedImageIndex(0);
      setImageError(false);
    }
  }, [images.length, selectedImageIndex]);

  useEffect(() => {
    if (!requiresVariant) {
      if (selectedVariant) onVariantChange(undefined);
      return;
    }

    const stillAvailable = availableVariants.some(
      (variant) => variant.id === selectedVariant?.id
    );
    if (!stillAvailable) {
      onVariantChange(availableVariants[0]);
    }
  }, [availableVariants, onVariantChange, requiresVariant, selectedVariant]);

  const chooseImage = (index: number) => {
    setSelectedImageIndex(index);
    setImageError(false);
  };

  const stepImage = (offset: number) => {
    if (!images.length) return;
    setSelectedImageIndex((current) => (current + offset + images.length) % images.length);
    setImageError(false);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        onClick={onClose}
        className="absolute inset-0 bg-black/70 backdrop-blur-sm"
      />
      <ScaleIn className="relative w-full max-w-2xl overflow-hidden rounded-3xl bg-surface ring-1 ring-white/10">
        <button
          onClick={onClose}
          className="absolute right-4 top-4 z-10 flex h-8 w-8 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-white/10 transition hover:bg-white/10"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="grid max-h-[80vh] overflow-y-auto sm:grid-cols-2">
          <div className="relative aspect-square bg-surface-elevated sm:aspect-auto">
            {image && !imageError ? (
              <img
                src={image}
                alt={item.name}
                onError={() => setImageError(true)}
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full min-h-[240px] items-center justify-center">
                <Package className="h-16 w-16 text-white/10" />
              </div>
            )}
            {hasMultipleImages && (
              <>
                <span className="absolute left-3 top-3 rounded-full bg-background/70 px-2 py-1 text-[11px] font-medium text-muted backdrop-blur">
                  {selectedImageIndex + 1}/{images.length}
                </span>
                <button
                  type="button"
                  onClick={() => stepImage(-1)}
                  className="absolute left-3 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-full bg-background/70 text-foreground backdrop-blur transition hover:bg-background/90"
                  aria-label="Previous product photo"
                >
                  <ChevronLeft className="h-4 w-4" />
                </button>
                <button
                  type="button"
                  onClick={() => stepImage(1)}
                  className="absolute right-3 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-full bg-background/70 text-foreground backdrop-blur transition hover:bg-background/90"
                  aria-label="Next product photo"
                >
                  <ChevronRight className="h-4 w-4" />
                </button>
                <div className="absolute inset-x-3 bottom-3 flex gap-2 overflow-x-auto rounded-2xl bg-background/70 p-2 backdrop-blur">
                  {images.map((url, index) => (
                    <button
                      key={`${url}-${index}`}
                      type="button"
                      onClick={() => chooseImage(index)}
                      className={classNames(
                        "h-12 w-12 shrink-0 overflow-hidden rounded-xl ring-1 transition",
                        selectedImageIndex === index
                          ? "ring-accent"
                          : "ring-white/10 opacity-70 hover:opacity-100"
                      )}
                      aria-label={`Show product photo ${index + 1}`}
                    >
                      <img
                        src={url}
                        alt=""
                        className="h-full w-full object-cover"
                        loading="lazy"
                      />
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>

          <div className="flex flex-col p-6 sm:p-8">
            {item.category && (
              <span className="mb-2 text-[11px] font-medium uppercase tracking-wider text-muted">
                {item.category}
              </span>
            )}
            <h2 className="text-2xl font-bold tracking-tight">{item.name}</h2>
            {item.brand && (
              <p className="mt-1 text-sm text-muted">{item.brand}</p>
            )}
            <p className="mt-4 text-sm leading-relaxed text-muted">
              {item.description || "No description available."}
            </p>

            {variants.length > 0 && (
              <div className="mt-6">
                <span className="text-xs font-medium uppercase tracking-wider text-muted">
                  Choose variant
                </span>
                <div className="mt-2 flex flex-wrap gap-2">
                  {variants.map((variant) => {
                    const isAvailable = variant.available !== false;
                    const isSelected = selectedVariant?.id === variant.id;

                    return (
                      <button
                        key={variant.id}
                        onClick={() => {
                          if (isAvailable) onVariantChange(variant);
                        }}
                        disabled={!isAvailable}
                        className={classNames(
                          "rounded-full px-3 py-1.5 text-xs font-medium transition",
                          isSelected
                            ? "bg-accent text-background"
                            : "bg-surface-elevated ring-1 ring-white/10 hover:bg-white/5",
                          !isAvailable && "cursor-not-allowed opacity-40"
                        )}
                      >
                        {variant.name} - {formatPrice(variant.price, currencySymbol, currencyCode)}
                        {!isAvailable ? " - Sold out" : ""}
                      </button>
                    );
                  })}
                </div>
                {requiresVariant && availableVariants.length === 0 && (
                  <p className="mt-2 text-xs text-red-300">
                    No variants are currently available.
                  </p>
                )}
              </div>
            )}

            <div className="mt-auto flex items-center justify-between pt-8">
              <span className="text-2xl font-bold text-accent">
                {formatPrice(price, currencySymbol, currencyCode)}
              </span>
              <button
                onClick={() => {
                  if (!canAdd) return;
                  onAdd();
                  onClose();
                }}
                disabled={!canAdd}
                className="inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-background transition hover:opacity-90 disabled:opacity-40"
              >
                <Plus className="h-4 w-4" />
                {requiresVariant && availableVariants.length === 0 ? "Sold out" : "Add to cart"}
              </button>
            </div>
          </div>
        </div>
      </ScaleIn>
    </div>
  );
}
