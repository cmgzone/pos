"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, CheckCircle, Loader2, Truck, Store } from "lucide-react";
import type { Business, OrderPayload } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { placeOrder } from "@/lib/api";
import { ScaleIn } from "./motion";

interface CheckoutModalProps {
  business: Business;
  currency: string;
  onClose: () => void;
}

export function CheckoutModal({ business, currency, onClose }: CheckoutModalProps) {
  const { cart, cartTotal, clearCart } = useStore();
  const [customerName, setCustomerName] = useState("");
  const [phone, setPhone] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [fulfillmentMethod, setFulfillmentMethod] = useState<"pickup" | "delivery">("pickup");
  const [note, setNote] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [result, setResult] = useState<{ orderNumber: string } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!customerName.trim() || !phone.trim()) return;

    const payload: OrderPayload = {
      branchId: business.selectedBranch.id,
      customerName: customerName.trim(),
      phone: phone.trim(),
      deliveryAddress: deliveryAddress.trim() || undefined,
      fulfillmentMethod,
      note: note.trim() || undefined,
      items: cart.map(({ item, variant, quantity }) => ({
        itemType: item.itemType,
        productId: item.itemType === "product" ? item.id : undefined,
        serviceId: item.itemType === "service" ? item.id : undefined,
        variantId: variant?.id,
        quantity,
      })),
    };

    setIsSubmitting(true);
    setError(null);
    try {
      const data = await placeOrder(business.id, payload);
      setResult(data);
      clearCart();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Order failed");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        onClick={onClose}
        className="absolute inset-0 bg-black/70 backdrop-blur-sm"
      />
      <ScaleIn className="relative w-full max-w-lg max-h-[90vh] overflow-y-auto rounded-3xl bg-surface ring-1 ring-white/10">
        <button
          onClick={onClose}
          className="absolute right-4 top-4 z-10 flex h-8 w-8 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-white/10 transition hover:bg-white/10"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="p-6 sm:p-8">
          <h2 className="text-2xl font-bold tracking-tight">Checkout</h2>
          <p className="mt-1 text-sm text-muted">
            Complete your order at {business.name}
          </p>

          <AnimatePresence mode="wait">
            {result ? (
              <motion.div
                key="success"
                initial={{ opacity: 0, scale: 0.96 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.96 }}
                className="mt-8 flex flex-col items-center rounded-2xl bg-surface-elevated p-8 text-center ring-1 ring-white/[0.06]"
              >
                <div className="flex h-16 w-16 items-center justify-center rounded-full bg-emerald-500/10">
                  <CheckCircle className="h-8 w-8 text-emerald-400" />
                </div>
                <h3 className="mt-4 text-xl font-semibold">Order placed!</h3>
                <p className="mt-2 text-sm text-muted">
                  Your order number is
                </p>
                <p className="mt-1 text-3xl font-bold text-accent">
                  #{result.orderNumber}
                </p>
                <button
                  onClick={onClose}
                  className="mt-6 rounded-full bg-accent px-6 py-2.5 text-sm font-semibold text-background transition hover:opacity-90"
                >
                  Continue shopping
                </button>
              </motion.div>
            ) : (
              <motion.form
                key="form"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                onSubmit={handleSubmit}
                className="mt-6 space-y-4"
              >
                <div>
                  <label className="mb-1 block text-xs font-medium uppercase tracking-wider text-muted">
                    Full name
                  </label>
                  <input
                    required
                    value={customerName}
                    onChange={(e) => setCustomerName(e.target.value)}
                    placeholder="John Doe"
                    className="h-11 w-full rounded-xl bg-surface-elevated px-4 text-sm ring-1 ring-white/10 focus:outline-none focus:ring-2 focus:ring-accent/50"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium uppercase tracking-wider text-muted">
                    Phone number
                  </label>
                  <input
                    required
                    type="tel"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="+254 712 345 678"
                    className="h-11 w-full rounded-xl bg-surface-elevated px-4 text-sm ring-1 ring-white/10 focus:outline-none focus:ring-2 focus:ring-accent/50"
                  />
                </div>

                <div>
                  <label className="mb-2 block text-xs font-medium uppercase tracking-wider text-muted">
                    Fulfillment
                  </label>
                  <div className="grid grid-cols-2 gap-3">
                    <button
                      type="button"
                      onClick={() => setFulfillmentMethod("pickup")}
                      className={`flex items-center justify-center gap-2 rounded-xl py-2.5 text-sm font-medium transition ${
                        fulfillmentMethod === "pickup"
                          ? "bg-accent text-background"
                          : "bg-surface-elevated ring-1 ring-white/10 hover:bg-white/5"
                      }`}
                    >
                      <Store className="h-4 w-4" />
                      Pickup
                    </button>
                    <button
                      type="button"
                      onClick={() => setFulfillmentMethod("delivery")}
                      className={`flex items-center justify-center gap-2 rounded-xl py-2.5 text-sm font-medium transition ${
                        fulfillmentMethod === "delivery"
                          ? "bg-accent text-background"
                          : "bg-surface-elevated ring-1 ring-white/10 hover:bg-white/5"
                      }`}
                    >
                      <Truck className="h-4 w-4" />
                      Delivery
                    </button>
                  </div>
                </div>

                {fulfillmentMethod === "delivery" && (
                  <motion.div
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: "auto" }}
                    exit={{ opacity: 0, height: 0 }}
                  >
                    <label className="mb-1 block text-xs font-medium uppercase tracking-wider text-muted">
                      Delivery address
                    </label>
                    <input
                      required={fulfillmentMethod === "delivery"}
                      value={deliveryAddress}
                      onChange={(e) => setDeliveryAddress(e.target.value)}
                      placeholder="123 Main Street, City"
                      className="h-11 w-full rounded-xl bg-surface-elevated px-4 text-sm ring-1 ring-white/10 focus:outline-none focus:ring-2 focus:ring-accent/50"
                    />
                  </motion.div>
                )}

                <div>
                  <label className="mb-1 block text-xs font-medium uppercase tracking-wider text-muted">
                    Note (optional)
                  </label>
                  <textarea
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    rows={3}
                    placeholder="Any special instructions..."
                    className="w-full rounded-xl bg-surface-elevated px-4 py-3 text-sm ring-1 ring-white/10 focus:outline-none focus:ring-2 focus:ring-accent/50"
                  />
                </div>

                {error && (
                  <p className="rounded-xl bg-red-500/10 px-4 py-2 text-sm text-red-300">
                    {error}
                  </p>
                )}

                <div className="flex items-center justify-between border-t border-white/10 pt-4">
                  <span className="text-muted">Total</span>
                  <span className="text-2xl font-bold text-accent">
                    {formatPrice(cartTotal, currency, currency)}
                  </span>
                </div>

                <button
                  type="submit"
                  disabled={isSubmitting || cart.length === 0}
                  className="flex w-full items-center justify-center gap-2 rounded-full bg-accent py-3 text-sm font-semibold text-background transition hover:opacity-90 disabled:opacity-50"
                >
                  {isSubmitting ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Placing order...
                    </>
                  ) : (
                    <>Place order</>
                  )}
                </button>
              </motion.form>
            )}
          </AnimatePresence>
        </div>
      </ScaleIn>
    </div>
  );
}
