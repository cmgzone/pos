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
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      onClick={onOpen}
      className="fixed bottom-6 right-6 z-40 flex h-14 w-14 items-center justify-center rounded-full bg-accent text-background shadow-lg shadow-accent/20 ring-1 ring-white/10"
    >
      <ShoppingBag className="h-5 w-5" />
      <AnimatePresence>
        {cartCount > 0 && (
          <motion.span
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            exit={{ scale: 0 }}
            className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full bg-background text-[10px] font-bold text-foreground ring-1 ring-accent"
          >
            {cartCount > 9 ? "9+" : cartCount}
          </motion.span>
        )}
      </AnimatePresence>
    </motion.button>
  );
}
