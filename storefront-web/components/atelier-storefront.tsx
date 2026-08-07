"use client";

import { useEffect, useMemo, useState } from "react";
import {
  ArrowDown,
  ArrowUpRight,
  CircleUserRound,
  Clock3,
  Moon,
  Package,
  Search,
  ShoppingBag,
  Sparkles,
  Sun,
  X,
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
import { SignupModal } from "./signup-modal";

type AtelierMode = "collection" | "single-product" | "portfolio" | "services";

interface AtelierStorefrontProps {
  catalog: Catalog;
  items: CatalogItem[];
  category: string;
  onCategoryChange: (category: string) => void;
  search: string;
  onSearchChange: (search: string) => void;
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
  search,
  onSearchChange,
  selectedBranch,
  onBranchChange,
  onTrackOrder,
  appearance,
  onAppearanceChange,
}: AtelierStorefrontProps) {
  const { addToCart, cartCount, setIsCartOpen } = useStore();
  const [quickViewItem, setQuickViewItem] = useState<CatalogItem | null>(null);
  const [selectedVariant, setSelectedVariant] = useState<ProductVariant>();
  const [showSignup, setShowSignup] = useState(false);
  const [sortBy, setSortBy] = useState("featured");
  const mode = resolveAtelierMode(catalog);
  // Keep the hero and grid in sync with the active category and search query.
  // Falling back to the full catalog here made an empty search look as though it
  // still had results.
  const sourceItems = useMemo(
    () => sortCatalogItems(items, sortBy),
    [items, sortBy],
  );
  const featuredItem = sourceItems.find((item) => item.isFeatured) || sourceItems[0];
  const media = useMemo(
    () => collectMedia(catalog, featuredItem, sourceItems),
    [catalog, featuredItem, sourceItems],
  );
  const isServiceStore = mode === "services";
  const browseLabel = isServiceStore ? "Explore services" : "Shop the store";

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
          <a
            href={`/portal?businessId=${encodeURIComponent(catalog.business.id)}`}
            className="atelier-account-link"
            aria-label="Open my customer account"
          >
            <CircleUserRound />
            <span>Account</span>
          </a>
          <button
            type="button"
            onClick={() => setShowSignup(true)}
            className="atelier-signup-button"
            aria-label="Create a customer account"
          >
            Sign up
          </button>
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
              <div><dt>01</dt><dd>{isServiceStore ? "Considered care" : "Live stock"}</dd></div>
              <div><dt>02</dt><dd>{isServiceStore ? "Book in moments" : "Simple checkout"}</dd></div>
              <div><dt>03</dt><dd>{selectedBranch?.name || "Local support"}</dd></div>
            </dl>
          </div>

          <div className="atelier-hero-media" data-piki-component="hero-media">
            <div className="atelier-hero-stage">
              <div className="atelier-hero-stage-meta">
                <span>{isServiceStore ? "Now booking" : "Featured today"}</span>
                <span>{sourceItems.length} {isServiceStore ? "options" : "items"}</span>
              </div>
              {media[0] ? (
                <img src={media[0]} alt="" className="atelier-hero-image" />
              ) : (
                <div className="atelier-media-fallback">
                  <span>{getInitials(catalog.business.name)}</span>
                </div>
              )}
              <p className="atelier-hero-product-name">
                {featuredItem?.name || catalog.business.name}
              </p>
            </div>
            <div className="atelier-hero-caption">
              <span>Curated for everyday use</span>
              <p>{isServiceStore ? "Clear choices. Thoughtful timing." : "Prices, availability, and support in one place."}</p>
            </div>
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
            category={category}
            onCategoryChange={onCategoryChange}
            search={search}
            onSearchChange={onSearchChange}
            sortBy={sortBy}
            onSortChange={setSortBy}
            onOpen={openItem}
          />
        ) : mode === "portfolio" ? (
          <PortfolioGrid
            catalog={catalog}
            items={sourceItems}
            category={category}
            onCategoryChange={onCategoryChange}
            search={search}
            onSearchChange={onSearchChange}
            sortBy={sortBy}
            onSortChange={setSortBy}
            onOpen={openItem}
          />
        ) : (
          <CollectionGrid
            catalog={catalog}
            items={sourceItems}
            category={category}
            onCategoryChange={onCategoryChange}
            search={search}
            onSearchChange={onSearchChange}
            sortBy={sortBy}
            onSortChange={setSortBy}
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
          {catalog.business.whatsappNumber && (
            <a
              className="atelier-footer-whatsapp"
              href={`https://wa.me/${catalog.business.whatsappNumber.replace(/[^\d]/g, "")}`}
              target="_blank"
              rel="noreferrer"
            >
              <ArrowUpRight /> Talk to us on WhatsApp
            </a>
          )}
        </div>
        <div className="atelier-footer-actions">
          <button type="button" className="atelier-primary-button" onClick={() => setShowSignup(true)}>
            Sign up for updates <ArrowUpRight />
          </button>
          <a
            className="atelier-text-button"
            href={`/portal?businessId=${encodeURIComponent(catalog.business.id)}`}
          >
            My account <ArrowUpRight />
          </a>
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
      {showSignup && (
        <SignupModal
          businessId={catalog.business.id}
          businessName={catalog.business.name}
          onClose={() => setShowSignup(false)}
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
  category,
  onCategoryChange,
  search,
  onSearchChange,
  onOpen,
  sortBy,
  onSortChange,
}: {
  catalog: Catalog;
  items: CatalogItem[];
  category: string;
  onCategoryChange: (category: string) => void;
  search: string;
  onSearchChange: (search: string) => void;
  onOpen: (item: CatalogItem) => void;
  sortBy: string;
  onSortChange: (sortBy: string) => void;
}) {
  const { visibleItems, hasMore, showMore } = useVisibleItems(items, category, search, 8);
  return (
    <section id="atelier-collection" className="atelier-practice" data-piki-component="service-list">
      <div className="atelier-section-heading">
        <p className="atelier-kicker"><span /> The practice</p>
        <p>Clear choices, thoughtful timing, no unnecessary steps.</p>
      </div>
      <AtelierBrowseControls
        catalog={catalog}
        category={category}
        onCategoryChange={onCategoryChange}
        search={search}
        onSearchChange={onSearchChange}
        sortBy={sortBy}
        onSortChange={onSortChange}
        itemCount={items.length}
        itemLabel="services"
      />
      <div className="atelier-service-list">
        {visibleItems.map((item, index) => (
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
        {!items.length && <EmptyAtelierState label={emptySelectionLabel("Services are being prepared.", search, category)} />}
      </div>
      <LoadMoreButton remaining={items.length - visibleItems.length} hasMore={hasMore} onClick={showMore} />
    </section>
  );
}

function PortfolioGrid({
  catalog,
  items,
  category,
  onCategoryChange,
  search,
  onSearchChange,
  onOpen,
  sortBy,
  onSortChange,
}: {
  catalog: Catalog;
  items: CatalogItem[];
  category: string;
  onCategoryChange: (category: string) => void;
  search: string;
  onSearchChange: (search: string) => void;
  onOpen: (item: CatalogItem) => void;
  sortBy: string;
  onSortChange: (sortBy: string) => void;
}) {
  const { visibleItems, hasMore, showMore } = useVisibleItems(items, category, search, 9);
  return (
    <section id="atelier-collection" className="atelier-portfolio" data-piki-component="portfolio-grid">
      <div className="atelier-section-heading">
        <p className="atelier-kicker"><span /> Selected work</p>
        <p>Objects, editions, and ideas arranged as a living portfolio.</p>
      </div>
      <AtelierBrowseControls
        catalog={catalog}
        category={category}
        onCategoryChange={onCategoryChange}
        search={search}
        onSearchChange={onSearchChange}
        sortBy={sortBy}
        onSortChange={onSortChange}
        itemCount={items.length}
        itemLabel="pieces"
      />
      <div className="atelier-portfolio-grid">
        {visibleItems.map((item, index) => (
          <AtelierTile
            key={item.id}
            item={item}
            catalog={catalog}
            index={index}
            onOpen={() => onOpen(item)}
          />
        ))}
        {!items.length && <EmptyAtelierState label={emptySelectionLabel("Work is being curated.", search, category)} />}
      </div>
      <LoadMoreButton remaining={items.length - visibleItems.length} hasMore={hasMore} onClick={showMore} />
    </section>
  );
}

function CollectionGrid({
  catalog,
  items,
  category,
  onCategoryChange,
  search,
  onSearchChange,
  onOpen,
  sortBy,
  onSortChange,
}: {
  catalog: Catalog;
  items: CatalogItem[];
  category: string;
  onCategoryChange: (category: string) => void;
  search: string;
  onSearchChange: (search: string) => void;
  onOpen: (item: CatalogItem) => void;
  sortBy: string;
  onSortChange: (sortBy: string) => void;
}) {
  const { visibleItems, hasMore, showMore } = useVisibleItems(items, category, search, 12);
  return (
    <section id="atelier-collection" className="atelier-collection" data-piki-component="product-collection">
      <div className="atelier-section-heading atelier-section-heading--split">
        <div>
          <p className="atelier-kicker"><span /> The collection</p>
          <p>Useful things, selected with intention.</p>
        </div>
      </div>
      <AtelierBrowseControls
        catalog={catalog}
        category={category}
        onCategoryChange={onCategoryChange}
        search={search}
        onSearchChange={onSearchChange}
        sortBy={sortBy}
        onSortChange={onSortChange}
        itemCount={items.length}
        itemLabel="items"
      />
      <div className="atelier-collection-grid">
        {visibleItems.map((item, index) => (
          <AtelierTile
            key={item.id}
            item={item}
            catalog={catalog}
            index={index}
            onOpen={() => onOpen(item)}
          />
        ))}
        {!items.length && <EmptyAtelierState label={emptySelectionLabel("Nothing in this selection just yet.", search, category)} />}
      </div>
      <LoadMoreButton remaining={items.length - visibleItems.length} hasMore={hasMore} onClick={showMore} />
    </section>
  );
}

function AtelierBrowseControls({
  catalog,
  category,
  onCategoryChange,
  search,
  onSearchChange,
  sortBy,
  onSortChange,
  itemCount,
  itemLabel,
}: {
  catalog: Catalog;
  category: string;
  onCategoryChange: (category: string) => void;
  search: string;
  onSearchChange: (search: string) => void;
  sortBy: string;
  onSortChange: (sortBy: string) => void;
  itemCount: number;
  itemLabel: string;
}) {
  const categories = Array.from(
    new Set([
      ...catalog.categories,
      ...catalog.products.map((item) => item.category || "").filter(Boolean),
    ]),
  );
  const useSelect = categories.length > 7;

  return (
    <div className="atelier-browse-controls" data-piki-component="catalog-controls">
      <label className="atelier-search-field">
        <Search aria-hidden="true" />
        <input
          type="search"
          value={search}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder={`Search ${itemLabel}`}
          aria-label={`Search ${itemLabel}`}
        />
        {search && (
          <button type="button" onClick={() => onSearchChange("")} aria-label="Clear search">
            <X aria-hidden="true" />
          </button>
        )}
      </label>
      <div className="atelier-browse-category">
        {categories.length > 1 && useSelect ? (
          <label className="atelier-category-select">
            <span>Category</span>
            <select value={category} onChange={(event) => onCategoryChange(event.target.value)}>
              <option value="all">All categories</option>
              {categories.map((value) => <option key={value} value={value}>{value}</option>)}
            </select>
          </label>
        ) : categories.length > 1 ? (
          <div className="atelier-category-rail" aria-label="Product categories">
            <button type="button" data-active={category === "all"} onClick={() => onCategoryChange("all")}>All</button>
            {categories.map((value) => (
              <button key={value} type="button" data-active={category === value} onClick={() => onCategoryChange(value)}>{value}</button>
            ))}
          </div>
        ) : (
          <span className="atelier-browse-all">All {itemLabel}</span>
        )}
        <div className="atelier-sort" aria-label="Sort products">
          <select value={sortBy} onChange={(event) => onSortChange(event.target.value)} aria-label="Sort products">
            <option value="featured">Featured</option>
            <option value="newest">Newest</option>
            <option value="price-asc">Price: Low to high</option>
            <option value="price-desc">Price: High to low</option>
            <option value="name">Name A–Z</option>
          </select>
        </div>
        <span className="atelier-result-count">{itemCount} {itemLabel}</span>
      </div>
    </div>
  );
}

function sortCatalogItems(items: CatalogItem[], sortBy: string): CatalogItem[] {
  const sorted = [...items];
  switch (sortBy) {
    case "newest":
      sorted.sort((first, second) =>
        (second.updatedAt || "").localeCompare(first.updatedAt || ""),
      );
      break;
    case "price-asc":
      sorted.sort((a, b) => a.price - b.price);
      break;
    case "price-desc":
      sorted.sort((a, b) => b.price - a.price);
      break;
    case "name":
      sorted.sort((a, b) => a.name.localeCompare(b.name));
      break;
    default:
      sorted.sort((first, second) => {
        if (first.isFeatured && !second.isFeatured) return -1;
        if (!first.isFeatured && second.isFeatured) return 1;
        return (second.soldQty || 0) - (first.soldQty || 0);
      });
      break;
  }
  return sorted;
}

function useVisibleItems(items: CatalogItem[], category: string, search: string, initialCount: number) {
  const [visibleCount, setVisibleCount] = useState(initialCount);
  useEffect(() => {
    setVisibleCount(initialCount);
  }, [category, initialCount, search]);

  return {
    visibleItems: items.slice(0, visibleCount),
    hasMore: items.length > visibleCount,
    showMore: () => setVisibleCount((count) => count + initialCount),
  };
}

function LoadMoreButton({ remaining, hasMore, onClick }: { remaining: number; hasMore: boolean; onClick: () => void }) {
  if (!hasMore) return null;
  return (
    <div className="atelier-load-more">
      <button type="button" onClick={onClick}>See more <span>({remaining} remaining)</span> <ArrowDown /></button>
    </div>
  );
}

function emptySelectionLabel(fallback: string, search: string, category: string) {
  if (search.trim()) return `No results for “${search.trim()}”. Try another search or category.`;
  if (category !== "all") return `Nothing in ${category} just yet. Choose another category to keep browsing.`;
  return fallback;
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
  const compareAt = item.compareAtPrice != null && item.compareAtPrice > item.price
    ? item.compareAtPrice
    : null;
  const discount = item.discountPercent ||
    (compareAt ? Math.round(((compareAt - item.price) / compareAt) * 100) : 0);
  const soldOut = item.trackStock === true && item.stock <= 0;
  const lowStock = !soldOut && item.trackStock === true && item.stock > 0 && item.stock <= 5;
  return (
    <article
      className={`atelier-tile${soldOut ? " atelier-tile--soldout" : ""}`}
      data-piki-component="product-card"
      data-product-id={item.id}
    >
      <button type="button" className="atelier-tile-image" onClick={onOpen} aria-label={`View ${item.name}`}>
        {image ? <img src={image} alt={item.name} loading="lazy" /> : <Package aria-hidden="true" />}
        <span className="atelier-tile-index">{String(index + 1).padStart(2, "0")}</span>
        {discount > 0 && <span className="atelier-tile-badge">-{discount}%</span>}
        {soldOut && <span className="atelier-tile-badge atelier-tile-badge--soldout">Sold out</span>}
      </button>
      <div className="atelier-tile-copy">
        <div>
          <p>{item.category || item.brand || "Edition"}</p>
          <h3>{item.name}</h3>
        </div>
        <div className="atelier-tile-buy">
          <span className="atelier-tile-price">
            {compareAt && (
              <s className="atelier-tile-oldprice">{formatPrice(compareAt, catalog.currencySymbol, catalog.currencyCode)}</s>
            )}
            {formatPrice(item.price, catalog.currencySymbol, catalog.currencyCode)}
          </span>
          <button
            type="button"
            onClick={onOpen}
            disabled={soldOut}
            aria-label={`View ${item.name}`}
          >
            <ArrowUpRight />
          </button>
        </div>
        {lowStock && <p className="atelier-tile-stock">Only {item.stock} left</p>}
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
  if (catalog.siteBuild?.singleProductId || catalog.campaign?.productIds.length === 1) return "single-product";
  if (preset === "portfolio" || pageType.includes("portfolio")) return "portfolio";
  return "collection";
}

function collectMedia(catalog: Catalog, featuredItem?: CatalogItem, items: CatalogItem[] = catalog.products): string[] {
  const urls = [
    ...getCatalogItemImages(featuredItem || ({} as CatalogItem)),
    ...items.flatMap((item) => getCatalogItemImages(item)).slice(0, 4),
    ...(catalog.business.brand.coverUrls || []),
    catalog.business.brand.coverUrl || "",
  ];
  return [...new Set(urls.map((url) => url.trim()).filter(Boolean))];
}

function heroEyebrow(catalog: Catalog, mode: AtelierMode) {
  if (mode === "services") return catalog.storefront.label || "Independent practice";
  if (mode === "portfolio") return "Creative portfolio";
  if (mode === "single-product") return "A single considered release";
  return `${catalog.business.name} / online store`;
}

function heroTitle(catalog: Catalog, item: CatalogItem | undefined, mode: AtelierMode) {
  if (mode === "single-product" && item) return item.name;
  if (mode === "services") return catalog.storefront.title || `Make time for better ${catalog.business.name}.`;
  if (mode === "portfolio") return catalog.storefront.title || `${catalog.business.name}, in progress.`;
  const title = catalog.storefront.title?.trim();
  const itemName = item?.name?.trim();
  const genericTitles = new Set(["online shop", "store", "catalog", "retail store"]);
  if (
    title &&
    title.toLowerCase() !== itemName?.toLowerCase() &&
    !genericTitles.has(title.toLowerCase())
  ) {
    return title;
  }
  const catalogText = [
    catalog.storefront.label,
    title,
    ...catalog.products.flatMap((product) => [product.name, product.category, product.brand]),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  return /tech|electronic|phone|laptop|audio|headphone|computer|device/.test(catalogText)
    ? "The right tech, right now."
    : "Better things, better chosen.";
}

function heroDescription(catalog: Catalog, mode: AtelierMode) {
  if (mode === "services") {
    return catalog.storefront.description || catalog.business.brand.description || "Book a more thoughtful kind of service, on your own terms.";
  }
  const description = catalog.storefront.description || catalog.business.brand.description;
  if (description && !/^browse products, choose variants, and place an order in seconds\.?$/i.test(description.trim())) {
    return description;
  }
  return "Straightforward shopping with live availability, clear pricing, and support when you need it.";
}
