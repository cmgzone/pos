"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { X, Search, Package, Loader2, Truck, CheckCircle, Clock } from "lucide-react";
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

const statusIcons: Record<string, React.ReactNode> = {
  pending: <Clock className="h-5 w-5 text-amber-400" />,
  processing: <Package className="h-5 w-5 text-blue-400" />,
  ready: <CheckCircle className="h-5 w-5 text-emerald-400" />,
  delivered: <Truck className="h-5 w-5 text-accent" />,
  cancelled: <X className="h-5 w-5 text-red-400" />,
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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        onClick={onClose}
        className="absolute inset-0 bg-black/70 backdrop-blur-sm"
      />
      <ScaleIn className="relative w-full max-w-md max-h-[90vh] overflow-y-auto rounded-3xl bg-surface ring-1 ring-white/10">
        <button
          onClick={onClose}
          className="absolute right-4 top-4 z-10 flex h-8 w-8 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-white/10 transition hover:bg-white/10"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="p-6 sm:p-8">
          <h2 className="text-2xl font-bold tracking-tight">Track order</h2>
          <p className="mt-1 text-sm text-muted">
            Enter your order number and phone
          </p>

          <form onSubmit={handleSubmit} className="mt-6 space-y-4">
            <div>
              <label className="mb-1 block text-xs font-medium uppercase tracking-wider text-muted">
                Order number
              </label>
              <input
                required
                value={orderNumber}
                onChange={(e) => setOrderNumber(e.target.value)}
                placeholder="#12345"
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
            <button
              type="submit"
              disabled={loading}
              className="flex w-full items-center justify-center gap-2 rounded-full bg-accent py-3 text-sm font-semibold text-background transition hover:opacity-90 disabled:opacity-50"
            >
              {loading ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Searching...
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
                initial={{ opacity: 0, y: 8 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }}
                className="mt-4 rounded-xl bg-red-500/10 px-4 py-2 text-sm text-red-300"
              >
                {error}
              </motion.p>
            )}

            {order && (
              <motion.div
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                className="mt-6 rounded-2xl bg-surface-elevated p-5 ring-1 ring-white/[0.06]"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-xs text-muted">Order #{order.orderNumber}</p>
                    <p className="mt-1 text-lg font-semibold capitalize">
                      {order.status}
                    </p>
                  </div>
                  <div className="flex h-12 w-12 items-center justify-center rounded-full bg-surface">
                    {statusIcons[order.status] || statusIcons.pending}
                  </div>
                </div>

                <div className="mt-4 space-y-2">
                  {order.items.map((item, idx) => (
                    <div
                      key={idx}
                      className="flex items-center justify-between text-sm"
                    >
                      <span className="text-muted">
                        {item.quantity}× {item.productName}
                      </span>
                      <span className="font-medium">
                        {formatPrice(item.lineTotal, currency, currencyCode)}
                      </span>
                    </div>
                  ))}
                </div>

                <div className="mt-4 flex items-center justify-between border-t border-white/10 pt-4">
                  <span className="text-muted">Total</span>
                  <span className="text-xl font-bold text-accent">
                    {formatPrice(order.subtotal, currency, currencyCode)}
                  </span>
                </div>

                {order.deliveryAddress && (
                  <p className="mt-3 text-xs text-muted">
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
