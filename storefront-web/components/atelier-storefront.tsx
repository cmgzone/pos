"use client";

import { useMemo, useState } from "react";
import {
  ArrowDown,
  ArrowUpRight,
  Clock3,
  Moon,
  Package,
  Search,
  ShoppingBag,
  Sparkles,
  Sun,
} from "lucide-react";
import type {
  Branch,
  Catalog,
  CatalogItem,
  ProductVariant,
  StorefrontAppearance,
} from "@/lib/types";
import { formatPrice, getCatalogItemImages, getInitials } from "@/lib/utils";
import { useStore } from "./store-provider";
import { QuickViewModal } from "./quick-view-modal";

type AtelierMode = "collection" | "single-product" | "portfolio" | "services";

interface AtelierStorefrontProps {
  catalog: Catalog;
  items: CatalogItem[];
  category: string;
  onCategoryChange: (category: string) => void;
  selectedBranch: Branch | null;
  onBranchChange: (branchId: string) => void;
  onTrackOrder: () => void;
  appearance: StorefrontAppearance;
  onAppearanceChange: (appearance: StorefrontAppearance) => void;
}

export function AtelierStorefront({
  catalog,
  items,
  category,
  onCategoryChange,
  selectedBranch,
  onBranchChange,
  onTrackOrder,
  appearance,
  onAppearanceChange,
}: AtelierStorefrontProps) {
  const { addToCart, cartCount, setIsCartOpen } = useStore();
  const [quickViewItem, setQuickViewItem] = useState<CatalogItem | null>(null);
  const [selectedVariant, setSelectedVariant] = useState<ProductVariant>();
  const mode = resolveAtelierMode(catalog);
  const sourceItems = items.length ? items : catalog.products;
  const featuredItem = sourceItems.find((item) => item.isFeatured) || sourceItems[0];
  const media = useMemo(
    () => collectMedia(catalog, featuredItem),
    [catalog, featuredItem],
  );
  const isServiceStore = mode === "services";
  const browseLabel = isServiceStore ? "Explore services" : "Explore collection";

  const scrollToCollection = () => {
    document.getElementById("atelier-collection")?.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });
  };

  const openItem = (item: CatalogItem) => {
    if (item.source === "external_api") {
      if (item.externalCheckoutUrl) {
        window.open(item.externalCheckoutUrl, "_blank", "noopener,noreferrer");
      }
      return;
    }
    if (item.hasVariants && (item.variants || []).length) {
      setSelectedVariant(undefined);
      setQuickViewItem(item);
      return;
    }
    addToCart(item);
  };

  const handleQuickViewAdd = () => {
    if (!quickViewItem) return;
    addToCart(quickViewItem, selectedVariant);
  };

  return (
    <div
      className={`atelier atelier--${mode}`}
      data-piki-component="atelier-storefront"
      data-piki-label={`${catalog.business.name} premium storefront`}
    >
      <header className="atelier-header" data-piki-component="site-header">
        <a className="atelier-brand" href="#top" aria-label={`${catalog.business.name} home`}>
          {catalog.business.brand.logoUrl ? (
            <img src={catalog.business.brand.logoUrl} alt="" className="atelier-brand-mark" />
          ) : (
            <span className="atelier-brand-mark atelier-brand-mark--fallback">
              {getInitials(catalog.business.name)}
            </span>
          )}
          <span className="atelier-brand-name">{catalog.business.name}</span>
        </a>

        <nav className="atelier-nav" aria-label="Storefront navigation">
          <button type="button" onClick={scrollToCollection}>
            {mode === "portfolio" ? "Selected work" : isServiceStore ? "The practice" : "Collection"}
          </button>
          <a href="#atelier-story">About</a>
          {catalog.pages?.slice(0, 1).map((page) => (
            <a key={page.id} href={`/page/${encodeURIComponent(page.slug)}`}>
              {page.label || page.title}
            </a>
          ))}
        </nav>

        <div className="atelier-header-actions">
          {catalog.business.branches.length > 1 && (
            <label className="atelier-branch-select">
              <span className="sr-only">Choose a location</span>
              <select
                value={selectedBranch?.id || catalog.business.selectedBranch.id}
                onChange={(event) => onBranchChange(event.target.value)}
              >
                {catalog.business.branches.map((branch) => (
                  <option key={branch.id} value={branch.id}>{branch.name}</option>
                ))}
              </select>
            </label>
          )}
          <button
            type="button"
            onClick={() => onAppearanceChange(appearance === "light" ? "dark" : "light")}
            className="atelier-icon-button"
            aria-label={appearance === "light" ? "Switch to dark mode" : "Switch to light mode"}
          >
            {appearance === "light" ? <Moon /> : <Sun />}
          </button>
          <button
            type="button"
            onClick={() => setIsCartOpen(true)}
            className="atelier-cart-button"
            aria-label={isServiceStore ? "Open bookings" : "Open shopping bag"}
          >
            <ShoppingBag />
            <span className="atelier-cart-label">{isServiceStore ? "Bookings" : "Bag"}</span>
            {cartCount > 0 && <span className="atelier-cart-count">{cartCount}</span>}
          </button>
        </div>
      </header>

      <main id="top">
        <section className="atelier-hero" data-piki-component="hero">
          <div className="atelier-hero-copy">
            <p className="atelier-kicker">
              <span />
              {heroEyebrow(catalog, mode)}
            </p>
            <h1>{heroTitle(catalog, featuredItem, mode)}</h1>
            <p className="atelier-hero-intro">
              {heroDescription(catalog, mode)}
            </p>
            <div className="atelier-hero-actions">
              <button type="button" className="atelier-primary-button" onClick={scrollToCollection}>
                {mode === "single-product" && featuredItem
                  ? featuredItem.source === "external_api" ? "View product" : "Meet the object"
                  : browseLabel}
                <ArrowDown />
              </button>
              {catalog.business.whatsappNumber && (
                <a
                  className="atelier-text-button"
                  href={`https://wa.me/${catalog.business.whatsappNumber.replace(/[^\d]/g, "")}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  Start a conversation <ArrowUpRight />
                </a>
              )}
            </div>
            <dl className="atelier-hero-notes">
              <div><dt>01</dt><dd>{isServiceStore ? "Considered care" : "Made to last"}</dd></div>
              <div><dt>02</dt><dd>{isServiceStore ? "Book in moments" : "Live availability"}</dd></div>
              <div><dt>03</dt><dd>{selectedBranch?.name || "Independent store"}</dd></div>
            </dl>
          </div>

          <div className="atelier-hero-media" data-piki-component="hero-media">
            {media[0] ? (
              <img src={media[0]} alt="" className="atelier-hero-image" />
            ) : (
              <div className="atelier-media-fallback">
                <span>{getInitials(catalog.business.name)}</span>
              </div>
            )}
            <div className="atelier-media-index">{mode === "services" ? "Practice / 01" : "Edition / 01"}</div>
            <div className="atelier-media-orbit" aria-hidden="true" />
          </div>
        </section>

        {mode === "single-product" && featuredItem ? (
          <SingleProductFeature
            item={featuredItem}
            catalog={catalog}
            media={media}
            onOpen={() => openItem(featuredItem)}
          />
        ) : mode === "services" ? (
          <ServicePractice
            catalog={catalog}
            items={sourceItems}
            onOpen={openItem}
          />
        ) : mode === "portfolio" ? (
          <PortfolioGrid catalog={catalog} items={sourceItems} onOpen={openItem} />
        ) : (
          <CollectionGrid
            catalog={catalog}
            items={sourceItems}
            category={category}
            onCategoryChange={onCategoryChange}
            onOpen={openItem}
          />
        )}

        <section id="atelier-story" className="atelier-story" data-piki-component="story">
          <div className="atelier-story-label">Our point of view</div>
          <div>
            <p className="atelier-story-copy">
              {catalog.business.brand.description || catalog.business.brand.tagline ||
                "A considered online space for work that deserves more than a grid of products."}
            </p>
            <div className="atelier-story-actions">
              <button type="button" onClick={onTrackOrder}>
                <Search /> {isServiceStore ? "Track a booking" : "Track an order"}
              </button>
              {catalog.business.whatsappNumber && (
                <a
                  href={`https://wa.me/${catalog.business.whatsappNumber.replace(/[^\d]/g, "")}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  Speak with us <ArrowUpRight />
                </a>
              )}
            </div>
          </div>
        </section>
      </main>

      <footer className="atelier-footer" data-piki-component="footer">
        <div>
          <p className="atelier-kicker"><span /> Independent by design</p>
          <p className="atelier-footer-title">{catalog.business.name}</p>
        </div>
        <div className="atelier-footer-meta">
          <span>© {new Date().getFullYear()}</span>
          <span>{selectedBranch?.name || catalog.business.selectedBranch.name}</span>
          <span>Powered by Piki POS</span>
        </div>
      </footer>

      {quickViewItem && (
        <QuickViewModal
          item={quickViewItem}
          currencySymbol={catalog.currencySymbol}
          currencyCode={catalog.currencyCode}
          selectedVariant={selectedVariant}
          onVariantChange={setSelectedVariant}
          onClose={() => setQuickViewItem(null)}
          onAdd={handleQuickViewAdd}
        />
      )}
    </div>
  );
}

function SingleProductFeature({
  item,
  catalog,
  media,
  onOpen,
}: {
  item: CatalogItem;
  catalog: Catalog;
  media: string[];
  onOpen: () => void;
}) {
  const image = media[1] || media[0];
  return (
    <section id="atelier-collection" className="atelier-object" data-piki-component="single-product">
      <div className="atelier-section-heading">
        <p className="atelier-kicker"><span /> The object</p>
        <p>One focus. Every detail considered.</p>
      </div>
      <div className="atelier-object-layout">
        <div className="atelier-object-image">
          {image ? <img src={image} alt={item.name} /> : <Package aria-hidden="true" />}
        </div>
        <div className="atelier-object-detail">
          <p className="atelier-index">01 / {item.category || "Signature piece"}</p>
          <h2>{item.name}</h2>
          <p className="atelier-object-description">
            {item.description || "A focused release, offered with live pricing and availability."}
          </p>
          <div className="atelier-object-buy">
            <span>{formatPrice(item.price, catalog.currencySymbol, catalog.currencyCode)}</span>
            <button type="button" onClick={onOpen}>
              {item.source === "external_api" ? "View product" : "Add to bag"} <ArrowUpRight />
            </button>
          </div>
          <p className="atelier-object-note">{item.hasVariants ? "Options are available in the product view." : "Availability updates directly from the store."}</p>
        </div>
      </div>
    </section>
  );
}

function ServicePractice({
  catalog,
  items,
  onOpen,
}: {
  catalog: Catalog;
  items: CatalogItem[];
  onOpen: (item: CatalogItem) => void;
}) {
  return (
    <section id="atelier-collection" className="atelier-practice" data-piki-component="service-list">
      <div className="atelier-section-heading">
        <p className="atelier-kicker"><span /> The practice</p>
        <p>Clear choices, thoughtful timing, no unnecessary steps.</p>
      </div>
      <div className="atelier-service-list">
        {items.map((item, index) => (
          <article key={item.id} className="atelier-service" data-piki-component="service-card">
            <div className="atelier-service-number">{String(index + 1).padStart(2, "0")}</div>
            <div>
              <h2>{item.name}</h2>
              <p>{item.description || "A tailored session designed around what you need."}</p>
            </div>
            <div className="atelier-service-meta">
              {item.durationMinutes && <span><Clock3 /> {item.durationMinutes} min</span>}
              <strong>{formatPrice(item.price, catalog.currencySymbol, catalog.currencyCode)}</strong>
            </div>
            <button type="button" onClick={() => onOpen(item)} aria-label={`Book ${item.name}`}>
              <ArrowUpRight />
            </button>
          </article>
        ))}
        {!items.length && <EmptyAtelierState label="Services are being prepared." />}
      </div>
    </section>
  );
}

function PortfolioGrid({
  catalog,
  items,
  onOpen,
}: {
  catalog: Catalog;
  items: CatalogItem[];
  onOpen: (item: CatalogItem) => void;
}) {
  return (
    <section id="atelier-collection" className="atelier-portfolio" data-piki-component="portfolio-grid">
      <div className="atelier-section-heading">
        <p className="atelier-kicker"><span /> Selected work</p>
        <p>Objects, editions, and ideas arranged as a living portfolio.</p>
      </div>
      <div className="atelier-portfolio-grid">
        {items.map((item, index) => (
          <AtelierTile
            key={item.id}
            item={item}
            catalog={catalog}
            index={index}
            onOpen={() => onOpen(item)}
          />
        ))}
        {!items.length && <EmptyAtelierState label="Work is being curated." />}
      </div>
    </section>
  );
}

function CollectionGrid({
  catalog,
  items,
  category,
  onCategoryChange,
  onOpen,
}: {
  catalog: Catalog;
  items: CatalogItem[];
  category: string;
  onCategoryChange: (category: string) => void;
  onOpen: (item: CatalogItem) => void;
}) {
  return (
    <section id="atelier-collection" className="atelier-collection" data-piki-component="product-collection">
      <div className="atelier-section-heading atelier-section-heading--split">
        <div>
          <p className="atelier-kicker"><span /> The collection</p>
          <p>Useful things, selected with intention.</p>
        </div>
        {catalog.categories.length > 1 && (
          <div className="atelier-category-rail" aria-label="Product categories">
            <button type="button" data-active={category === "all"} onClick={() => onCategoryChange("all")}>All</button>
            {catalog.categories.map((value) => (
              <button key={value} type="button" data-active={category === value} onClick={() => onCategoryChange(value)}>{value}</button>
            ))}
          </div>
        )}
      </div>
      <div className="atelier-collection-grid">
        {items.map((item, index) => (
          <AtelierTile
            key={item.id}
            item={item}
            catalog={catalog}
            index={index}
            onOpen={() => onOpen(item)}
          />
        ))}
        {!items.length && <EmptyAtelierState label="Nothing in this selection just yet." />}
      </div>
    </section>
  );
}

function AtelierTile({
  item,
  catalog,
  index,
  onOpen,
}: {
  item: CatalogItem;
  catalog: Catalog;
  index: number;
  onOpen: () => void;
}) {
  const image = getCatalogItemImages(item)[0];
  return (
    <article className="atelier-tile" data-piki-component="product-card" data-product-id={item.id}>
      <button type="button" className="atelier-tile-image" onClick={onOpen} aria-label={`View ${item.name}`}>
        {image ? <img src={image} alt={item.name} loading="lazy" /> : <Package aria-hidden="true" />}
        <span className="atelier-tile-index">{String(index + 1).padStart(2, "0")}</span>
      </button>
      <div className="atelier-tile-copy">
        <div>
          <p>{item.category || item.brand || "Edition"}</p>
          <h3>{item.name}</h3>
        </div>
        <div className="atelier-tile-buy">
          <span>{formatPrice(item.price, catalog.currencySymbol, catalog.currencyCode)}</span>
          <button type="button" onClick={onOpen} aria-label={`View ${item.name}`}><ArrowUpRight /></button>
        </div>
      </div>
    </article>
  );
}

function EmptyAtelierState({ label }: { label: string }) {
  return <p className="atelier-empty"><Sparkles /> {label}</p>;
}

function resolveAtelierMode(catalog: Catalog): AtelierMode {
  const pageType = String(catalog.page?.pageType || "").toLowerCase();
  const preset = String(catalog.theme.preset || "").toLowerCase();
  const serviceRatio = catalog.products.length
    ? catalog.products.filter((item) => (item.itemType || item.type) === "service").length / catalog.products.length
    : 0;
  if (catalog.storefront.type === "services" || serviceRatio > 0.5) return "services";
  if (catalog.products.length === 1 || catalog.campaign?.productIds.length === 1) return "single-product";
  if (preset === "portfolio" || pageType.includes("portfolio")) return "portfolio";
  return "collection";
}

function collectMedia(catalog: Catalog, featuredItem?: CatalogItem): string[] {
  const urls = [
    ...(catalog.business.brand.coverUrls || []),
    catalog.business.brand.coverUrl || "",
    ...getCatalogItemImages(featuredItem || ({} as CatalogItem)),
    ...catalog.products.flatMap((item) => getCatalogItemImages(item)).slice(0, 4),
  ];
  return [...new Set(urls.map((url) => url.trim()).filter(Boolean))];
}

function heroEyebrow(catalog: Catalog, mode: AtelierMode) {
  if (mode === "services") return catalog.storefront.label || "Independent practice";
  if (mode === "portfolio") return "Creative portfolio";
  if (mode === "single-product") return "A single considered release";
  return catalog.storefront.label || "Independent collection";
}

function heroTitle(catalog: Catalog, item: CatalogItem | undefined, mode: AtelierMode) {
  if (mode === "single-product" && item) return item.name;
  if (mode === "services") return catalog.storefront.title || `Make time for better ${catalog.business.name}.`;
  if (mode === "portfolio") return catalog.storefront.title || `${catalog.business.name}, in progress.`;
  return catalog.storefront.title || catalog.business.brand.tagline || `${catalog.business.name}, selected with intention.`;
}

function heroDescription(catalog: Catalog, mode: AtelierMode) {
  if (mode === "services") {
    return catalog.storefront.description || catalog.business.brand.description || "Book a more thoughtful kind of service, on your own terms.";
  }
  return catalog.storefront.description || catalog.business.brand.description || "A premium storefront shaped around the work itself, with every detail connected to the counter.";
}
