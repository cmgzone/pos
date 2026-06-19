"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Check, Package } from "lucide-react";
import type { CatalogItem, ProductVariant } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { StaggerItem, HoverLift } from "./motion";
import { QuickViewModal } from "./quick-view-modal";

interface ProductCardProps {
  item: CatalogItem;
  currency: string;
}

export function ProductCard({ item, currency }: ProductCardProps) {
  const { addToCart } = useStore();
  const [selectedVariant, setSelectedVariant] = useState<ProductVariant | undefined>();
  const [showQuickView, setShowQuickView] = useState(false);
  const [added, setAdded] = useState(false);

  const price = selectedVariant ? selectedVariant.price : item.price;
  const isOutOfStock = item.trackStock && item.stock <= 0 && !item.hasVariants;

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

  const image = item.imageUrl || item.imageUrls?.[0];

  return (
    <StaggerItem>
      <HoverLift>
        <motion.div
          onClick={() => setShowQuickView(true)}
          className="group relative flex flex-col overflow-hidden rounded-2xl bg-surface ring-1 ring-white/[0.06] cursor-pointer"
          whileHover={{ boxShadow: "0 0 0 1px rgba(212,175,55,0.15)" }}
        >
          <div className="relative aspect-[4/3] overflow-hidden bg-surface-elevated">
            {image ? (
              <img
                src={image}
                alt={item.name}
                className="h-full w-full object-cover transition duration-700 group-hover:scale-105"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center">
                <Package className="h-10 w-10 text-white/10" />
              </div>
            )}
            {item.isFeatured && (
              <span className="absolute left-3 top-3 rounded-full bg-accent/90 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider text-background">
                Featured
              </span>
            )}
            {isOutOfStock && (
              <span className="absolute right-3 top-3 rounded-full bg-red-500/90 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider text-white">
                Out of stock
              </span>
            )}
          </div>

          <div className="flex flex-1 flex-col p-4">
            {item.category && (
              <span className="mb-1 text-[11px] font-medium uppercase tracking-wider text-muted">
                {item.category}
              </span>
            )}
            <h3 className="line-clamp-2 text-base font-semibold leading-snug">
              {item.name}
            </h3>
            {item.brand && (
              <p className="mt-1 text-xs text-muted">{item.brand}</p>
            )}

            <div className="mt-auto flex items-center justify-between pt-4">
              <span className="text-lg font-bold text-accent">
                {formatPrice(price, currency, currency)}
              </span>
              <button
                onClick={handleAdd}
                disabled={isOutOfStock}
                className="flex h-9 w-9 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-white/10 transition hover:bg-accent hover:text-background hover:ring-0 disabled:opacity-40 disabled:hover:bg-surface-elevated disabled:hover:text-foreground"
              >
                <motion.div
                  key={added ? "check" : "plus"}
                  initial={{ scale: 0.5, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  transition={{ duration: 0.2 }}
                >
                  {added ? (
                    <Check className="h-4 w-4" />
                  ) : (
                    <Plus className="h-4 w-4" />
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
          currency={currency}
          selectedVariant={selectedVariant}
          onVariantChange={setSelectedVariant}
          onClose={() => setShowQuickView(false)}
          onAdd={handleAdd}
        />
      )}
    </StaggerItem>
  );
}
