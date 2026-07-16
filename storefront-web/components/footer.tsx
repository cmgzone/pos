"use client";

import { Search, MessageCircle } from "lucide-react";
import type { Business, StorefrontPageLink } from "@/lib/types";
import { getInitials } from "@/lib/utils";

interface FooterProps {
  business?: Business;
  onTrackOrder: () => void;
  showTracking?: boolean;
  pages?: StorefrontPageLink[];
}

export function Footer({ business, onTrackOrder, showTracking = true, pages = [] }: FooterProps) {
  const year = new Date().getFullYear();
  const brand = business?.brand;
  const logoUrl = brand?.logoUrl;
  const whatsapp = business?.whatsappNumber;

  const scrollToCatalog = () => {
    const catalog = document.getElementById("catalog");
    if (catalog) catalog.scrollIntoView({ behavior: "smooth" });
    else window.location.href = "/";
  };

  return (
    <footer className="mt-auto border-t border-border-subtle">
      <div className="mx-auto max-w-6xl px-4 py-12 sm:px-6 lg:px-10">
        <div className="grid gap-10 sm:grid-cols-2 lg:grid-cols-4">
          <div className="lg:col-span-2">
            <div className="flex items-center gap-3">
              {logoUrl ? (
                <img
                  src={logoUrl}
                  alt={business?.name || "Store"}
                  className="h-9 w-9 rounded-md object-cover ring-1 ring-border-strong"
                />
              ) : (
                <div className="flex h-9 w-9 items-center justify-center rounded-md bg-surface-elevated text-[13px] font-semibold ring-1 ring-border-subtle">
                  {getInitials(business?.name)}
                </div>
              )}
              <span className="text-[15px] font-semibold tracking-tight">
                {business?.name || "Storefront"}
              </span>
            </div>
            {brand?.description && (
              <p className="mt-4 max-w-sm text-[13px] leading-relaxed text-muted">
                {brand.description}
              </p>
            )}
            {business?.selectedBranch?.name && (
              <p className="mt-3 text-[12px] text-muted">
                {business.selectedBranch.name}
              </p>
            )}
          </div>

          <div>
            <h3 className="text-[11px] font-semibold uppercase tracking-[0.16em] text-muted">
              Shop
            </h3>
            <ul className="mt-4 space-y-2.5 text-[13px]">
              <li>
                <button
                  onClick={scrollToCatalog}
                  className="text-muted-strong transition hover:text-foreground"
                >
                  All products
                </button>
              </li>
              {showTracking && (
                <li>
                  <button
                    onClick={onTrackOrder}
                    className="inline-flex items-center gap-1.5 text-muted-strong transition hover:text-foreground"
                  >
                    <Search className="h-3.5 w-3.5" />
                    Track order
                  </button>
                </li>
              )}
              {pages.map((page) => (
                <li key={page.id}>
                  <a
                    href={`/page/${encodeURIComponent(page.slug)}`}
                    className="text-muted-strong transition hover:text-foreground"
                  >
                    {page.label || page.title}
                  </a>
                </li>
              ))}
            </ul>
          </div>

          <div>
            <h3 className="text-[11px] font-semibold uppercase tracking-[0.16em] text-muted">
              Contact
            </h3>
            <ul className="mt-4 space-y-2.5 text-[13px]">
              {whatsapp && (
                <li>
                  <a
                    href={`https://wa.me/${whatsapp.replace(/[^\d]/g, "")}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1.5 text-muted-strong transition hover:text-foreground"
                  >
                    <MessageCircle className="h-3.5 w-3.5" />
                    WhatsApp
                  </a>
                </li>
              )}
              <li className="text-muted">
                Online orders, pickup & delivery.
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-10 flex flex-col items-center justify-between gap-3 border-t border-border-subtle pt-6 text-[12px] text-muted sm:flex-row">
          <p>
            &copy; {year} {business?.name || "Storefront"}.
          </p>
          <p>
            Powered by{" "}
            <span className="font-medium text-muted-strong">Piki POS</span>
          </p>
        </div>
      </div>
    </footer>
  );
}
