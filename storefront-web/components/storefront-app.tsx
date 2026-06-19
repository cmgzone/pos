"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { AnimatePresence } from "framer-motion";
import { Sparkles } from "lucide-react";
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
import { getBootstrap } from "@/lib/utils";
import { fetchCatalog } from "@/lib/api";
import { FadeIn } from "./motion";

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
    async (businessId: string, branchId?: string) => {
      setError(null);
      try {
        const data = await fetchCatalog(businessId, branchId);
        setCatalog(data);
        setSelectedBranch(data.business.selectedBranch);
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
      return;
    }
    if (!bootstrap.businessId) {
      setError(
        "No store link detected. Visit a catalog URL like /catalog/<businessId>."
      );
      return;
    }
    loadCatalog(bootstrap.businessId);
  }, [loadCatalog, setCatalog, setSelectedBranch]);

  const handleBranchChange = useCallback(
    (branchId: string) => {
      if (!catalog) return;
      const branch = catalog.business.branches.find((b) => b.id === branchId);
      if (branch) {
        setSelectedBranch(branch);
        loadCatalog(catalog.business.id, branchId);
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

  return (
    <>
      <SiteHeader
        business={catalog?.business}
        onTrackOrder={() => setShowTracker(true)}
      />

      <Hero
        business={catalog?.business}
        onBrowse={scrollToCatalog}
      />

      <main className="flex-1 w-full space-y-8 px-4 pb-16 pt-8 sm:px-6 lg:px-8 xl:px-12">
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

        {isLoading || !catalog ? (
          <div className="pt-4">
            <SkeletonGrid />
          </div>
        ) : filteredItems.length === 0 ? (
          <div className="py-20 text-center text-muted">
            <p className="text-sm">No items match your search.</p>
            <button
              onClick={() => {
                setSearch("");
                setCategory("all");
              }}
              className="mt-3 text-xs text-accent hover:underline"
            >
              Clear filters
            </button>
          </div>
        ) : (
          <section>
            <FadeIn>
              <div className="mb-6 flex items-center gap-3">
                <div className="flex h-8 w-8 items-center justify-center rounded-xl bg-accent/[0.12] ring-1 ring-accent/20">
                  <Sparkles className="h-4 w-4 text-accent" />
                </div>
                <div>
                  <h2 className="text-base font-semibold tracking-tight">
                    {search || category !== "all"
                      ? "Search results"
                      : "Featured products"}
                  </h2>
                  <p className="text-[12px] text-muted">
                    {filteredItems.length}{" "}
                    {filteredItems.length === 1 ? "item" : "items"}
                  </p>
                </div>
              </div>
            </FadeIn>
            <ProductGrid items={filteredItems} currencySymbol={catalog.currencySymbol} currencyCode={catalog.currencyCode} />
          </section>
        )}
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

export function StorefrontApp() {
  return (
    <StoreProvider>
      <StorefrontInner />
    </StoreProvider>
  );
}
