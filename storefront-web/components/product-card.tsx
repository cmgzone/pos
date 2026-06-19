"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Check, Tag, ImageOff } from "lucide-react";
import type { CatalogItem, ProductVariant } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { StaggerItem, HoverLift } from "./motion";
import { QuickViewModal } from "./quick-view-modal";

const categoryColors: Record<string, string> = {
  food: "#eab308",
  beverages: "#f97316",
  electronics: "#3b82f6",
  fashion: "#ec4899",
  health: "#22c55e",
  home: "#a855f7",
  services: "#f4c430",
};

function categoryColor(category?: string | null): string {
  const key = (category || "").toLowerCase().split(/[&,\s]+/)[0];
  return categoryColors[key] || "#6366f1";
}

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

  const price = selectedVariant ? selectedVariant.price : item.price;
  const isOutOfStock = item.trackStock && item.stock <= 0 && !item.hasVariants;
  const image = item.imageUrl || item.imageUrls?.[0];
  const hasImage = image && !imageError;
  const accent = categoryColor(item.category);

  const handleAdd = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    if (isOutOfStock) return;
    if (item.hasVariants && !selectedVariant) {
      setShowQuickView(true);
      return;
    }
    addToCart(item, selectedVariant);
    setAdded(true);
    setTimeout(() => setAdded(false), 1200);
  };

  return (
    <StaggerItem>
      <HoverLift>
        <motion.div
          onClick={() => setShowQuickView(true)}
          className="group relative flex flex-col overflow-hidden rounded-2xl bg-[#141418] ring-1 ring-white/[0.05] cursor-pointer"
          whileHover={{ boxShadow: `0 0 0 1px ${accent}30` }}
        >
          <div className="relative aspect-[4/3] overflow-hidden">
            {hasImage ? (
              <img
                src={image}
                alt={item.name}
                onError={() => setImageError(true)}
                className="h-full w-full object-cover transition duration-700 group-hover:scale-105"
                loading="lazy"
              />
            ) : (
              <div
                className="flex h-full w-full flex-col items-center justify-center gap-2"
                style={{
                  background: `linear-gradient(135deg, ${accent}12, ${accent}06)`,
                }}
              >
                <div
                  className="flex h-12 w-12 items-center justify-center rounded-xl"
                  style={{ backgroundColor: `${accent}20` }}
                >
                  <Tag className="h-5 w-5" style={{ color: accent }} />
                </div>
                <div
                  className="flex h-10 w-10 items-center justify-center rounded-full bg-white/5"
                >
                  <ImageOff className="h-4 w-4 text-white/15" />
                </div>
              </div>
            )}
            {item.isFeatured && (
              <span className="absolute left-2 top-2 rounded-full bg-accent/90 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-background">
                Featured
              </span>
            )}
            {isOutOfStock && (
              <span className="absolute right-2 top-2 rounded-full bg-red-500/90 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-white">
                Out of stock
              </span>
            )}
            {item.variants && item.variants.length > 1 && (
              <span className="absolute bottom-2 left-2 rounded-full bg-background/80 px-2 py-0.5 text-[10px] font-medium text-muted">
                {item.variants.length} options
              </span>
            )}
          </div>

          <div className="flex flex-1 flex-col p-3.5">
            {item.category && (
              <span className="mb-1 text-[10px] font-medium uppercase tracking-wider text-muted">
                {item.category}
              </span>
            )}
            <h3 className="line-clamp-2 text-sm font-semibold leading-snug">
              {item.name}
            </h3>
            {item.brand && (
              <p className="mt-0.5 text-[11px] text-muted">{item.brand}</p>
            )}

            <div className="mt-auto flex items-center justify-between pt-3">
              <span className="text-base font-bold text-accent">
                {formatPrice(price, currencySymbol, currencyCode)}
              </span>
              <button
                onClick={handleAdd}
                disabled={isOutOfStock}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-white/[0.08] ring-1 ring-white/[0.06] transition hover:bg-accent hover:text-background hover:ring-0 disabled:opacity-40 disabled:hover:bg-white/[0.08] disabled:hover:text-foreground"
              >
                <motion.div
                  key={added ? "check" : "plus"}
                  initial={{ scale: 0.4, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ duration: 0.2 }}
                >
                  {added ? (
                    <Check className="h-3.5 w-3.5" />
                  ) : (
                    <Plus className="h-3.5 w-3.5" />
                  )}
                </motion.div>
              </button>
            </div>
          </div>
        </motion.div>
      </HoverLift>

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
