"use client";

import { motion } from "framer-motion";
import { X, Plus, Package } from "lucide-react";
import type { CatalogItem, ProductVariant } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
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
  const price = selectedVariant ? selectedVariant.price : item.price;
  const image = item.imageUrl || item.imageUrls?.[0];

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
            {image ? (
              <img
                src={image}
                alt={item.name}
                className="h-full w-full object-cover"
              />
            ) : (
              <div className="flex h-full min-h-[240px] items-center justify-center">
                <Package className="h-16 w-16 text-white/10" />
              </div>
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

            {item.variants && item.variants.length > 0 && (
              <div className="mt-6">
                <span className="text-xs font-medium uppercase tracking-wider text-muted">
                  Select option
                </span>
                <div className="mt-2 flex flex-wrap gap-2">
                  {item.variants.map((variant) => (
                    <button
                      key={variant.id}
                      onClick={() => onVariantChange(variant)}
                      className={`rounded-full px-3 py-1.5 text-xs font-medium transition ${
                        selectedVariant?.id === variant.id
                          ? "bg-accent text-background"
                          : "bg-surface-elevated ring-1 ring-white/10 hover:bg-white/5"
                      }`}
                    >
                      {variant.name} — {formatPrice(variant.price, currencySymbol, currencyCode)}
                    </button>
                  ))}
                </div>
              </div>
            )}

            <div className="mt-auto flex items-center justify-between pt-8">
              <span className="text-2xl font-bold text-accent">
                {formatPrice(price, currencySymbol, currencyCode)}
              </span>
              <button
                onClick={() => {
                  onAdd();
                  onClose();
                }}
                disabled={item.hasVariants && !selectedVariant}
                className="inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-background transition hover:opacity-90 disabled:opacity-40"
              >
                <Plus className="h-4 w-4" />
                Add to cart
              </button>
            </div>
          </div>
        </div>
      </ScaleIn>
    </div>
  );
}
