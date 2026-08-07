"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Check, X } from "lucide-react";
import { signupCustomer } from "@/lib/api";
import { ScaleIn } from "./motion";

interface SignupModalProps {
  businessId: string;
  businessName: string;
  onClose: () => void;
}

const inputClass =
  "h-11 w-full rounded-md border border-border-subtle bg-surface px-3.5 text-[14px] text-foreground placeholder:text-muted focus:border-accent focus:outline-none";

export function SignupModal({
  businessId,
  businessName,
  onClose,
}: SignupModalProps) {
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [consent, setConsent] = useState(true);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await signupCustomer(businessId, {
        name: name.trim(),
        phone: phone.trim(),
        email: email.trim() || undefined,
        marketingOptIn: consent,
      });
      setDone(true);
    } catch (reason) {
      setError(
        reason instanceof Error ? reason.message : "Unable to create your account."
      );
    } finally {
      setBusy(false);
    }
  }

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
              {done ? "Welcome" : "Create an account"}
            </h2>
            <p className="mt-0.5 text-[13px] text-muted">{businessName}</p>
          </div>
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-md text-muted transition hover:bg-surface-elevated hover:text-foreground"
            aria-label="Close sign up"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="overflow-y-auto px-6 py-6">
          <AnimatePresence mode="wait">
            {done ? (
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
                <h3 className="mt-5 text-xl font-semibold">You&apos;re signed up</h3>
                <p className="mt-2 max-w-sm text-[13px] leading-5 text-muted">
                  Thanks {name.trim() || "there"} — your details are now with{" "}
                  {businessName}. You&apos;ll hear about new products and offers, and
                  checking out after this is even faster.
                </p>
                {email.trim() && (
                  <p className="mt-3 max-w-sm text-[13px] leading-5 text-muted">
                    Your account is linked to {email.trim()}. Use it from the
                    Account link to view it anytime.
                  </p>
                )}
                <button
                  onClick={onClose}
                  className="mt-6 h-11 w-full rounded-md bg-accent px-4 text-[14px] font-semibold text-background transition hover:opacity-90"
                >
                  Keep shopping
                </button>
              </motion.div>
            ) : (
              <form key="form" onSubmit={submit} className="space-y-4">
<p className="text-[13px] leading-5 text-muted">
                  Create a customer account so {businessName} can keep you up to
                  date and serve you faster.
                </p>

                <label className="block text-sm font-medium text-foreground">
                  Full name
                  <input
                    required
                    minLength={2}
                    value={name}
                    onChange={(event) => setName(event.target.value)}
                    placeholder="Jane Doe"
                    className={`mt-1.5 ${inputClass}`}
                  />
                </label>

                <label className="block text-sm font-medium text-foreground">
                  Phone number
                  <input
                    required
                    inputMode="tel"
                    value={phone}
                    onChange={(event) => setPhone(event.target.value)}
                    placeholder="0712 345 678"
                    className={`mt-1.5 ${inputClass}`}
                  />
                </label>

                <label className="block text-sm font-medium text-foreground">
                  Email{" "}
                  <span className="font-normal text-muted">(optional)</span>
                  <input
                    type="email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    placeholder="you@example.com"
                    className={`mt-1.5 ${inputClass}`}
                  />
                </label>

                <label className="flex items-start gap-2.5 text-[13px] leading-5 text-muted-strong">
                  <input
                    type="checkbox"
                    checked={consent}
                    onChange={(event) => setConsent(event.target.checked)}
                    className="mt-0.5 h-4 w-4 shrink-0 accent-[var(--accent)]"
                  />
                  <span>
                    I&apos;m happy to receive news, offers and updates from{" "}
                    {businessName} on my phone or email.
                  </span>
                </label>

                {error && (
                  <p className="rounded-lg border border-red-400/30 bg-red-400/10 px-3 py-2 text-sm text-red-200">
                    {error}
                  </p>
                )}

                <button
                  disabled={busy}
                  className="h-11 w-full rounded-md bg-accent px-4 text-[14px] font-semibold text-background transition hover:opacity-90 disabled:opacity-60"
                >
                  {busy ? "Creating account…" : "Create account"}
                </button>
              </form>
            )}
          </AnimatePresence>
        </div>
      </ScaleIn>
    </div>
  );
}