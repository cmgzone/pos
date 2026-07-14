"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Check, ImageOff } from "lucide-react";
import type { CatalogItem, ProductVariant } from "@/lib/types";
import { formatPrice, getCatalogItemImages } from "@/lib/utils";
import { useStore } from "./store-provider";
import { StaggerItem } from "./motion";
import { QuickViewModal } from "./quick-view-modal";

interface ProductCardProps {
  item: CatalogItem;
  currencySymbol: string;
  currencyCode: string;
}

export function ProductCard({ item, currencySymbol, currencyCode }: ProductCardProps) {
  const { addToCart } = useStore();
  const [selectedVariant, setSelectedVariant] = useState<ProductVariant | undefined>();
  const [showQuickView, setShowQuickView] = useState(false);
  const [added, setAdded] = useState(false);
  const [imageError, setImageError] = useState(false);

  const variants = item.variants || [];
  const hasVariants = Boolean(item.hasVariants && variants.length > 0);
  const availableVariants = variants.filter((variant) => variant.available !== false);
  const variantPrices = (availableVariants.length ? availableVariants : variants).map(
    (variant) => variant.price
  );
  const selectedAvailableVariant =
    selectedVariant && selectedVariant.available !== false ? selectedVariant : undefined;
  const price = selectedAvailableVariant
    ? selectedAvailableVariant.price
    : hasVariants && variantPrices.length > 0
      ? Math.min(...variantPrices)
      : item.price;
  const pricePrefix =
    hasVariants && !selectedAvailableVariant && variantPrices.length > 0 ? "From " : "";
  const isOutOfStock = hasVariants
    ? availableVariants.length === 0
    : Boolean(item.trackStock && item.stock <= 0);
  const images = getCatalogItemImages(item);
  const image = images[0];
  const hasImage = image && !imageError;

  const handleAdd = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    if (isOutOfStock) return;
    if (hasVariants && !selectedAvailableVariant) {
      setShowQuickView(true);
      return;
    }
    addToCart(item, selectedVariant);
    setAdded(true);
    setTimeout(() => setAdded(false), 1200);
  };

  const buttonLabel = isOutOfStock
    ? "Sold out"
    : hasVariants && !selectedAvailableVariant
      ? "Choose options"
      : "Add to cart";

  return (
    <StaggerItem>
      <div className="theme-product-card group flex flex-col overflow-hidden rounded-lg border border-border-subtle bg-surface transition hover:border-border-strong">
        <button
          type="button"
          onClick={() => setShowQuickView(true)}
          className="theme-product-image relative aspect-[4/5] overflow-hidden bg-surface-elevated text-left"
        >
          {hasImage ? (
            <img
              src={image}
              alt={item.name}
              onError={() => setImageError(true)}
              className="h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
              loading="lazy"
            />
          ) : (
            <div className="flex h-full w-full flex-col items-center justify-center gap-2 text-muted">
              <ImageOff className="h-7 w-7 opacity-40" />
              <span className="text-[11px] uppercase tracking-wider opacity-60">
                No image
              </span>
            </div>
          )}

          {item.isFeatured && !isOutOfStock && (
            <span className="absolute left-3 top-3 rounded bg-accent px-2 py-1 text-[10px] font-semibold uppercase tracking-[0.1em] text-background">
              Featured
            </span>
          )}

          {isOutOfStock && (
            <div className="absolute inset-0 flex items-center justify-center bg-background/60">
              <span className="rounded border border-border-strong bg-background/80 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-strong">
                Sold out
              </span>
            </div>
          )}

          {hasVariants && variants.length > 1 && !isOutOfStock && (
            <span className="absolute bottom-3 left-3 rounded bg-background/80 px-2 py-1 text-[10px] font-medium text-muted-strong backdrop-blur-sm">
              {variants.length} options
            </span>
          )}
        </button>

        <div className="flex flex-1 flex-col p-4">
          {item.category && (
            <span className="mb-1.5 text-[10px] font-medium uppercase tracking-[0.12em] text-muted">
              {item.category}
            </span>
          )}
          <button
            type="button"
            onClick={() => setShowQuickView(true)}
            className="text-left"
          >
            <h3 className="line-clamp-2 text-[15px] font-medium leading-snug text-foreground">
              {item.name}
            </h3>
          </button>
          {item.brand && (
            <p className="mt-1 text-[12px] text-muted">{item.brand}</p>
          )}

          <div className="mt-4 flex items-center justify-between gap-3">
            <div className="flex flex-col">
              <span className="text-[17px] font-semibold tracking-tight text-accent">
                {pricePrefix}
                {formatPrice(price, currencySymbol, currencyCode)}
              </span>
              {hasVariants && !selectedAvailableVariant && variantPrices.length > 0 && (
                <span className="text-[11px] text-muted">multiple options</span>
              )}
            </div>
          </div>

          <button
            onClick={handleAdd}
            disabled={isOutOfStock}
            className="mt-3 inline-flex h-10 items-center justify-center gap-2 rounded-md border border-border-subtle bg-surface-elevated text-[13px] font-semibold text-foreground transition hover:border-accent hover:bg-accent hover:text-background disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-border-subtle disabled:hover:bg-surface-elevated disabled:hover:text-foreground"
          >
            <motion.span
              key={added ? "check" : "plus"}
              initial={{ scale: 0.5, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ duration: 0.18 }}
              className="inline-flex items-center gap-2"
            >
              {added ? (
                <>
                  <Check className="h-4 w-4" />
                  Added
                </>
              ) : (
                <>
                  {!isOutOfStock && <Plus className="h-4 w-4" />}
                  {buttonLabel}
                </>
              )}
            </motion.span>
          </button>
        </div>
      </div>

      {showQuickView && (
        <QuickViewModal
          item={item}
          currencySymbol={currencySymbol}
          currencyCode={currencyCode}
          selectedVariant={selectedVariant}
          onVariantChange={setSelectedVariant}
          onClose={() => setShowQuickView(false)}
          onAdd={handleAdd}
        />
      )}
    </StaggerItem>
  );
}
