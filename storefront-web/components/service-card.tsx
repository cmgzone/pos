"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Check, Clock, Sparkles } from "lucide-react";
import type { CatalogItem } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { StaggerItem, HoverLift } from "./motion";

interface ServiceCardProps {
  item: CatalogItem;
  currency: string;
}

export function ServiceCard({ item, currency }: ServiceCardProps) {
  const { addToCart } = useStore();
  const [added, setAdded] = useState(false);

  const handleAdd = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    addToCart(item, undefined);
    setAdded(true);
    setTimeout(() => setAdded(false), 1200);
  };

  return (
    <StaggerItem>
      <HoverLift>
        <motion.div
          className="group relative flex flex-col overflow-hidden rounded-2xl bg-surface ring-1 ring-white/[0.06]"
          whileHover={{ boxShadow: "0 0 0 1px rgba(167,139,250,0.15)" }}
        >
          <div className="relative flex aspect-[4/3] items-center justify-center overflow-hidden bg-gradient-to-br from-accent-2/10 to-transparent">
            <Sparkles className="h-12 w-12 text-accent-2/30" />
            <span className="absolute left-3 top-3 rounded-full bg-accent-2/20 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider text-accent-2">
              Service
            </span>
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
            {item.description && (
              <p className="mt-2 line-clamp-2 text-xs text-muted">
                {item.description}
              </p>
            )}

            <div className="mt-auto flex items-center justify-between pt-4">
              <div className="flex flex-col">
                <span className="text-lg font-bold text-accent-2">
                  {formatPrice(item.price, currency, currency)}
                </span>
                {item.durationMinutes && (
                  <span className="flex items-center gap-1 text-[11px] text-muted">
                    <Clock className="h-3 w-3" />
                    {item.durationMinutes} min
                  </span>
                )}
              </div>
              <button
                onClick={handleAdd}
                className="flex h-9 w-9 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-white/10 transition hover:bg-accent-2 hover:text-background hover:ring-0"
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
    </StaggerItem>
  );
}
