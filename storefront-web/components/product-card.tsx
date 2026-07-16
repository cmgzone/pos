"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Check, ImageOff, PackageCheck, ExternalLink } from "lucide-react";
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
  const isExternal = item.source === "external_api";
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
  const compareAtPrice = selectedAvailableVariant?.compareAtPrice ?? item.compareAtPrice;
  const isOutOfStock = hasVariants
    ? availableVariants.length === 0
    : Boolean(item.trackStock && item.stock <= 0);
  const images = getCatalogItemImages(item);
  const image = images[0];
  const hasImage = image && !imageError;
  const availableOptionCount = availableVariants.length;
  const stockLabel = isOutOfStock
    ? "Sold out"
    : hasVariants
      ? `${availableOptionCount} option${availableOptionCount === 1 ? "" : "s"} available`
      : item.trackStock && item.stock <= 5
        ? `Only ${Math.max(0, item.stock)} left`
        : "In stock";

  const handleAdd = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    if (isExternal) {
      if (item.externalCheckoutUrl) window.open(item.externalCheckoutUrl, "_blank", "noopener,noreferrer");
      return;
    }
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
  const openDetails = () => {
    if (isExternal) {
      if (item.externalCheckoutUrl) window.open(item.externalCheckoutUrl, "_blank", "noopener,noreferrer");
      return;
    }
    setShowQuickView(true);
  };

  return (
    <StaggerItem>
      <div className="theme-product-card group flex h-full flex-col overflow-hidden rounded-[var(--theme-radius)] border border-border-subtle bg-surface shadow-[0_18px_50px_-34px_rgba(0,0,0,0.85)] transition duration-300 hover:-translate-y-1 hover:border-border-strong hover:shadow-[0_24px_60px_-30px_rgba(0,0,0,0.9)]">
        <button
          type="button"
          onClick={openDetails}
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

          {!isOutOfStock && (
            <div className="absolute left-3 top-3 flex flex-col items-start gap-2">
              {item.discountPercent && item.discountPercent > 0 && (
                <span className="rounded-full bg-accent px-2.5 py-1 text-[10px] font-extrabold uppercase tracking-[0.1em] text-background shadow-sm">
                  Save {item.discountPercent}%
                </span>
              )}
              {item.isFeatured && (
                <span className="rounded-full border border-white/15 bg-background/82 px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.1em] text-foreground backdrop-blur-md">
                  Featured
                </span>
              )}
            </div>
          )}

          {isOutOfStock && (
            <div className="absolute inset-0 flex items-center justify-center bg-background/60">
              <span className="rounded border border-border-strong bg-background/80 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-muted-strong">
                Sold out
              </span>
            </div>
          )}

          {!isOutOfStock && (
            <span className="absolute bottom-3 left-3 inline-flex items-center gap-1.5 rounded-full border border-white/10 bg-background/82 px-2.5 py-1 text-[10px] font-semibold text-muted-strong backdrop-blur-md">
              <PackageCheck className="h-3 w-3 text-accent" />
              {stockLabel}
            </span>
          )}
        </button>

        <div className="flex flex-1 flex-col p-3 sm:p-4">
          {item.category && (
            <span className="mb-1.5 text-[10px] font-medium uppercase tracking-[0.12em] text-muted">
              {item.category}
            </span>
          )}
          <button
            type="button"
            onClick={openDetails}
            className="text-left"
          >
            <h3 className="line-clamp-2 text-[14px] font-medium leading-snug text-foreground sm:text-[15px]">
              {item.name}
            </h3>
          </button>
          {item.brand && (
            <p className="mt-1 text-[12px] text-muted">{item.brand}</p>
          )}

          <div className="mt-auto flex items-end justify-between gap-3 pt-5">
            <div className="flex flex-col">
              {compareAtPrice != null && compareAtPrice > price && (
                <span className="text-[12px] text-muted line-through decoration-current/60">
                  {formatPrice(compareAtPrice, currencySymbol, currencyCode)}
                </span>
              )}
              <span className="text-[15px] font-semibold tracking-tight text-accent sm:text-[17px]">
                {pricePrefix}
                {formatPrice(price, currencySymbol, currencyCode)}
              </span>
              {hasVariants && !selectedAvailableVariant && variantPrices.length > 0 && (
                <span className="text-[11px] text-muted">multiple options</span>
              )}
              {item.promotionLabel && compareAtPrice != null && compareAtPrice > price && (
                <span className="mt-1 text-[10px] font-semibold uppercase tracking-[0.08em] text-muted">
                  {item.promotionLabel}
                </span>
              )}
            </div>
          </div>

          <button
            onClick={handleAdd}
            disabled={isOutOfStock || (isExternal && !item.externalCheckoutUrl)}
            className="mt-3 inline-flex h-10 items-center justify-center gap-2 rounded-md border border-border-subtle bg-surface-elevated text-[13px] font-semibold text-foreground transition hover:border-accent hover:bg-accent hover:text-background disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:border-border-subtle disabled:hover:bg-surface-elevated disabled:hover:text-foreground"
          >
            <motion.span
              key={added ? "check" : "plus"}
              initial={{ scale: 0.5, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ duration: 0.18 }}
              className="inline-flex items-center gap-2"
            >
              {isExternal ? (
                <>
                  <ExternalLink className="h-4 w-4" />
                  <span>{item.externalCheckoutUrl ? "View product" : "Unavailable"}</span>
                </>
              ) : added ? (
                <>
                  <Check className="h-4 w-4" />
                  Added
                </>
              ) : (
                <>
                  {!isOutOfStock && <Plus className="h-4 w-4" />}
                  <span className="sm:hidden">
                    {isOutOfStock
                      ? "Sold out"
                      : hasVariants && !selectedAvailableVariant
                        ? "Options"
                        : "Add"}
                  </span>
                  <span className="hidden sm:inline">{buttonLabel}</span>
                </>
              )}
            </motion.span>
          </button>
        </div>
      </div>

      {showQuickView && !isExternal && (
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
