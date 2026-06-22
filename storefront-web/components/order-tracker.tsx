"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Search, Loader2, Truck, CheckCircle, Clock, Package, XCircle } from "lucide-react";
import type { Business, Order } from "@/lib/types";
import { formatPrice } from "@/lib/utils";
import { trackOrder } from "@/lib/api";
import { ScaleIn } from "./motion";

interface OrderTrackerProps {
  business: Business;
  currency: string;
  currencyCode: string;
  onClose: () => void;
}

const statusMeta: Record<string, { label: string; icon: React.ReactNode }> = {
  pending: { label: "Pending", icon: <Clock className="h-5 w-5" /> },
  processing: { label: "Processing", icon: <Package className="h-5 w-5" /> },
  ready: { label: "Ready", icon: <CheckCircle className="h-5 w-5" /> },
  delivered: { label: "Delivered", icon: <Truck className="h-5 w-5" /> },
  cancelled: { label: "Cancelled", icon: <XCircle className="h-5 w-5" /> },
};

export function OrderTracker({ business, currency, currencyCode, onClose }: OrderTrackerProps) {
  const [orderNumber, setOrderNumber] = useState("");
  const [phone, setPhone] = useState("");
  const [order, setOrder] = useState<Order | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setOrder(null);
    try {
      const data = await trackOrder(business.id, orderNumber.trim(), phone.trim());
      setOrder(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Order not found");
    } finally {
      setLoading(false);
    }
  };

  const inputClass =
    "h-11 w-full rounded-md border border-border-subtle bg-surface px-3.5 text-[14px] text-foreground placeholder:text-muted focus:border-accent focus:outline-none";

  const status = order ? statusMeta[order.status] || statusMeta.pending : null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        onClick={onClose}
        className="absolute inset-0 bg-black/60"
      />
      <ScaleIn className="relative flex max-h-[90vh] w-full max-w-md flex-col overflow-hidden rounded-xl border border-border-subtle bg-surface">
        <div className="flex items-center justify-between border-b border-border-subtle px-6 py-4">
          <div>
            <h2 className="font-display text-2xl tracking-tight">Track order</h2>
            <p className="mt-0.5 text-[13px] text-muted">{business.name}</p>
          </div>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-md text-muted transition hover:bg-surface-elevated hover:text-foreground"
            aria-label="Close order tracker"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="overflow-y-auto px-6 py-6">
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="mb-1.5 block text-[12px] font-medium text-muted-strong">
                Order number
              </label>
              <input
                required
                value={orderNumber}
                onChange={(e) => setOrderNumber(e.target.value)}
                placeholder="#12345"
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
            <button
              type="submit"
              disabled={loading}
              className="flex w-full items-center justify-center gap-2 rounded-md bg-accent py-3 text-[14px] font-semibold text-background transition hover:opacity-90 disabled:opacity-50"
            >
              {loading ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Searching…
                </>
              ) : (
                <>
                  <Search className="h-4 w-4" />
                  Track order
                </>
              )}
            </button>
          </form>

          <AnimatePresence>
            {error && (
              <motion.p
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="mt-4 rounded-md border border-border-subtle bg-surface-elevated px-3.5 py-2.5 text-[13px]"
              >
                {error}
              </motion.p>
            )}

            {order && status && (
              <motion.div
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                className="mt-6 rounded-lg border border-border-subtle bg-surface-elevated p-5"
              >
                <div className="flex items-center justify-between border-b border-border-subtle pb-4">
                  <div>
                    <p className="text-[11px] uppercase tracking-[0.14em] text-muted">
                      Order #{order.orderNumber}
                    </p>
                    <p className="mt-1 font-display text-2xl tracking-tight">
                      {status.label}
                    </p>
                  </div>
                  <div className="flex h-12 w-12 items-center justify-center rounded-full bg-background ring-1 ring-border-subtle">
                    {status.icon}
                  </div>
                </div>

                <ul className="mt-4 space-y-2">
                  {order.items.map((item, idx) => (
                    <li
                      key={idx}
                      className="flex items-center justify-between text-[13px]"
                    >
                      <span className="truncate pr-3 text-muted-strong">
                        {item.quantity}× {item.productName}
                      </span>
                      <span className="shrink-0 tabular-nums">
                        {formatPrice(item.lineTotal, currency, currencyCode)}
                      </span>
                    </li>
                  ))}
                </ul>

                <div className="mt-4 flex items-center justify-between border-t border-border-subtle pt-4">
                  <span className="text-[13px] text-muted">Total</span>
                  <span className="text-lg font-semibold tabular-nums text-accent">
                    {formatPrice(order.subtotal, currency, currencyCode)}
                  </span>
                </div>

                {order.deliveryAddress && (
                  <p className="mt-3 text-[12px] text-muted">
                    Deliver to: {order.deliveryAddress}
                  </p>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </ScaleIn>
    </div>
  );
}
