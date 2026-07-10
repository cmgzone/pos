"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { AnimatePresence } from "framer-motion";
import { StoreProvider, useStore } from "./store-provider";
import { SiteHeader } from "./site-header";
import { Hero } from "./hero";
import { CatalogToolbar } from "./catalog-toolbar";
import { ProductGrid } from "./product-grid";
import { CartDrawer } from "./cart-drawer";
import { CheckoutModal } from "./checkout-modal";
import { OrderTracker } from "./order-tracker";
import { Footer } from "./footer";
import { FloatingCart } from "./floating-cart";
import { SkeletonGrid } from "./skeleton-grid";
import { ErrorState } from "./error-state";
import { getBootstrap, getBranchIdFromQuery } from "@/lib/utils";
import { fetchCatalog } from "@/lib/api";
import { FadeIn } from "./motion";
import type { BusinessBrand, StorefrontType } from "@/lib/types";

function StorefrontInner() {
  const {
    catalog,
    setCatalog,
    selectedBranch,
    setSelectedBranch,
    setIsCartOpen,
  } = useStore();
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState<string>("all");
  const [sortBy, setSortBy] = useState<string>("featured");
  const [showCheckout, setShowCheckout] = useState(false);
  const [showTracker, setShowTracker] = useState(false);

  const loadCatalog = useCallback(
    async (businessId: string, branchId?: string, storefrontType?: StorefrontType) => {
      setError(null);
      try {
        const data = await fetchCatalog(businessId, branchId, storefrontType);
        setCatalog(data);
        setSelectedBranch(data.business.selectedBranch);
        applyStorefrontStyles(data.business.brand, data.storefront.type);
      } catch (err) {
        setCatalog(null);
        setError(err instanceof Error ? err.message : "Failed to load store");
      }
    },
    [setCatalog, setSelectedBranch]
  );

  useEffect(() => {
    const bootstrap = getBootstrap();
    if (bootstrap.catalog) {
      setCatalog(bootstrap.catalog);
      setSelectedBranch(bootstrap.catalog.business.selectedBranch);
      applyStorefrontStyles(
        bootstrap.catalog.business.brand,
        bootstrap.catalog.storefront.type,
      );
      return;
    }
    if (!bootstrap.businessId) {
      setError(
        "No store link detected. Visit a catalog URL like /catalog/<businessId>."
      );
      return;
    }
    loadCatalog(
      bootstrap.businessId,
      bootstrap.branchId || getBranchIdFromQuery(),
      bootstrap.catalog?.storefront?.type,
    );
  }, [loadCatalog, setCatalog, setSelectedBranch]);

  const handleBranchChange = useCallback(
    (branchId: string) => {
      if (!catalog) return;
      const branch = catalog.business.branches.find((b) => b.id === branchId);
      if (branch) {
        setSelectedBranch(branch);
        loadCatalog(catalog.business.id, branchId, catalog.storefront.type);
      }
    },
    [catalog, loadCatalog, setSelectedBranch]
  );

  const filteredItems = useMemo(() => {
    if (!catalog) return [];
    let items = [...catalog.products];

    const q = search.trim().toLowerCase();
    if (q) {
      items = items.filter(
        (item) =>
          item.name.toLowerCase().includes(q) ||
          (item.description && item.description.toLowerCase().includes(q)) ||
          (item.category && item.category.toLowerCase().includes(q)) ||
          (item.brand && item.brand.toLowerCase().includes(q))
      );
    }

    if (category !== "all") {
      items = items.filter((item) => item.category === category);
    }

    switch (sortBy) {
      case "priceAsc":
        items.sort((a, b) => a.price - b.price);
        break;
      case "priceDesc":
        items.sort((a, b) => b.price - a.price);
        break;
      case "name":
        items.sort((a, b) => a.name.localeCompare(b.name));
        break;
      case "featured":
      default:
        items.sort((a, b) => {
          if (a.isFeatured && !b.isFeatured) return -1;
          if (!a.isFeatured && b.isFeatured) return 1;
          return (b.soldQty || 0) - (a.soldQty || 0);
        });
    }

    return items;
  }, [catalog, search, category, sortBy]);

  const isLoading = catalog === null && error === null;

  const scrollToCatalog = () => {
    document.getElementById("catalog")?.scrollIntoView({ behavior: "smooth" });
  };

  if (error) {
    return <ErrorState message={error} />;
  }

  const isSearching = Boolean(search) || category !== "all";

  return (
    <>
      <SiteHeader
        business={catalog?.business}
        storefront={catalog?.storefront}
        onTrackOrder={() => setShowTracker(true)}
      />

      <Hero
        business={catalog?.business}
        storefront={catalog?.storefront}
        onBrowse={scrollToCatalog}
      />

      <main className="flex-1 w-full px-4 pb-20 pt-10 sm:px-6 lg:px-10">
        <CatalogToolbar
          categories={catalog?.categories || []}
          activeCategory={category}
          onCategoryChange={setCategory}
          search={search}
          onSearchChange={setSearch}
          sortBy={sortBy}
          onSortChange={setSortBy}
          branches={catalog?.business.branches || []}
          selectedBranch={selectedBranch}
          onBranchChange={handleBranchChange}
        />

        <div className="mt-10">
          {isLoading || !catalog ? (
            <SkeletonGrid />
          ) : filteredItems.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-24 text-center">
              {catalog.products.length === 0 && !isSearching ? (
                <>
                  <p className="font-display text-2xl tracking-tight">
                    {catalog.storefront.type === "services"
                      ? "No services published for this branch yet"
                      : catalog.storefront.type === "restaurant"
                        ? "No menu items published for this branch yet"
                        : "No products published for this branch yet"}
                  </p>
                  <p className="mt-2 text-[13px] text-muted">
                    {selectedBranch?.name
                      ? `Switch to another branch or publish products for ${selectedBranch.name}.`
                      : "Publish products to see them in this store."}
                  </p>
                </>
              ) : (
                <>
                  <p className="font-display text-2xl tracking-tight">
                    No items match your search
                  </p>
                  <p className="mt-2 text-[13px] text-muted">
                    Try a different keyword or clear your filters.
                  </p>
                  <button
                    onClick={() => {
                      setSearch("");
                      setCategory("all");
                    }}
                    className="mt-5 rounded-md border border-border-subtle bg-surface-elevated px-4 py-2 text-[13px] font-semibold transition hover:border-accent hover:bg-accent hover:text-background"
                  >
                    Clear filters
                  </button>
                </>
              )}
            </div>
          ) : (
            <section>
              <FadeIn>
                <div className="mb-6 flex items-end justify-between gap-4 border-b border-border-subtle pb-4">
                  <div>
                    <p className="text-[11px] font-medium uppercase tracking-[0.16em] text-muted">
                      {isSearching ? "Results" : catalog.storefront.type === "services" ? "Services" : catalog.storefront.type === "restaurant" ? "Today’s menu" : "Collection"}
                    </p>
                    <h2 className="mt-1.5 font-display text-3xl tracking-tight sm:text-4xl">
                      {isSearching
                        ? "Search results"
                        : catalog.storefront.type === "services"
                          ? "Choose a service"
                          : catalog.storefront.type === "restaurant"
                            ? "Order from the menu"
                            : "Browse the store"}
                    </h2>
                  </div>
                  <p className="hidden text-[13px] text-muted sm:block">
                    {filteredItems.length}{" "}
                    {filteredItems.length === 1 ? "item" : "items"}
                  </p>
                </div>
              </FadeIn>
              <ProductGrid
                items={filteredItems}
                currencySymbol={catalog.currencySymbol}
                currencyCode={catalog.currencyCode}
                storefrontType={catalog.storefront.type}
              />
            </section>
          )}
        </div>
      </main>

      <Footer
        business={catalog?.business}
        onTrackOrder={() => setShowTracker(true)}
      />

      <FloatingCart onOpen={() => setIsCartOpen(true)} />

      <CartDrawer
        onCheckout={() => setShowCheckout(true)}
        currencySymbol={catalog?.currencySymbol || ""}
        currencyCode={catalog?.currencyCode || ""}
      />

      <AnimatePresence>
        {showCheckout && catalog && (
          <CheckoutModal
            business={catalog.business}
            currencySymbol={catalog.currencySymbol}
            currencyCode={catalog.currencyCode}
            storefrontType={catalog.storefront.type}
            onClose={() => setShowCheckout(false)}
          />
        )}
        {showTracker && catalog && (
          <OrderTracker
            business={catalog.business}
            currency={catalog.currencySymbol}
            currencyCode={catalog.currencyCode}
            onClose={() => setShowTracker(false)}
          />
        )}
      </AnimatePresence>
    </>
  );
}

function applyStorefrontStyles(
  brand?: BusinessBrand,
  storefrontType: StorefrontType = "retail",
) {
  const root = document.documentElement;
  root.dataset.storefrontType = storefrontType;
  if (brand?.primaryColor) {
    root.style.setProperty("--accent", brand.primaryColor);
  } else {
    root.style.removeProperty("--accent");
  }
}

export function StorefrontApp() {
  return (
    <StoreProvider>
      <StorefrontInner />
    </StoreProvider>
  );
}
