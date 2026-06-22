"use client";

import { motion, AnimatePresence } from "framer-motion";
import { X, Plus, Minus, ShoppingBag, Trash2 } from "lucide-react";
import { useStore } from "./store-provider";
import { formatPrice } from "@/lib/utils";

interface CartDrawerProps {
  onCheckout: () => void;
  currencySymbol: string;
  currencyCode: string;
}

export function CartDrawer({ onCheckout, currencySymbol, currencyCode }: CartDrawerProps) {
  const {
    cart,
    isCartOpen,
    setIsCartOpen,
    updateQuantity,
    removeFromCart,
    cartTotal,
    cartCount,
  } = useStore();

  return (
    <AnimatePresence>
      {isCartOpen && (
        <div className="fixed inset-0 z-50">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setIsCartOpen(false)}
            className="absolute inset-0 bg-black/60"
          />
          <motion.div
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", damping: 28, stiffness: 240 }}
            className="absolute right-0 top-0 flex h-full w-full max-w-md flex-col border-l border-border-subtle bg-surface"
          >
            <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
              <div className="flex items-center gap-2.5">
                <ShoppingBag className="h-4 w-4 text-muted-strong" />
                <h2 className="text-[15px] font-semibold tracking-tight">Your cart</h2>
                <span className="text-[12px] text-muted">
                  {cartCount} {cartCount === 1 ? "item" : "items"}
                </span>
              </div>
              <button
                onClick={() => setIsCartOpen(false)}
                className="flex h-8 w-8 items-center justify-center rounded-md text-muted transition hover:bg-surface-elevated hover:text-foreground"
                aria-label="Close cart"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {cart.length === 0 ? (
              <div className="flex flex-1 flex-col items-center justify-center gap-4 p-8 text-center">
                <div className="flex h-14 w-14 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-border-subtle">
                  <ShoppingBag className="h-6 w-6 text-muted" />
                </div>
                <div>
                  <p className="text-[15px] font-medium">Your cart is empty</p>
                  <p className="mt-1 text-[13px] text-muted">
                    Add items to get started.
                  </p>
                </div>
                <button
                  onClick={() => setIsCartOpen(false)}
                  className="mt-2 rounded-md border border-border-subtle bg-surface-elevated px-4 py-2 text-[13px] font-semibold transition hover:border-accent hover:bg-accent hover:text-background"
                >
                  Continue shopping
                </button>
              </div>
            ) : (
              <>
                <div className="flex-1 overflow-y-auto px-5 py-4">
                  <ul className="space-y-4">
                    {cart.map(({ key, item, variant, quantity }) => {
                      const price = variant ? variant.price : item.price;
                      return (
                        <motion.li
                          layout
                          key={key}
                          className="flex gap-4"
                        >
                          <div className="h-20 w-16 shrink-0 overflow-hidden rounded-md border border-border-subtle bg-surface-elevated">
                            {item.imageUrl ? (
                              <img
                                src={item.imageUrl}
                                alt={item.name}
                                className="h-full w-full object-cover"
                              />
                            ) : (
                              <div className="flex h-full w-full items-center justify-center">
                                <ShoppingBag className="h-5 w-5 text-muted/40" />
                              </div>
                            )}
                          </div>
                          <div className="flex flex-1 flex-col">
                            <div className="flex items-start justify-between gap-2">
                              <h4 className="line-clamp-2 text-[14px] font-medium leading-snug">
                                {item.name}
                              </h4>
                              <button
                                onClick={() => removeFromCart(key)}
                                className="shrink-0 text-muted transition hover:text-foreground"
                                aria-label={`Remove ${item.name}`}
                              >
                                <Trash2 className="h-4 w-4" />
                              </button>
                            </div>
                            {variant && (
                              <span className="mt-0.5 text-[12px] text-muted">
                                {variant.name}
                              </span>
                            )}
                            <div className="mt-auto flex items-center justify-between pt-2">
                              <div className="inline-flex items-center rounded-md border border-border-subtle">
                                <button
                                  onClick={() => updateQuantity(key, quantity - 1)}
                                  className="flex h-7 w-7 items-center justify-center text-muted transition hover:text-foreground"
                                  aria-label="Decrease quantity"
                                >
                                  <Minus className="h-3 w-3" />
                                </button>
                                <span className="w-7 text-center text-[13px] font-medium tabular-nums">
                                  {quantity}
                                </span>
                                <button
                                  onClick={() => updateQuantity(key, quantity + 1)}
                                  className="flex h-7 w-7 items-center justify-center text-muted transition hover:text-foreground"
                                  aria-label="Increase quantity"
                                >
                                  <Plus className="h-3 w-3" />
                                </button>
                              </div>
                              <span className="text-[14px] font-semibold tabular-nums text-accent">
                                {formatPrice(price * quantity, currencySymbol, currencyCode)}
                              </span>
                            </div>
                          </div>
                        </motion.li>
                      );
                    })}
                  </ul>
                </div>

                <div className="border-t border-border-subtle px-5 py-4">
                  <div className="mb-3 flex items-center justify-between text-[14px]">
                    <span className="text-muted">Subtotal</span>
                    <span className="font-semibold tabular-nums text-accent">
                      {formatPrice(cartTotal, currencySymbol, currencyCode)}
                    </span>
                  </div>
                  <p className="mb-3 text-[11px] text-muted">
                    Taxes and shipping calculated at checkout.
                  </p>
                  <button
                    onClick={() => {
                      setIsCartOpen(false);
                      onCheckout();
                    }}
                    className="w-full rounded-md bg-accent py-3 text-[14px] font-semibold text-background transition hover:opacity-90"
                  >
                    Checkout
                  </button>
                </div>
              </>
            )}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
}
