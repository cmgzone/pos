"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AnimatePresence } from "framer-motion";
import { StoreProvider, useStore } from "./store-provider";
import { CartDrawer } from "./cart-drawer";
import { CheckoutModal } from "./checkout-modal";
import { OrderTracker } from "./order-tracker";
import { FloatingCart } from "./floating-cart";
import { SkeletonGrid } from "./skeleton-grid";
import { ErrorState } from "./error-state";
import { AtelierStorefront } from "./atelier-storefront";
import {
  GeneratedSiteFrame,
  type PikiComponentSelection,
} from "./generated-site-frame";
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
  StorefrontTheme,
  StorefrontThemeDesign,
  StorefrontType,
} from "@/lib/types";

const APPEARANCE_STORAGE_KEY = "piki-storefront-appearance";

const INSPECTOR_INTERACTIVE_SELECTOR = [
  "button",
  "a[href]",
  "input",
  "select",
  "textarea",
  "label",
  '[role="button"]',
  '[role="link"]',
  '[role="navigation"]',
].join(",");

const INSPECTOR_CONTENT_SELECTOR = [
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "p",
  "img",
  "picture",
  "svg",
  "li",
  "blockquote",
  "figcaption",
  "article",
  "nav",
  "aside",
  "section",
  "header",
  "footer",
  "main",
  "[data-piki-inspectable]",
  "[data-piki-component]",
  ".theme-product-card",
].join(",");

function inspectorElementFor(target: EventTarget | null): HTMLElement | null {
  if (!(target instanceof Element)) return null;
  if (target.closest("[data-piki-inspector-ignore]")) return null;
  const interactive = target.closest<HTMLElement>(INSPECTOR_INTERACTIVE_SELECTOR);
  const element =
    interactive || target.closest<HTMLElement>(INSPECTOR_CONTENT_SELECTOR);
  if (
    !element ||
    element === document.body ||
    element === document.documentElement ||
    element.tagName === "IFRAME"
  ) {
    return null;
  }
  return element;
}

function compactElementLabel(element: HTMLElement): string {
  const direct =
    element.dataset.pikiLabel ||
    element.getAttribute("aria-label") ||
    element.getAttribute("alt") ||
    element.getAttribute("placeholder") ||
    element.getAttribute("title");
  if (direct?.trim()) return direct.trim().slice(0, 160);
  const ownText = element.textContent?.replace(/\s+/g, " ").trim();
  if (ownText) return ownText.slice(0, 160);
  return inspectorComponentName(element).replaceAll("-", " ");
}

function inspectorComponentName(element: HTMLElement): string {
  if (element.dataset.pikiComponent) return element.dataset.pikiComponent;
  if (element.classList.contains("theme-product-card")) return "product-card";
  const tag = element.tagName.toLowerCase();
  if (/^h[1-6]$/.test(tag)) return "heading";
  if (tag === "p" || tag === "blockquote" || tag === "figcaption") {
    return "text";
  }
  if (tag === "img" || tag === "picture") return "image";
  if (tag === "svg") return "icon";
  if (tag === "a") return "link";
  if (tag === "button" || element.getAttribute("role") === "button") {
    return element.dataset.pikiAction || "button";
  }
  if (["input", "select", "textarea"].includes(tag)) return "form-control";
  if (tag === "li") return "list-item";
  return tag;
}

function inspectorSelectorFor(element: HTMLElement): string {
  if (element.dataset.pikiSectionId) {
    return `[data-piki-section-id="${CSS.escape(element.dataset.pikiSectionId)}"]`;
  }
  if (element.id) return `#${CSS.escape(element.id)}`;
  const parts: string[] = [];
  let current: HTMLElement | null = element;
  while (current && current !== document.body && parts.length < 7) {
    let part = current.tagName.toLowerCase();
    const stableClasses = Array.from(current.classList)
      .filter(
        (name) =>
          !name.startsWith("piki-inspect") &&
          !name.includes(":") &&
          !name.includes("[") &&
          !name.includes("/") &&
          name.length < 70,
      )
      .slice(0, 2);
    if (current.dataset.pikiComponent) {
      part += `[data-piki-component="${CSS.escape(
        current.dataset.pikiComponent,
      )}"]`;
    } else if (stableClasses.length) {
      part += `.${stableClasses.map((name) => CSS.escape(name)).join(".")}`;
    }
    const siblings = current.parentElement
      ? Array.from(current.parentElement.children).filter(
          (item) => item.tagName === current?.tagName,
        )
      : [];
    if (siblings.length > 1) {
      part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
    }
    parts.unshift(part);
    const candidate = parts.join(" > ");
    try {
      if (document.querySelectorAll(candidate).length === 1) return candidate;
    } catch {
      // Continue building a conservative selector from stable DOM details.
    }
    current = current.parentElement;
  }
  return parts.join(" > ");
}

function describeInspectorElement(element: HTMLElement): PikiComponentSelection {
  const scopeElement = element.closest<HTMLElement>(
    "[data-piki-component], [data-piki-section-id], .storefront-section, article, nav, aside, header, footer, main, section",
  );
  const bindingElement = element.closest<HTMLElement>(
    "[data-piki-binding], [data-piki-section-id]",
  );
  const style = window.getComputedStyle(element);
  const rect = element.getBoundingClientRect();
  const hierarchy = Array.from(
    (function* () {
      let current: HTMLElement | null = element;
      let depth = 0;
      while (current && current !== document.body && depth < 6) {
        yield `${inspectorComponentName(current)}:${compactElementLabel(current)}`;
        current = current.parentElement;
        depth += 1;
      }
    })(),
  )
    .reverse()
    .join(" > ")
    .slice(0, 700);
  return {
    component: inspectorComponentName(element),
    binding:
      bindingElement?.dataset.pikiBinding ||
      bindingElement?.dataset.pikiSectionId,
    selector: inspectorSelectorFor(element),
    parentSelector: element.parentElement
      ? inspectorSelectorFor(element.parentElement)
      : undefined,
    label: compactElementLabel(element),
    text: element.textContent?.replace(/\s+/g, " ").trim().slice(0, 500),
    element: element.tagName.toLowerCase(),
    role: element.getAttribute("role") || undefined,
    scope: scopeElement
      ? `${inspectorComponentName(scopeElement)}:${compactElementLabel(scopeElement)}`.slice(
          0,
          220,
        )
      : undefined,
    hierarchy,
    classes: Array.from(element.classList).slice(0, 8).join(" ").slice(0, 500),
    attributes: [
      element.dataset.pikiAction
        ? `action=${element.dataset.pikiAction}`
        : "",
      element.dataset.productId
        ? `productId=${element.dataset.productId}`
        : "",
      element.dataset.pikiSectionId
        ? `sectionId=${element.dataset.pikiSectionId}`
        : "",
      element.getAttribute("type")
        ? `type=${element.getAttribute("type")}`
        : "",
    ]
      .filter(Boolean)
      .join("; "),
    dimensions: `${Math.round(rect.width)} × ${Math.round(rect.height)} px`,
    styles: [
      `display:${style.display}`,
      `position:${style.position}`,
      `font-size:${style.fontSize}`,
      `font-weight:${style.fontWeight}`,
      `text-align:${style.textAlign}`,
      `color:${style.color}`,
      `background:${style.backgroundColor}`,
      style.gap !== "normal" ? `gap:${style.gap}` : "",
      style.gridTemplateColumns !== "none"
        ? `grid-columns:${style.gridTemplateColumns}`
        : "",
    ]
      .filter(Boolean)
      .join("; ")
      .slice(0, 700),
  };
}

function createInspectorOverlay() {
  const box = document.createElement("div");
  box.className = "piki-inspector-box";
  box.dataset.pikiInspectorIgnore = "true";
  const badge = document.createElement("div");
  badge.className = "piki-inspector-badge";
  box.appendChild(badge);
  document.body.appendChild(box);
  return { box, badge };
}

function drawInspectorOverlay(
  overlay: ReturnType<typeof createInspectorOverlay>,
  element: HTMLElement | null,
  selected = false,
) {
  if (!element || !element.isConnected) {
    overlay.box.hidden = true;
    return;
  }
  const rect = element.getBoundingClientRect();
  if (rect.width < 1 || rect.height < 1) {
    overlay.box.hidden = true;
    return;
  }
  overlay.box.hidden = false;
  overlay.box.dataset.selected = String(selected);
  overlay.box.style.left = `${Math.max(0, rect.left)}px`;
  overlay.box.style.top = `${Math.max(0, rect.top)}px`;
  overlay.box.style.width = `${Math.min(rect.width, window.innerWidth - Math.max(0, rect.left))}px`;
  overlay.box.style.height = `${Math.min(rect.height, window.innerHeight - Math.max(0, rect.top))}px`;
  overlay.badge.textContent = `${inspectorComponentName(element).replaceAll("-", " ")} · ${compactElementLabel(element)}`;
}

function StorefrontInner() {
  const {
    catalog,
    setCatalog,
    selectedBranch,
    setSelectedBranch,
    setIsCartOpen,
  } = useStore();
  const [error, setError] = useState<string | null>(null);
  const [category, setCategory] = useState("all");
  const [search, setSearch] = useState("");
  const [showCheckout, setShowCheckout] = useState(false);
  const [showTracker, setShowTracker] = useState(false);
  const [appearance, setAppearance] = useState<StorefrontAppearance>("light");
  const [inspectMode, setInspectMode] = useState(false);

  useEffect(() => {
    setInspectMode(
      new URLSearchParams(window.location.search).get("pikiInspect") === "1",
    );
  }, []);

  useEffect(() => {
    const host = window.chrome?.webview;
    if (!host?.addEventListener) return;
    const onHostMessage = (event: MessageEvent) => {
      let data = event.data;
      if (typeof data === "string") {
        try {
          data = JSON.parse(data);
        } catch {
          return;
        }
      }
      if (
        !data ||
        data.channel !== "piki-storefront-studio" ||
        data.type !== "set-inspector-mode"
      ) {
        return;
      }
      setInspectMode(data.enabled !== false);
    };
    host.addEventListener("message", onHostMessage);
    return () => host.removeEventListener?.("message", onHostMessage);
  }, []);

  const handlePikiComponentSelected = useCallback(
    (selection: PikiComponentSelection) => {
      window.chrome?.webview?.postMessage(JSON.stringify({
        channel: "piki-storefront-studio",
        type: "section-selected",
        selection,
      }));
    },
    [],
  );

  useEffect(() => {
    if (!inspectMode || !catalog) return;
    const root = document.documentElement;
    root.classList.add("piki-inspect-mode");
    const overlay = createInspectorOverlay();
    let hoveredElement: HTMLElement | null = null;
    let selectedElement: HTMLElement | null = null;
    const onPointerOver = (event: PointerEvent) => {
      const element = inspectorElementFor(event.target);
      if (!element) return;
      if (hoveredElement && hoveredElement !== element) {
        delete hoveredElement.dataset.pikiInspectHover;
      }
      hoveredElement = element;
      element.dataset.pikiInspectHover = "true";
      drawInspectorOverlay(overlay, element, element === selectedElement);
    };
    const onPointerOut = (event: PointerEvent) => {
      const element = inspectorElementFor(event.target);
      if (element && element !== selectedElement) {
        delete element.dataset.pikiInspectHover;
      }
      if (hoveredElement === element) hoveredElement = null;
      drawInspectorOverlay(overlay, selectedElement, true);
    };
    const onClick = (event: MouseEvent) => {
      const element = inspectorElementFor(event.target);
      if (!element) return;
      event.preventDefault();
      event.stopImmediatePropagation();
      document
        .querySelectorAll<HTMLElement>("[data-piki-inspect-selected]")
        .forEach((item) => delete item.dataset.pikiInspectSelected);
      element.dataset.pikiInspectSelected = "true";
      selectedElement = element;
      drawInspectorOverlay(overlay, element, true);
      handlePikiComponentSelected(describeInspectorElement(element));
    };
    const redraw = () =>
      drawInspectorOverlay(
        overlay,
        hoveredElement || selectedElement,
        !hoveredElement || hoveredElement === selectedElement,
      );
    document.addEventListener("pointerover", onPointerOver, true);
    document.addEventListener("pointerout", onPointerOut, true);
    document.addEventListener("click", onClick, true);
    window.addEventListener("scroll", redraw, true);
    window.addEventListener("resize", redraw);
    window.chrome?.webview?.postMessage(JSON.stringify({
      channel: "piki-storefront-studio",
      type: "inspector-ready",
    }));
    return () => {
      root.classList.remove("piki-inspect-mode");
      overlay.box.remove();
      document
        .querySelectorAll<HTMLElement>(
          "[data-piki-inspect-hover], [data-piki-inspect-selected]",
        )
        .forEach((item) => {
          delete item.dataset.pikiInspectHover;
          delete item.dataset.pikiInspectSelected;
        });
      document.removeEventListener("pointerover", onPointerOver, true);
      document.removeEventListener("pointerout", onPointerOut, true);
      document.removeEventListener("click", onClick, true);
      window.removeEventListener("scroll", redraw, true);
      window.removeEventListener("resize", redraw);
    };
  }, [catalog, handlePikiComponentSelected, inspectMode]);

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
    if (category !== "all") {
      items = items.filter((item) => item.category === category);
    }
    const query = search.trim().toLocaleLowerCase();
    if (query) {
      items = items.filter((item) =>
        [item.name, item.brand, item.category, item.description].some((value) =>
          value?.toLocaleLowerCase().includes(query),
        ),
      );
    }
    items.sort((first, second) => {
      if (first.isFeatured && !second.isFeatured) return -1;
      if (!first.isFeatured && second.isFeatured) return 1;
      return (second.soldQty || 0) - (first.soldQty || 0);
    });
    return items;
  }, [catalog, category, search]);

  if (error) return <ErrorState message={error} />;

  const isLoading = catalog === null;
  const usesGeneratedSite = Boolean(catalog?.siteBuild);

  return (
    <>
      {catalog?.preview && (
        <div
          data-piki-inspector-ignore
          className="sticky top-0 z-[80] border-b border-amber-300/30 bg-amber-300 px-4 py-2 text-center text-[12px] font-bold text-black shadow-sm"
        >
          Draft website preview · Updates automatically · Customers cannot see
          this website until you publish
        </div>
      )}
      {inspectMode && (
        <div
          data-piki-inspector-ignore
          className="sticky top-0 z-[90] flex items-center justify-center gap-2 border-b border-rose-300 bg-rose-50 px-4 py-2 text-center text-[12px] font-bold text-rose-900 shadow-sm"
        >
          <span aria-hidden="true">✦</span>
          Select any visible element, then tell Piki exactly what to change
        </div>
      )}

      {isLoading || !catalog ? (
        <main className="flex-1 px-4 py-16 sm:px-6 lg:px-10">
          <SkeletonGrid />
        </main>
      ) : usesGeneratedSite ? (
        <GeneratedSiteFrame
          catalog={catalog}
          onTrackOrder={() => setShowTracker(true)}
          inspectMode={inspectMode}
          onComponentSelected={handlePikiComponentSelected}
        />
      ) : (
        <AtelierStorefront
          catalog={catalog}
          items={filteredItems}
          category={category}
          onCategoryChange={setCategory}
          search={search}
          onSearchChange={setSearch}
          selectedBranch={selectedBranch}
          onBranchChange={handleBranchChange}
          onTrackOrder={() => setShowTracker(true)}
          appearance={appearance}
          onAppearanceChange={handleAppearanceChange}
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
