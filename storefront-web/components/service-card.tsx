"use client";

import { useState } from "react";
import { motion } from "framer-motion";
import { Plus, Check, Clock, Scissors } from "lucide-react";
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

  const duration = item.durationMinutes;

  return (
    <StaggerItem>
      <HoverLift>
        <motion.div
          className="group relative flex flex-col overflow-hidden rounded-2xl bg-[#141418] ring-1 ring-white/[0.05]"
          whileHover={{ boxShadow: "0 0 0 1px rgba(244,196,48,0.15)" }}
        >
          <div className="relative flex aspect-[4/3] flex-col items-center justify-center gap-3 overflow-hidden bg-gradient-to-br from-accent/[0.08] to-accent/[0.02]">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-accent/[0.12] ring-1 ring-accent/20">
              <Scissors className="h-5 w-5 text-accent/50" />
            </div>
            <span className="rounded-full bg-accent/15 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-accent">
              Service
            </span>
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
            {item.description && (
              <p className="mt-1.5 line-clamp-2 text-[11px] leading-relaxed text-muted">
                {item.description}
              </p>
            )}

            <div className="mt-auto flex items-center justify-between pt-3">
              <div className="flex flex-col">
                <span className="text-base font-bold text-accent">
                  {formatPrice(item.price, currency, currency)}
                </span>
                {duration && (
                  <span className="flex items-center gap-1 text-[10px] text-muted">
                    <Clock className="h-3 w-3" />
                    {duration} min
                  </span>
                )}
              </div>
              <button
                onClick={handleAdd}
                className="flex h-8 w-8 items-center justify-center rounded-full bg-white/[0.08] ring-1 ring-white/[0.06] transition hover:bg-accent hover:text-background hover:ring-0"
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
    </StaggerItem>
  );
}
