"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Check, Loader2, Truck, Store } from "lucide-react";
import type { Business, OrderPayload } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { placeOrder } from "@/lib/api";
import { ScaleIn } from "./motion";

interface CheckoutModalProps {
  business: Business;
  currencySymbol: string;
  currencyCode: string;
  onClose: () => void;
}

export function CheckoutModal({
  business,
  currencySymbol,
  currencyCode,
  onClose,
}: CheckoutModalProps) {
  const { cart, cartTotal, clearCart } = useStore();
  const [customerName, setCustomerName] = useState("");
  const [phone, setPhone] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [fulfillmentMethod, setFulfillmentMethod] = useState<"pickup" | "delivery">(
    "pickup"
  );
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
      items: cart.map(({ item, variant, quantity }) => {
        const itemType = item.itemType || item.type || "product";
        return {
          itemType,
          productId: itemType === "product" ? item.productId || item.id : undefined,
          serviceId: itemType === "service" ? item.serviceId || item.id : undefined,
          variantId: variant?.id,
          quantity,
        };
      }),
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

  const inputClass =
    "h-11 w-full rounded-md border border-border-subtle bg-surface px-3.5 text-[14px] text-foreground placeholder:text-muted focus:border-border-strong focus:outline-none";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        onClick={onClose}
        className="absolute inset-0 bg-black/60"
      />
      <ScaleIn className="relative flex max-h-[90vh] w-full max-w-lg flex-col overflow-hidden rounded-xl border border-border-subtle bg-surface">
        <div className="flex items-center justify-between border-b border-border-subtle px-6 py-4">
          <div>
            <h2 className="font-display text-2xl tracking-tight">Checkout</h2>
            <p className="mt-0.5 text-[13px] text-muted">{business.name}</p>
          </div>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-md text-muted transition hover:bg-surface-elevated hover:text-foreground"
            aria-label="Close checkout"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="overflow-y-auto px-6 py-6">
          <AnimatePresence mode="wait">
            {result ? (
              <motion.div
                key="success"
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="flex flex-col items-center py-8 text-center"
              >
                <div className="flex h-14 w-14 items-center justify-center rounded-full bg-foreground text-background">
                  <Check className="h-7 w-7" />
                </div>
                <h3 className="mt-5 text-xl font-semibold">Order placed</h3>
                <p className="mt-2 text-[13px] text-muted">
                  Save your order number to track this order later.
                </p>
                <p className="mt-4 font-display text-4xl tracking-tight">
                  #{result.orderNumber}
                </p>
                <button
                  onClick={onClose}
                  className="mt-8 rounded-md bg-foreground px-6 py-3 text-[14px] font-semibold text-background transition hover:opacity-90"
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
                className="space-y-5"
              >
                <div className="space-y-4">
                  <div>
                    <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                      Full name
                    </label>
                    <input
                      required
                      value={customerName}
                      onChange={(e) => setCustomerName(e.target.value)}
                      placeholder="John Doe"
                      className={inputClass}
                    />
                  </div>
                  <div>
                    <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                      Phone number
                    </label>
                    <input
                      required
                      type="tel"
                      value={phone}
                      onChange={(e) => setPhone(e.target.value)}
                      placeholder="+254 712 345 678"
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <label className="mb-2 block text-[12px] font-medium text-muted-strong">
                      Fulfillment
                    </label>
                    <div className="grid grid-cols-2 gap-2.5">
                      <button
                        type="button"
                        onClick={() => setFulfillmentMethod("pickup")}
                        className={`flex items-center justify-center gap-2 rounded-md border py-2.5 text-[13px] font-medium transition ${
                          fulfillmentMethod === "pickup"
                            ? "border-foreground bg-foreground text-background"
                            : "border-border-subtle bg-surface-elevated text-foreground hover:border-border-strong"
                        }`}
                      >
                        <Store className="h-4 w-4" />
                        Pickup
                      </button>
                      <button
                        type="button"
                        onClick={() => setFulfillmentMethod("delivery")}
                        className={`flex items-center justify-center gap-2 rounded-md border py-2.5 text-[13px] font-medium transition ${
                          fulfillmentMethod === "delivery"
                            ? "border-foreground bg-foreground text-background"
                            : "border-border-subtle bg-surface-elevated text-foreground hover:border-border-strong"
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
                      <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                        Delivery address
                      </label>
                      <input
                        required={fulfillmentMethod === "delivery"}
                        value={deliveryAddress}
                        onChange={(e) => setDeliveryAddress(e.target.value)}
                        placeholder="123 Main Street, City"
                        className={inputClass}
                      />
                    </motion.div>
                  )}

                  <div>
                    <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                      Note <span className="text-muted">(optional)</span>
                    </label>
                    <textarea
                      value={note}
                      onChange={(e) => setNote(e.target.value)}
                      rows={3}
                      placeholder="Any special instructions..."
                      className="w-full rounded-md border border-border-subtle bg-surface px-3.5 py-3 text-[14px] text-foreground placeholder:text-muted focus:border-border-strong focus:outline-none"
                    />
                  </div>
                </div>

                <div className="rounded-md border border-border-subtle bg-surface-elevated p-4">
                  <div className="mb-2 flex items-center justify-between text-[12px] font-medium uppercase tracking-wider text-muted">
                    <span>Order summary</span>
                    <span>{cart.length} {cart.length === 1 ? "item" : "items"}</span>
                  </div>
                  <ul className="space-y-1.5">
                    {cart.map(({ key, item, variant, quantity }) => {
                      const linePrice = (variant ? variant.price : item.price) * quantity;
                      return (
                        <li
                          key={key}
                          className="flex items-center justify-between text-[13px]"
                        >
                          <span className="truncate pr-3 text-muted-strong">
                            {quantity}× {item.name}
                            {variant ? ` (${variant.name})` : ""}
                          </span>
                          <span className="shrink-0 tabular-nums">
                            {formatPrice(linePrice, currencySymbol, currencyCode)}
                          </span>
                        </li>
                      );
                    })}
                  </ul>
                  <div className="mt-3 flex items-center justify-between border-t border-border-subtle pt-3">
                    <span className="text-[13px] text-muted">Total</span>
                    <span className="text-lg font-semibold tabular-nums">
                      {formatPrice(cartTotal, currencySymbol, currencyCode)}
                    </span>
                  </div>
                </div>

                {error && (
                  <p className="rounded-md border border-border-subtle bg-surface-elevated px-3.5 py-2.5 text-[13px] text-foreground">
                    {error}
                  </p>
                )}

                <button
                  type="submit"
                  disabled={isSubmitting || cart.length === 0}
                  className="flex w-full items-center justify-center gap-2 rounded-md bg-foreground py-3 text-[14px] font-semibold text-background transition hover:opacity-90 disabled:opacity-50"
                >
                  {isSubmitting ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Placing order…
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
