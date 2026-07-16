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
import { GeneratedSiteFrame } from "./generated-site-frame";
import {
  getBootstrap,
  getBranchIdFromQuery,
  getPagePreviewTokenFromQuery,
  getPreviewTokenFromQuery,
  getSitePreviewTokenFromQuery,
} from "@/lib/utils";
import {
  campaignSlugFromPath,
  fetchCatalog,
  pageSlugFromPath,
  storefrontTypeFromPath,
} from "@/lib/api";
import type {
  BusinessBrand,
  StorefrontAppearance,
  StorefrontSectionAction,
  StorefrontTheme,
  StorefrontThemeDesign,
  StorefrontType,
} from "@/lib/types";

const APPEARANCE_STORAGE_KEY = "piki-storefront-appearance";

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
  const [appearance, setAppearance] = useState<StorefrontAppearance>("light");

  const loadCatalog = useCallback(
    async (
      businessId: string,
      branchId?: string,
      storefrontType?: StorefrontType,
      previewToken?: string,
      campaignSlug?: string,
      pageSlug?: string,
      pagePreviewToken?: string,
      sitePreviewToken?: string,
    ) => {
      setError(null);
      try {
        const data = await fetchCatalog(
          businessId,
          branchId,
          storefrontType,
          previewToken,
          campaignSlug,
          pageSlug,
          pagePreviewToken,
          sitePreviewToken,
        );
        setCatalog(data);
        setSelectedBranch(data.business.selectedBranch);
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
    const pagePreviewToken = getPagePreviewTokenFromQuery();
    const sitePreviewToken = getSitePreviewTokenFromQuery();
    const businessId = bootstrap.businessId || bootstrap.catalog?.business.id;
    const branchId =
      bootstrap.branchId ||
      bootstrap.catalog?.business.selectedBranch.id ||
      getBranchIdFromQuery();
    const storefrontType =
      bootstrap.catalog?.storefront.type || storefrontTypeFromPath();
    const campaignSlug = bootstrap.catalog?.campaign?.slug || campaignSlugFromPath();
    const pageSlug = bootstrap.catalog?.page?.slug || pageSlugFromPath();

    if (bootstrap.catalog) {
      setCatalog(bootstrap.catalog);
      setSelectedBranch(bootstrap.catalog.business.selectedBranch);
    } else if (!businessId) {
      setError(
        "No store link detected. Visit a catalog URL like /catalog/<businessId>.",
      );
      return;
    } else {
      loadCatalog(businessId, branchId, storefrontType, previewToken, campaignSlug, pageSlug, pagePreviewToken, sitePreviewToken);
    }

    if ((!previewToken && !pagePreviewToken && !sitePreviewToken) || !businessId) return;
    const timer = window.setInterval(() => {
      loadCatalog(businessId, branchId, storefrontType, previewToken, campaignSlug, pageSlug, pagePreviewToken, sitePreviewToken);
    }, 2000);
    return () => window.clearInterval(timer);
  }, [loadCatalog, setCatalog, setSelectedBranch]);

  useEffect(() => {
    const saved = window.localStorage.getItem(APPEARANCE_STORAGE_KEY);
    if (saved === "light" || saved === "dark") {
      setAppearance(saved);
    }
  }, []);

  useEffect(() => {
    if (!catalog) return;
    applyStorefrontStyles(
      catalog.business.brand,
      catalog.storefront.type,
      catalog.theme,
      appearance,
    );
  }, [appearance, catalog]);

  const handleAppearanceChange = (nextAppearance: StorefrontAppearance) => {
    setAppearance(nextAppearance);
    window.localStorage.setItem(APPEARANCE_STORAGE_KEY, nextAppearance);
  };

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
        catalog.campaign?.slug || campaignSlugFromPath(),
        catalog.page?.slug || pageSlugFromPath(),
        getPagePreviewTokenFromQuery(),
        getSitePreviewTokenFromQuery(),
      );
    },
    [catalog, loadCatalog, setSelectedBranch],
  );

  const filteredItems = useMemo(() => {
    if (!catalog) return [];
    const campaignProductIds = new Set(catalog.campaign?.productIds || []);
    let items = catalog.campaign
      ? catalog.products.filter((item) => campaignProductIds.has(item.id))
      : [...catalog.products];
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
      const catalogSection = document.getElementById("catalog");
      if (catalogSection) catalogSection.scrollIntoView({ behavior: "smooth" });
      else window.location.href = "/";
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
  const activeSections = catalog?.page?.sections || catalog?.theme.sections || [];
  const usesGeneratedSite = Boolean(
    catalog?.siteBuild && !catalog?.campaign,
  );

  return (
    <>
      {catalog?.preview && (
        <div className="sticky top-0 z-[80] border-b border-amber-300/30 bg-amber-300 px-4 py-2 text-center text-[12px] font-bold text-black shadow-sm">
          Draft website preview · Updates automatically · Customers cannot see
          this website until you publish
        </div>
      )}
      {!usesGeneratedSite && activeSections
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
      {!usesGeneratedSite && (
        <SiteHeader
          business={catalog?.business}
          storefront={catalog?.storefront}
          onTrackOrder={() => setShowTracker(true)}
          appearance={appearance}
          onAppearanceChange={handleAppearanceChange}
          showTracking={catalog?.checkout.showOrderTracking !== false}
          pages={catalog?.pages || []}
        />
      )}

      {isLoading || !catalog ? (
        <main className="flex-1 px-4 py-16 sm:px-6 lg:px-10">
          <SkeletonGrid />
        </main>
      ) : usesGeneratedSite ? (
        <GeneratedSiteFrame
          catalog={catalog}
          onTrackOrder={() => setShowTracker(true)}
        />
      ) : (
        <StorefrontSections
          catalog={catalog}
          sections={activeSections.filter(
            (section) =>
              section.type !== "announcement" &&
              (!catalog.campaign ||
                section.type === "catalog" ||
                section.type === "contact" ||
                section.type === "benefits"),
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

      {!usesGeneratedSite && (
        <Footer
          business={catalog?.business}
          onTrackOrder={() => setShowTracker(true)}
          showTracking={catalog?.checkout.showOrderTracking !== false}
          pages={catalog?.pages || []}
        />
      )}
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
  appearance: StorefrontAppearance = "light",
) {
  const root = document.documentElement;
  const design = theme?.design;
  root.dataset.storefrontType = storefrontType;
  root.dataset.themeHero = design?.heroStyle || "cover";
  root.dataset.themeCard = design?.cardStyle || "bordered";
  root.dataset.themeImage = design?.imageRatio || "portrait";
  root.dataset.themeDensity = design?.density || "comfortable";
  root.dataset.themeCorner = design?.cornerStyle || "soft";
  root.dataset.themeHeadingScale = design?.headingScale || "balanced";
  root.dataset.themeContentWidth = design?.contentWidth || "standard";
  root.dataset.themeSectionSpacing = design?.sectionSpacing || "standard";
  root.dataset.themeButton = design?.buttonStyle || "solid";
  root.dataset.themeNavigation = design?.navigationStyle || "minimal";
  root.dataset.themeIcon = design?.iconStyle || "plain";
  root.dataset.themeMotion = design?.motionStyle || "subtle";
  root.dataset.themeProductColumns = String(design?.productColumns || 4);
  root.dataset.appearance = appearance;
  root.style.colorScheme = appearance;

  const palette = resolveAppearancePalette(design, storefrontType, appearance);
  const accent = design?.accentColor || brand?.primaryColor || "#d14343";
  const colors: Record<string, string | undefined> = {
    "--background": palette.background,
    "--foreground": palette.foreground,
    "--accent": accent,
    "--accent-contrast": readableTextOn(accent),
    "--muted": palette.muted,
    "--muted-strong": palette.mutedStrong,
    "--surface": palette.surface,
    "--surface-elevated": palette.surfaceElevated,
    "--border": palette.border,
    "--border-strong": palette.borderStrong,
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
    poppins: 'var(--font-poppins), "Segoe UI", sans-serif',
    playfair: 'var(--font-playfair), Georgia, serif',
    montserrat: 'var(--font-montserrat), "Segoe UI", sans-serif',
    nunito: 'var(--font-nunito), "Arial Rounded MT Bold", sans-serif',
    oswald: 'var(--font-oswald), Impact, sans-serif',
    merriweather: 'var(--font-merriweather), Georgia, serif',
  };
  const bodyFont = design ? fontFamilies[design.bodyFontFamily || design.fontFamily] : undefined;
  const headingFont = design ? fontFamilies[design.headingFontFamily || design.fontFamily] : undefined;
  if (bodyFont || headingFont) {
    root.style.setProperty("--storefront-font", bodyFont || headingFont || "");
    root.style.setProperty("--storefront-display-font", headingFont || bodyFont || "");
  } else {
    root.style.removeProperty("--storefront-font");
    root.style.removeProperty("--storefront-display-font");
  }
}

interface AppearancePalette {
  background: string;
  foreground: string;
  muted: string;
  mutedStrong: string;
  surface: string;
  surfaceElevated: string;
  border: string;
  borderStrong: string;
}

function resolveAppearancePalette(
  design: StorefrontThemeDesign | undefined,
  storefrontType: StorefrontType,
  appearance: StorefrontAppearance,
): AppearancePalette {
  const designIsLight = colorLuminance(design?.backgroundColor) > 0.55;
  if (design && designIsLight === (appearance === "light")) {
    return {
      background: design.backgroundColor,
      foreground: design.textColor,
      muted: design.mutedColor,
      mutedStrong: design.mutedColor,
      surface: design.surfaceColor,
      surfaceElevated: design.surfaceElevatedColor,
      border: design.borderColor,
      borderStrong: design.borderColor,
    };
  }

  if (appearance === "dark") {
    if (storefrontType === "services") {
      return {
        background: "#091820",
        foreground: "#e9f7f5",
        muted: "#91adaa",
        mutedStrong: "#bed3d0",
        surface: "#0e252d",
        surfaceElevated: "#13313a",
        border: "rgba(233, 247, 245, 0.10)",
        borderStrong: "rgba(233, 247, 245, 0.19)",
      };
    }
    if (storefrontType === "restaurant") {
      return {
        background: "#1b0d09",
        foreground: "#fff4e8",
        muted: "#c6a99a",
        mutedStrong: "#e2c7b8",
        surface: "#27130d",
        surfaceElevated: "#351a11",
        border: "rgba(255, 244, 232, 0.10)",
        borderStrong: "rgba(255, 244, 232, 0.20)",
      };
    }
    return {
      background: "#100f0d",
      foreground: "#f5f3ef",
      muted: "#9a958c",
      mutedStrong: "#c0bbb1",
      surface: "#181614",
      surfaceElevated: "#211f1c",
      border: "rgba(245, 243, 239, 0.09)",
      borderStrong: "rgba(245, 243, 239, 0.18)",
    };
  }

  if (storefrontType === "services") {
    return {
      background: "#f3f8f7",
      foreground: "#102523",
      muted: "#647c79",
      mutedStrong: "#3f5d59",
      surface: "#ffffff",
      surfaceElevated: "#e7f1ef",
      border: "rgba(16, 37, 35, 0.10)",
      borderStrong: "rgba(16, 37, 35, 0.19)",
    };
  }
  if (storefrontType === "restaurant") {
    return {
      background: "#fff8f2",
      foreground: "#2b1912",
      muted: "#816a5f",
      mutedStrong: "#60483e",
      surface: "#ffffff",
      surfaceElevated: "#f5e9df",
      border: "rgba(43, 25, 18, 0.10)",
      borderStrong: "rgba(43, 25, 18, 0.19)",
    };
  }
  return {
    background: "#f8f7f3",
    foreground: "#191916",
    muted: "#77736b",
    mutedStrong: "#545149",
    surface: "#ffffff",
    surfaceElevated: "#efede7",
    border: "rgba(25, 25, 22, 0.10)",
    borderStrong: "rgba(25, 25, 22, 0.19)",
  };
}

function colorLuminance(color?: string): number {
  const match = color?.trim().match(/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i);
  if (!match) return 0;
  const normalized =
    match[1].length === 3
      ? match[1]
          .split("")
          .map((character) => `${character}${character}`)
          .join("")
      : match[1].slice(0, 6);
  const value = Number.parseInt(normalized, 16);
  const red = (value >> 16) & 255;
  const green = (value >> 8) & 255;
  const blue = value & 255;
  return (red * 0.2126 + green * 0.7152 + blue * 0.0722) / 255;
}

function readableTextOn(color: string): string {
  return colorLuminance(color) > 0.57 ? "#151511" : "#ffffff";
}

export function StorefrontApp() {
  return (
    <StoreProvider>
      <StorefrontInner />
    </StoreProvider>
  );
}
