"use client";

import { motion, AnimatePresence } from "framer-motion";
import { ShoppingBag } from "lucide-react";
import { useStore } from "./store-provider";

interface FloatingCartProps {
  onOpen: () => void;
}

export function FloatingCart({ onOpen }: FloatingCartProps) {
  const { cartCount } = useStore();

  return (
    <motion.button
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      whileTap={{ scale: 0.96 }}
      onClick={onOpen}
      className="fixed bottom-5 right-5 z-40 flex h-12 w-12 items-center justify-center rounded-full bg-accent text-background shadow-lg shadow-black/30 ring-1 ring-border-strong sm:hidden"
      aria-label="Open cart"
    >
      <ShoppingBag className="h-5 w-5" />
      <AnimatePresence>
        {cartCount > 0 && (
          <motion.span
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            exit={{ scale: 0 }}
            className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-background px-1 text-[10px] font-bold text-foreground ring-1 ring-border-strong"
          >
            {cartCount > 9 ? "9+" : cartCount}
          </motion.span>
        )}
      </AnimatePresence>
    </motion.button>
  );
}
