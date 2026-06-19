"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { AnimatePresence } from "framer-motion";
import { StoreProvider, useStore } from "./store-provider";
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

  if (error) {
    return <ErrorState message={error} />;
  }

  return (
    <>
      <Hero
        business={catalog?.business}
        onTrackOrder={() => setShowTracker(true)}
      />

      <main className="flex-1 w-full px-4 sm:px-6 lg:px-8 xl:px-12 py-8">
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
          <SkeletonGrid />
        ) : filteredItems.length === 0 ? (
          <div className="py-24 text-center text-muted">
            <p className="text-lg">No items match your search.</p>
            <button
              onClick={() => {
                setSearch("");
                setCategory("all");
              }}
              className="mt-4 text-accent hover:underline"
            >
              Clear filters
            </button>
          </div>
        ) : (
          <ProductGrid items={filteredItems} currency={catalog.currencySymbol} />
        )}
      </main>

      <Footer
        business={catalog?.business}
        onTrackOrder={() => setShowTracker(true)}
      />

      <FloatingCart onOpen={() => setIsCartOpen(true)} />

      <CartDrawer
        onCheckout={() => setShowCheckout(true)}
        currency={catalog?.currencySymbol || ""}
      />

      <AnimatePresence>
        {showCheckout && catalog && (
          <CheckoutModal
            business={catalog.business}
            currency={catalog.currencySymbol}
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
