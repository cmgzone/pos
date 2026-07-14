"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Check, Loader2, Truck, Store } from "lucide-react";
import type {
  Business,
  OrderPayload,
  StorefrontCheckoutSettings,
  StorefrontType,
} from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { useStore } from "./store-provider";
import { placeOrder } from "@/lib/api";
import { ScaleIn } from "./motion";

const DEFAULT_CHECKOUT: StorefrontCheckoutSettings = {
  paymentMethods: ["manual"],
  defaultPaymentMethod: "manual",
  fulfillmentMethods: ["pickup", "delivery"],
  defaultFulfillmentMethod: "pickup",
  showDeliveryAddress: true,
  showOrderNote: true,
  showOrderTracking: true,
  checkoutTitle: "Checkout",
  checkoutButtonLabel: "Place order",
  successMessage: "Your order has been received.",
};

interface CheckoutModalProps {
  business: Business;
  currencySymbol: string;
  currencyCode: string;
  storefrontType: StorefrontType;
  checkout?: StorefrontCheckoutSettings;
  onClose: () => void;
}

type CheckoutResult = {
  orderNumber: string;
  trackingCode?: string;
  paymentMethod?: string;
  paymentStatus?: string;
  paymentRequestId?: string;
};

export function CheckoutModal({
  business,
  currencySymbol,
  currencyCode,
  storefrontType,
  checkout: checkoutInput,
  onClose,
}: CheckoutModalProps) {
  const checkout = checkoutInput || DEFAULT_CHECKOUT;
  const paymentMethods = checkout.paymentMethods.length
    ? checkout.paymentMethods
    : DEFAULT_CHECKOUT.paymentMethods;
  const fulfillmentMethods = checkout.fulfillmentMethods.length
    ? checkout.fulfillmentMethods
    : DEFAULT_CHECKOUT.fulfillmentMethods;
  const initialPayment = paymentMethods.includes(checkout.defaultPaymentMethod)
    ? checkout.defaultPaymentMethod
    : paymentMethods[0];
  const initialFulfillment = fulfillmentMethods.includes(checkout.defaultFulfillmentMethod)
    ? checkout.defaultFulfillmentMethod
    : fulfillmentMethods[0];
  const { cart, cartTotal, clearCart } = useStore();
  const [customerName, setCustomerName] = useState("");
  const [phone, setPhone] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [fulfillmentMethod, setFulfillmentMethod] = useState<"pickup" | "delivery">(
    initialFulfillment,
  );
  const [note, setNote] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<"manual" | "mpesa">(
    initialPayment,
  );
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [result, setResult] = useState<CheckoutResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!customerName.trim() || !phone.trim()) return;

    const payload: OrderPayload = {
      branchId: business.selectedBranch.id,
      storefrontType,
      customerName: customerName.trim(),
      phone: phone.trim(),
      deliveryAddress:
        checkout.showDeliveryAddress && fulfillmentMethod === "delivery"
          ? deliveryAddress.trim() || undefined
          : undefined,
      fulfillmentMethod,
      note: checkout.showOrderNote ? note.trim() || undefined : undefined,
      paymentMethod,
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
    "h-11 w-full rounded-md border border-border-subtle bg-surface px-3.5 text-[14px] text-foreground placeholder:text-muted focus:border-accent focus:outline-none";

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
            <h2 className="font-display text-2xl tracking-tight">
              {checkout.checkoutTitle}
            </h2>
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
                <div className="flex h-14 w-14 items-center justify-center rounded-full bg-accent text-background">
                  <Check className="h-7 w-7" />
                </div>
                <h3 className="mt-5 text-xl font-semibold">Order placed</h3>
                <p className="mt-2 text-[13px] text-muted">
                  {checkout.successMessage}
                </p>
                {result.paymentMethod === "mpesa" && result.paymentStatus === "initiated" && (
                  <p className="mt-2 rounded-md border border-border-subtle bg-surface-elevated px-4 py-3 text-[13px] text-muted-strong">
                    Check your phone and enter your M-Pesa PIN to complete payment.
                  </p>
                )}
                <p className="mt-4 font-display text-4xl tracking-tight text-accent">
                  #{result.orderNumber}
                </p>
                {checkout.showOrderTracking && result.trackingCode && (
                  <p className="mt-3 text-[13px] text-muted">
                    Delivery tracking: {result.trackingCode}
                  </p>
                )}
                {result.paymentStatus && (
                  <p className="mt-1 text-[13px] text-muted">
                    Payment: {result.paymentStatus}
                  </p>
                )}
                <button
                  onClick={onClose}
                  className="mt-8 rounded-md bg-accent px-6 py-3 text-[14px] font-semibold text-background transition hover:opacity-90"
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
                      Payment
                    </label>
                    <select
                      value={paymentMethod}
                      onChange={(event) =>
                        setPaymentMethod(event.target.value as "manual" | "mpesa")
                      }
                      className={inputClass}
                    >
                      {paymentMethods.map((method) => (
                        <option key={method} value={method}>
                          {method === "mpesa" ? "M-Pesa" : "Pay on confirmation"}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                      Full name
                    </label>
                    <input
                      required
                      value={customerName}
                      onChange={(event) => setCustomerName(event.target.value)}
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
                      onChange={(event) => setPhone(event.target.value)}
                      placeholder="+254 712 345 678"
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <label className="mb-2 block text-[12px] font-medium text-muted-strong">
                      Fulfillment
                    </label>
                    <div
                      className={`grid gap-2.5 ${
                        fulfillmentMethods.length > 1 ? "grid-cols-2" : "grid-cols-1"
                      }`}
                    >
                      {fulfillmentMethods.map((method) => (
                        <button
                          key={method}
                          type="button"
                          onClick={() => setFulfillmentMethod(method)}
                          className={`flex items-center justify-center gap-2 rounded-md border py-2.5 text-[13px] font-medium transition ${
                            fulfillmentMethod === method
                              ? "border-accent bg-accent text-background"
                              : "border-border-subtle bg-surface-elevated text-foreground hover:border-border-strong"
                          }`}
                        >
                          {method === "pickup" ? (
                            <Store className="h-4 w-4" />
                          ) : (
                            <Truck className="h-4 w-4" />
                          )}
                          {method === "pickup" ? "Pickup" : "Delivery"}
                        </button>
                      ))}
                    </div>
                  </div>

                  {checkout.showDeliveryAddress && fulfillmentMethod === "delivery" && (
                    <motion.div
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: "auto" }}
                      exit={{ opacity: 0, height: 0 }}
                    >
                      <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                        Delivery address
                      </label>
                      <input
                        required
                        value={deliveryAddress}
                        onChange={(event) => setDeliveryAddress(event.target.value)}
                        placeholder="123 Main Street, City"
                        className={inputClass}
                      />
                    </motion.div>
                  )}

                  {checkout.showOrderNote && (
                    <div>
                      <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                        Note <span className="text-muted">(optional)</span>
                      </label>
                      <textarea
                        value={note}
                        onChange={(event) => setNote(event.target.value)}
                        rows={3}
                        placeholder="Any special instructions..."
                        className="w-full rounded-md border border-border-subtle bg-surface px-3.5 py-3 text-[14px] text-foreground placeholder:text-muted focus:border-accent focus:outline-none"
                      />
                    </div>
                  )}
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
                        <li key={key} className="flex items-center justify-between text-[13px]">
                          <span className="truncate pr-3 text-muted-strong">
                            {quantity}× {item.name}{variant ? ` (${variant.name})` : ""}
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
                    <span className="text-lg font-semibold tabular-nums text-accent">
                      {formatPrice(cartTotal, currencySymbol, currencyCode)}
                    </span>
                  </div>
                </div>

                {paymentMethod === "mpesa" && (
                  <p className="rounded-md border border-border-subtle bg-surface-elevated px-3.5 py-2.5 text-[13px] text-muted-strong">
                    An M-Pesa payment request will be sent to the phone number above.
                  </p>
                )}
                {error && (
                  <p className="rounded-md border border-border-subtle bg-surface-elevated px-3.5 py-2.5 text-[13px] text-foreground">
                    {error}
                  </p>
                )}

                <button
                  type="submit"
                  disabled={isSubmitting || cart.length === 0}
                  className="flex w-full items-center justify-center gap-2 rounded-md bg-accent py-3 text-[14px] font-semibold text-background transition hover:opacity-90 disabled:opacity-50"
                >
                  {isSubmitting ? (
                    <>
                      <Loader2 className="h-4 w-4 animate-spin" />
                      Processing…
                    </>
                  ) : (
                    checkout.checkoutButtonLabel
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
