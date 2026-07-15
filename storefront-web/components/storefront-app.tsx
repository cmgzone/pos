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
import {
  getBootstrap,
  getBranchIdFromQuery,
  getPreviewTokenFromQuery,
} from "@/lib/utils";
import { fetchCatalog, storefrontTypeFromPath } from "@/lib/api";
import { FadeIn } from "./motion";
import type { BusinessBrand, StorefrontTheme, StorefrontType } from "@/lib/types";

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
    async (
      businessId: string,
      branchId?: string,
      storefrontType?: StorefrontType,
      previewToken?: string,
    ) => {
      setError(null);
      try {
        const data = await fetchCatalog(
          businessId,
          branchId,
          storefrontType,
          previewToken,
        );
        setCatalog(data);
        setSelectedBranch(data.business.selectedBranch);
        applyStorefrontStyles(data.business.brand, data.storefront.type, data.theme);
      } catch (err) {
        setCatalog(null);
        setError(err instanceof Error ? err.message : "Failed to load store");
      }
    },
    [setCatalog, setSelectedBranch]
  );

  useEffect(() => {
    const bootstrap = getBootstrap();
    const previewToken = getPreviewTokenFromQuery();
    const businessId = bootstrap.businessId || bootstrap.catalog?.business.id;
    const branchId =
      bootstrap.branchId ||
      bootstrap.catalog?.business.selectedBranch.id ||
      getBranchIdFromQuery();
    const storefrontType =
      bootstrap.catalog?.storefront.type || storefrontTypeFromPath();

    if (bootstrap.catalog) {
      setCatalog(bootstrap.catalog);
      setSelectedBranch(bootstrap.catalog.business.selectedBranch);
      applyStorefrontStyles(
        bootstrap.catalog.business.brand,
        bootstrap.catalog.storefront.type,
        bootstrap.catalog.theme,
      );
    } else if (!businessId) {
      setError(
        "No store link detected. Visit a catalog URL like /catalog/<businessId>.",
      );
      return;
    } else {
      loadCatalog(businessId, branchId, storefrontType, previewToken);
    }

    if (!previewToken || !businessId) return;
    const timer = window.setInterval(() => {
      loadCatalog(businessId, branchId, storefrontType, previewToken);
    }, 2000);
    return () => window.clearInterval(timer);
  }, [loadCatalog, setCatalog, setSelectedBranch]);

  const handleBranchChange = useCallback(
    (branchId: string) => {
      if (!catalog) return;
      const branch = catalog.business.branches.find((b) => b.id === branchId);
      if (branch) {
        setSelectedBranch(branch);
        loadCatalog(
          catalog.business.id,
          branchId,
          catalog.storefront.type,
          getPreviewTokenFromQuery(),
        );
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
      {catalog?.preview && (
        <div className="sticky top-0 z-[80] border-b border-amber-300/30 bg-amber-300 px-4 py-2 text-center text-[12px] font-bold text-black shadow-sm">
          Draft website preview · Updates automatically · Customers cannot see this theme until you publish
        </div>
      )}
      <SiteHeader
        business={catalog?.business}
        storefront={catalog?.storefront}
        onTrackOrder={() => setShowTracker(true)}
        showTracking={catalog?.checkout.showOrderTracking !== false}
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
        showTracking={catalog?.checkout.showOrderTracking !== false}
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
            checkout={catalog.checkout}
            onClose={() => setShowCheckout(false)}
          />
        )}
        {showTracker && catalog && catalog.checkout.showOrderTracking && (
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
  theme?: StorefrontTheme,
) {
  const root = document.documentElement;
  const design = theme?.design;
  root.dataset.storefrontType = storefrontType;
  root.dataset.themeHero = design?.heroStyle || "cover";
  root.dataset.themeCard = design?.cardStyle || "bordered";
  root.dataset.themeImage = design?.imageRatio || "portrait";
  root.dataset.themeDensity = design?.density || "comfortable";
  root.dataset.themeCorner = design?.cornerStyle || "soft";

  const colors: Record<string, string | undefined> = {
    "--background": design?.backgroundColor,
    "--foreground": design?.textColor,
    "--accent": design?.accentColor || brand?.primaryColor || undefined,
    "--muted": design?.mutedColor,
    "--muted-strong": design?.mutedColor,
    "--surface": design?.surfaceColor,
    "--surface-elevated": design?.surfaceElevatedColor,
    "--border": design?.borderColor,
    "--border-strong": design?.borderColor,
  };
  Object.entries(colors).forEach(([name, value]) => {
    if (value) root.style.setProperty(name, value);
    else root.style.removeProperty(name);
  });

  const fontFamilies: Record<StorefrontTheme["design"]["fontFamily"], string> = {
    inter: 'Inter, ui-sans-serif, system-ui, sans-serif',
    modern: '"Avenir Next", "Segoe UI", ui-sans-serif, sans-serif',
    serif: 'Georgia, "Times New Roman", serif',
    rounded: 'Nunito, "Arial Rounded MT Bold", ui-sans-serif, sans-serif',
    system: 'ui-sans-serif, system-ui, sans-serif',
  };
  const font = design ? fontFamilies[design.fontFamily] : undefined;
  if (font) {
    root.style.setProperty("--storefront-font", font);
    root.style.setProperty("--storefront-display-font", font);
  } else {
    root.style.removeProperty("--storefront-font");
    root.style.removeProperty("--storefront-display-font");
  }
}

export function StorefrontApp() {
  return (
    <StoreProvider>
      <StorefrontInner />
    </StoreProvider>
  );
}
