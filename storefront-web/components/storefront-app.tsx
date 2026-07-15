"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { StoreProvider, useStore } from "./store-provider";
import { SiteHeader } from "./site-header";
import {
  StorefrontAnnouncement,
  StorefrontSections,
} from "./storefront-sections";
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
import type {
  BusinessBrand,
  StorefrontSectionAction,
  StorefrontTheme,
  StorefrontType,
} from "@/lib/types";

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
  const [category, setCategory] = useState("all");
  const [sortBy, setSortBy] = useState("featured");
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
        applyStorefrontStyles(
          data.business.brand,
          data.storefront.type,
          data.theme,
        );
      } catch (loadError) {
        setCatalog(null);
        setError(
          loadError instanceof Error ? loadError.message : "Failed to load store",
        );
      }
    },
    [setCatalog, setSelectedBranch],
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
      const branch = catalog.business.branches.find(
        (candidate) => candidate.id === branchId,
      );
      if (!branch) return;
      setSelectedBranch(branch);
      loadCatalog(
        catalog.business.id,
        branchId,
        catalog.storefront.type,
        getPreviewTokenFromQuery(),
      );
    },
    [catalog, loadCatalog, setSelectedBranch],
  );

  const filteredItems = useMemo(() => {
    if (!catalog) return [];
    let items = [...catalog.products];
    const query = search.trim().toLowerCase();
    if (query) {
      items = items.filter(
        (item) =>
          item.name.toLowerCase().includes(query) ||
          item.description?.toLowerCase().includes(query) ||
          item.category?.toLowerCase().includes(query) ||
          item.brand?.toLowerCase().includes(query),
      );
    }
    if (category !== "all") {
      items = items.filter((item) => item.category === category);
    }
    switch (sortBy) {
      case "priceAsc":
        items.sort((first, second) => first.price - second.price);
        break;
      case "priceDesc":
        items.sort((first, second) => second.price - first.price);
        break;
      case "name":
        items.sort((first, second) => first.name.localeCompare(second.name));
        break;
      default:
        items.sort((first, second) => {
          if (first.isFeatured && !second.isFeatured) return -1;
          if (!first.isFeatured && second.isFeatured) return 1;
          return (second.soldQty || 0) - (first.soldQty || 0);
        });
    }
    return items;
  }, [catalog, search, category, sortBy]);

  const handleSectionAction = (action: StorefrontSectionAction) => {
    if (action === "catalog") {
      document.getElementById("catalog")?.scrollIntoView({ behavior: "smooth" });
      return;
    }
    if (action === "trackOrder") {
      setShowTracker(true);
      return;
    }
    if (action === "whatsapp" && catalog?.business.whatsappNumber) {
      const phone = catalog.business.whatsappNumber.replace(/[^\d]/g, "");
      if (phone) {
        window.open(`https://wa.me/${phone}`, "_blank", "noopener,noreferrer");
      }
    }
  };

  if (error) return <ErrorState message={error} />;

  const isLoading = catalog === null;
  const isSearching = Boolean(search) || category !== "all";

  return (
    <>
      {catalog?.preview && (
        <div className="sticky top-0 z-[80] border-b border-amber-300/30 bg-amber-300 px-4 py-2 text-center text-[12px] font-bold text-black shadow-sm">
          Draft website preview · Updates automatically · Customers cannot see
          this theme until you publish
        </div>
      )}
      {catalog?.theme.sections
        .filter(
          (section) =>
            section.enabled !== false && section.type === "announcement",
        )
        .map((section) => (
          <StorefrontAnnouncement
            key={section.id}
            section={section}
            onAction={handleSectionAction}
          />
        ))}
      <SiteHeader
        business={catalog?.business}
        storefront={catalog?.storefront}
        onTrackOrder={() => setShowTracker(true)}
        showTracking={catalog?.checkout.showOrderTracking !== false}
      />

      {isLoading || !catalog ? (
        <main className="flex-1 px-4 py-16 sm:px-6 lg:px-10">
          <SkeletonGrid />
        </main>
      ) : (
        <StorefrontSections
          catalog={catalog}
          sections={catalog.theme.sections.filter(
            (section) => section.type !== "announcement",
          )}
          filteredItems={filteredItems}
          isSearching={isSearching}
          search={search}
          onSearchChange={setSearch}
          category={category}
          onCategoryChange={setCategory}
          sortBy={sortBy}
          onSortChange={setSortBy}
          selectedBranch={selectedBranch}
          onBranchChange={handleBranchChange}
          onAction={handleSectionAction}
        />
      )}

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
    inter: "Inter, ui-sans-serif, system-ui, sans-serif",
    modern: '"Avenir Next", "Segoe UI", ui-sans-serif, sans-serif',
    serif: 'Georgia, "Times New Roman", serif',
    rounded: 'Nunito, "Arial Rounded MT Bold", ui-sans-serif, sans-serif',
    system: "ui-sans-serif, system-ui, sans-serif",
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
