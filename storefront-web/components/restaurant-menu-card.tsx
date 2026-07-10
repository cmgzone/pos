"use client";

import { useState } from "react";
import { Check, Plus, UtensilsCrossed } from "lucide-react";
import { motion } from "framer-motion";
import type { CatalogItem } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { StaggerItem } from "./motion";

interface RestaurantMenuCardProps {
  item: CatalogItem;
  currencySymbol: string;
  currencyCode: string;
}

export function RestaurantMenuCard({
  item,
  currencySymbol,
  currencyCode,
}: RestaurantMenuCardProps) {
  const { addToCart } = useStore();
  const [added, setAdded] = useState(false);
  const imageUrl = item.imageUrls?.[0] || item.imageUrl;

  const add = () => {
    addToCart(item);
    setAdded(true);
    window.setTimeout(() => setAdded(false), 1200);
  };

  return (
    <StaggerItem>
      <article className="group overflow-hidden rounded-2xl border border-border-subtle bg-surface shadow-sm transition hover:-translate-y-0.5 hover:border-accent/60 hover:shadow-md">
        <div className="relative aspect-[16/10] overflow-hidden bg-surface-elevated">
          {imageUrl ? (
            <img
              src={imageUrl}
              alt={item.name}
              className="h-full w-full object-cover transition duration-500 group-hover:scale-105"
            />
          ) : (
            <div className="flex h-full items-center justify-center bg-gradient-to-br from-accent/15 via-surface-elevated to-surface">
              <UtensilsCrossed className="h-8 w-8 text-accent" />
            </div>
          )}
          {item.category && (
            <span className="absolute left-3 top-3 rounded-full bg-background/90 px-2.5 py-1 text-[10px] font-bold uppercase tracking-[0.12em] text-foreground backdrop-blur">
              {item.category}
            </span>
          )}
        </div>
        <div className="p-4">
          <div className="flex items-start justify-between gap-3">
            <h3 className="text-[16px] font-semibold leading-snug text-foreground">
              {item.name}
            </h3>
            <span className="shrink-0 text-[15px] font-bold text-accent">
              {formatPrice(item.price, currencySymbol, currencyCode)}
            </span>
          </div>
          {item.description && (
            <p className="mt-2 line-clamp-2 text-[12px] leading-relaxed text-muted">
              {item.description}
            </p>
          )}
          <button
            onClick={add}
            className="mt-4 inline-flex h-10 w-full items-center justify-center gap-2 rounded-xl bg-accent text-[13px] font-semibold text-background transition hover:opacity-90"
          >
            <motion.span
              key={added ? "added" : "add"}
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              className="inline-flex items-center gap-2"
            >
              {added ? <Check className="h-4 w-4" /> : <Plus className="h-4 w-4" />}
              {added ? "Added to order" : "Add to order"}
            </motion.span>
          </button>
        </div>
      </article>
    </StaggerItem>
  );
}
