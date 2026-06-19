"use client";

import { motion, AnimatePresence } from "framer-motion";
import { X, Plus, Minus, ShoppingBag, Trash2 } from "lucide-react";
import { useStore } from "./store-provider";
import { formatPrice } from "@/lib/utils";

interface CartDrawerProps {
  onCheckout: () => void;
  currency: string;
}

export function CartDrawer({ onCheckout, currency }: CartDrawerProps) {
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
            className="absolute inset-0 bg-black/60 backdrop-blur-sm"
          />
          <motion.div
            initial={{ x: "100%" }}
            animate={{ x: 0 }}
            exit={{ x: "100%" }}
            transition={{ type: "spring", damping: 25, stiffness: 200 }}
            className="absolute right-0 top-0 h-full w-full max-w-md bg-surface shadow-2xl ring-1 ring-white/10"
          >
            <div className="flex h-full flex-col">
              <div className="flex items-center justify-between border-b border-white/10 p-5">
                <div className="flex items-center gap-3">
                  <ShoppingBag className="h-5 w-5 text-accent" />
                  <h2 className="text-lg font-semibold">Your cart</h2>
                  <span className="rounded-full bg-surface-elevated px-2 py-0.5 text-xs text-muted">
                    {cartCount}
                  </span>
                </div>
                <button
                  onClick={() => setIsCartOpen(false)}
                  className="flex h-8 w-8 items-center justify-center rounded-full transition hover:bg-white/5"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>

              {cart.length === 0 ? (
                <div className="flex flex-1 flex-col items-center justify-center gap-4 p-8 text-center text-muted">
                  <ShoppingBag className="h-12 w-12 opacity-20" />
                  <p>Your cart is empty.</p>
                  <button
                    onClick={() => setIsCartOpen(false)}
                    className="text-sm text-accent hover:underline"
                  >
                    Continue shopping
                  </button>
                </div>
              ) : (
                <>
                  <div className="flex-1 overflow-y-auto p-5">
                    <div className="space-y-4">
                      {cart.map(({ key, item, variant, quantity }) => {
                        const price = variant ? variant.price : item.price;
                        return (
                          <motion.div
                            layout
                            key={key}
                            className="flex gap-4 rounded-2xl bg-surface-elevated p-3 ring-1 ring-white/[0.06]"
                          >
                            <div className="h-16 w-16 shrink-0 overflow-hidden rounded-xl bg-surface">
                              {item.imageUrl ? (
                                <img
                                  src={item.imageUrl}
                                  alt={item.name}
                                  className="h-full w-full object-cover"
                                />
                              ) : (
                                <div className="flex h-full w-full items-center justify-center">
                                  <ShoppingBag className="h-5 w-5 text-white/10" />
                                </div>
                              )}
                            </div>
                            <div className="flex flex-1 flex-col">
                              <h4 className="line-clamp-1 text-sm font-medium">
                                {item.name}
                              </h4>
                              {variant && (
                                <span className="text-xs text-muted">
                                  {variant.name}
                                </span>
                              )}
                              <div className="mt-auto flex items-center justify-between">
                                <span className="text-sm font-semibold text-accent">
                                  {formatPrice(price * quantity, currency, currency)}
                                </span>
                                <div className="flex items-center gap-2">
                                  <button
                                    onClick={() =>
                                      updateQuantity(key, quantity - 1)
                                    }
                                    className="flex h-6 w-6 items-center justify-center rounded-full bg-surface ring-1 ring-white/10 transition hover:bg-white/5"
                                  >
                                    <Minus className="h-3 w-3" />
                                  </button>
                                  <span className="w-4 text-center text-sm">
                                    {quantity}
                                  </span>
                                  <button
                                    onClick={() =>
                                      updateQuantity(key, quantity + 1)
                                    }
                                    className="flex h-6 w-6 items-center justify-center rounded-full bg-surface ring-1 ring-white/10 transition hover:bg-white/5"
                                  >
                                    <Plus className="h-3 w-3" />
                                  </button>
                                </div>
                              </div>
                            </div>
                            <button
                              onClick={() => removeFromCart(key)}
                              className="self-start text-muted transition hover:text-red-400"
                            >
                              <Trash2 className="h-4 w-4" />
                            </button>
                          </motion.div>
                        );
                      })}
                    </div>
                  </div>

                  <div className="border-t border-white/10 p-5">
                    <div className="mb-4 flex items-center justify-between text-sm">
                      <span className="text-muted">Subtotal</span>
                      <span className="font-semibold">
                        {formatPrice(cartTotal, currency, currency)}
                      </span>
                    </div>
                    <button
                      onClick={() => {
                        setIsCartOpen(false);
                        onCheckout();
                      }}
                      className="w-full rounded-full bg-accent py-3 text-sm font-semibold text-background transition hover:opacity-90"
                    >
                      Checkout
                    </button>
                  </div>
                </>
              )}
            </div>
          </motion.div>
        </div>
      )}
    </AnimatePresence>
  );
}
