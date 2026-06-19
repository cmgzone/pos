"use client";

import { CheckCircle, Truck, Shield, MessageCircle } from "lucide-react";
import { FadeIn } from "./motion";

const badges = [
  { icon: CheckCircle, label: "M-Pesa payments" },
  { icon: Truck, label: "Fast delivery" },
  { icon: Shield, label: "KRA eTIMS ready" },
  { icon: MessageCircle, label: "WhatsApp support" },
];

export function TrustBadges() {
  return (
    <FadeIn delay={0.3}>
      <div className="border-b border-white/[0.06]">
        <div className="mx-auto flex flex-wrap items-center justify-center gap-x-8 gap-y-3 px-4 py-5 sm:px-6 lg:px-8 xl:px-12">
          {badges.map(({ icon: Icon, label }) => (
            <div
              key={label}
              className="flex items-center gap-2 text-xs text-muted"
            >
              <Icon className="h-3.5 w-3.5 text-accent/70" />
              {label}
            </div>
          ))}
        </div>
      </div>
    </FadeIn>
  );
}
