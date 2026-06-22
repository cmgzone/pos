"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Check, Clock, Calendar } from "lucide-react";
import type { CatalogItem } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { StaggerItem } from "./motion";

interface ServiceCardProps {
  item: CatalogItem;
  currencySymbol: string;
  currencyCode: string;
}

export function ServiceCard({ item, currencySymbol, currencyCode }: ServiceCardProps) {
  const { addToCart } = useStore();
  const [added, setAdded] = useState(false);

  const handleAdd = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    addToCart(item, undefined);
    setAdded(true);
    setTimeout(() => setAdded(false), 1200);
  };

  const duration = item.durationMinutes;

  return (
    <StaggerItem>
      <div className="group flex flex-col overflow-hidden rounded-lg border border-border-subtle bg-surface transition hover:border-border-strong">
        <div className="relative flex aspect-[4/5] flex-col items-center justify-center gap-4 border-b border-border-subtle bg-surface-elevated">
          <div className="flex h-14 w-14 items-center justify-center rounded-full ring-1 ring-border-strong">
            <Calendar className="h-6 w-6 text-muted-strong" />
          </div>
          <span className="text-[10px] font-semibold uppercase tracking-[0.16em] text-muted">
            Service
          </span>
        </div>

        <div className="flex flex-1 flex-col p-4">
          {item.category && (
            <span className="mb-1.5 text-[10px] font-medium uppercase tracking-[0.12em] text-muted">
              {item.category}
            </span>
          )}
          <h3 className="line-clamp-2 text-[15px] font-medium leading-snug text-foreground">
            {item.name}
          </h3>
          {item.description && (
            <p className="mt-1.5 line-clamp-2 text-[12px] leading-relaxed text-muted">
              {item.description}
            </p>
          )}

          <div className="mt-4 flex items-center justify-between gap-3">
            <div className="flex flex-col">
              <span className="text-[17px] font-semibold tracking-tight text-accent">
                {formatPrice(item.price, currencySymbol, currencyCode)}
              </span>
              {duration && (
                <span className="flex items-center gap-1 text-[11px] text-muted">
                  <Clock className="h-3 w-3" />
                  {duration} min
                </span>
              )}
            </div>
          </div>

          <button
            onClick={handleAdd}
            className="mt-3 inline-flex h-10 items-center justify-center gap-2 rounded-md border border-border-subtle bg-surface-elevated text-[13px] font-semibold text-foreground transition hover:border-accent hover:bg-accent hover:text-background"
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
                  <Plus className="h-4 w-4" />
                  Book now
                </>
              )}
            </motion.span>
          </button>
        </div>
      </div>
    </StaggerItem>
  );
}
