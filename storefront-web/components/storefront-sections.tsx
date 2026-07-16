"use client";

import type { ComponentType, CSSProperties, ReactNode } from "react";
import {
  ArrowRight,
  BadgeCheck,
  Clock3,
  Heart,
  MessageCircle,
  ShieldCheck,
  Sparkles,
  Star,
  Truck,
  PlayCircle,
  icons,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type {
  Branch,
  Catalog,
  CatalogItem,
  StorefrontBenefit,
  StorefrontFaqItem,
  StorefrontGalleryItem,
  StorefrontSection,
  StorefrontSectionAction,
} from "@/lib/types";
import { Hero } from "./hero";
import { CatalogToolbar } from "./catalog-toolbar";
import { ProductGrid } from "./product-grid";
import { FadeIn } from "./motion";

interface StorefrontSectionsProps {
  catalog: Catalog;
  sections: StorefrontSection[];
  filteredItems: CatalogItem[];
  isSearching: boolean;
  search: string;
  onSearchChange: (value: string) => void;
  category: string;
  onCategoryChange: (value: string) => void;
  sortBy: string;
  onSortChange: (value: string) => void;
  selectedBranch: Branch | null;
  onBranchChange: (branchId: string) => void;
  onAction: (action: StorefrontSectionAction) => void;
}

export function StorefrontSections({
  catalog,
  sections,
  filteredItems,
  isSearching,
  search,
  onSearchChange,
  category,
  onCategoryChange,
  sortBy,
  onSortChange,
  selectedBranch,
  onBranchChange,
  onAction,
}: StorefrontSectionsProps) {
  const visibleSections = sections.filter((section) => section.enabled !== false);

  const chooseCategory = (value: string) => {
    onCategoryChange(value);
    window.requestAnimationFrame(() => {
      document.getElementById("catalog")?.scrollIntoView({ behavior: "smooth" });
    });
  };

  return (
    <main className="flex-1">
      {catalog.campaign && (
        <CampaignHero
          campaign={catalog.campaign}
          onShop={() => {
            document.getElementById("catalog")?.scrollIntoView({ behavior: "smooth" });
          }}
        />
      )}
      {visibleSections.map((section) => {
        switch (section.type) {
          case "announcement":
            return (
              <StorefrontAnnouncement
                key={section.id}
                section={section}
                onAction={onAction}
              />
            );
          case "hero":
            return (
              <div
                key={section.id}
                className="storefront-section"
                data-section-style={section.style}
              >
                <Hero
                  business={catalog.business}
                  storefront={catalog.storefront}
                  section={section}
                  onAction={onAction}
                />
              </div>
            );
          case "categoryShowcase":
            if (catalog.categories.length === 0) return null;
            return (
              <SectionShell key={section.id} section={section}>
                <SectionHeading section={section} />
                <div className="mt-8 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  {catalog.categories.slice(0, 8).map((itemCategory, index) => (
                    <button
                      key={itemCategory}
                      onClick={() => chooseCategory(itemCategory)}
                      className="group flex min-h-28 flex-col justify-between rounded-[var(--theme-radius)] border border-border-subtle bg-surface-elevated p-5 text-left transition hover:-translate-y-0.5 hover:border-accent"
                    >
                      <span className="text-[11px] font-semibold uppercase tracking-[0.16em] text-muted">
                        {String(index + 1).padStart(2, "0")}
                      </span>
                      <span className="mt-5 flex items-center justify-between gap-3 text-[16px] font-semibold">
                        {itemCategory}
                        <ArrowRight className="h-4 w-4 transition group-hover:translate-x-1" />
                      </span>
                    </button>
                  ))}
                </div>
              </SectionShell>
            );
          case "featuredProducts": {
            const requested = section.source === "category" && section.category
              ? catalog.products.filter((item) => item.category === section.category)
              : section.source === "all"
                ? catalog.products
                : catalog.products.filter((item) => item.isFeatured);
            const source = requested.length ? requested : catalog.products;
            const items = source.slice(0, section.limit || 4);
            if (items.length === 0) return null;
            return (
              <SectionShell key={section.id} section={section}>
                <SectionHeading section={section} />
                <div className="mt-8">
                  <ProductGrid
                    items={items}
                    currencySymbol={catalog.currencySymbol}
                    currencyCode={catalog.currencyCode}
                    storefrontType={catalog.storefront.type}
                  />
                </div>
              </SectionShell>
            );
          }
          case "promoBanner":
            return (
              <SectionShell key={section.id} section={section} narrow>
                <div className={alignmentClass(section.alignment)}>
                  <SectionHeading section={section} />
                  <div className="mt-7">
                    <SectionAction
                      label={section.buttonLabel}
                      action={section.buttonAction}
                      onAction={onAction}
                    />
                  </div>
                </div>
              </SectionShell>
            );
          case "benefits": {
            if (!section.items?.length) return null;
            const benefits = section.items.filter(isBenefit);
            if (!benefits.length) return null;
            return (
              <SectionShell key={section.id} section={section}>
                <SectionHeading section={section} />
                <DynamicGrid columns={section.columns} className="mt-8 gap-4">
                  {benefits.map((item, index) => (
                    <BenefitCard key={`${item.title}-${index}`} item={item} />
                  ))}
                </DynamicGrid>
              </SectionShell>
            );
          }
          case "story": {
            const cover = catalog.business.brand.coverUrls?.[0] ||
              catalog.business.brand.coverUrl;
            const sideBySide = section.imagePosition === "left" || section.imagePosition === "right";
            return (
              <SectionShell key={section.id} section={section}>
                <div className={`grid items-center gap-10 ${section.showImage && cover && sideBySide ? "lg:grid-cols-2" : ""}`}>
                  <div className={alignmentClass(section.alignment)}>
                    <SectionHeading section={section} />
                  </div>
                  {section.showImage && cover && (
                    <img
                      src={cover}
                      alt=""
                      className={`aspect-[4/3] h-full w-full rounded-[var(--theme-radius)] object-cover ring-1 ring-border-subtle ${section.imagePosition === "left" ? "lg:order-first" : ""}`}
                    />
                  )}
                </div>
              </SectionShell>
            );
          }
          case "richText":
            return (
              <SectionShell key={section.id} section={section} narrow={section.width === "narrow"}>
                <div className={alignmentClass(section.alignment)}>
                  <SectionHeading section={section} />
                  {section.content && (
                    <div className="section-muted mt-6 whitespace-pre-line text-[15px] leading-8">
                      {section.content}
                    </div>
                  )}
                </div>
              </SectionShell>
            );
          case "faq": {
            const items = (section.items || []).filter(isFaqItem);
            if (!items.length) return null;
            return (
              <SectionShell key={section.id} section={section} narrow>
                <SectionHeading section={section} />
                <div className="mt-8 divide-y divide-border-subtle border-y border-border-subtle">
                  {items.map((item, index) => (
                    <details key={`${item.question}-${index}`} className="group py-5">
                      <summary className="flex cursor-pointer list-none items-center justify-between gap-5 text-[15px] font-semibold">
                        {item.question}
                        <span className="text-xl text-accent transition group-open:rotate-45">+</span>
                      </summary>
                      <p className="section-muted max-w-2xl pt-3 text-[14px] leading-7">{item.answer}</p>
                    </details>
                  ))}
                </div>
              </SectionShell>
            );
          }
          case "gallery": {
            const items = (section.items || []).filter(isGalleryItem);
            if (!items.length) return null;
            return (
              <SectionShell key={section.id} section={section}>
                <SectionHeading section={section} />
                <DynamicGrid columns={section.columns} className="mt-8 gap-4">
                  {items.map((item, index) => (
                    <figure key={`${item.imageUrl}-${index}`} className="overflow-hidden rounded-[var(--theme-radius)] bg-surface-elevated ring-1 ring-border-subtle">
                      <img src={item.imageUrl} alt={item.alt || ""} className="aspect-[4/3] w-full object-cover" loading="lazy" />
                      {item.caption && <figcaption className="section-muted p-4 text-[12px]">{item.caption}</figcaption>}
                    </figure>
                  ))}
                </DynamicGrid>
              </SectionShell>
            );
          }
          case "video":
            if (!section.videoUrl) return null;
            return (
              <SectionShell key={section.id} section={section} narrow>
                <SectionHeading section={section} />
                <div className="relative mt-8 aspect-video overflow-hidden rounded-[var(--theme-radius)] bg-surface-elevated ring-1 ring-border-subtle">
                  <iframe
                    src={section.videoUrl}
                    title={section.title || "Store video"}
                    className="h-full w-full"
                    loading="lazy"
                    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                    allowFullScreen
                  />
                  <PlayCircle className="pointer-events-none absolute left-4 top-4 h-6 w-6 text-white/70" />
                </div>
                {section.caption && <p className="section-muted mt-3 text-[12px]">{section.caption}</p>}
              </SectionShell>
            );
          case "catalog":
            return (
              <SectionShell key={section.id} section={section}>
                <CatalogToolbar
                  categories={campaignCategories(catalog)}
                  activeCategory={category}
                  onCategoryChange={onCategoryChange}
                  search={search}
                  onSearchChange={onSearchChange}
                  sortBy={sortBy}
                  onSortChange={onSortChange}
                  branches={catalog.business.branches}
                  selectedBranch={selectedBranch}
                  onBranchChange={onBranchChange}
                />
                <div className="mt-10">
                  {filteredItems.length === 0 ? (
                    <CatalogEmptyState
                      catalog={catalog}
                      selectedBranch={selectedBranch}
                      isSearching={isSearching}
                      onClear={() => {
                        onSearchChange("");
                        onCategoryChange("all");
                      }}
                    />
                  ) : (
                    <section>
                      <FadeIn>
                        <div className="mb-6 flex items-end justify-between gap-4 border-b border-border-subtle pb-4">
                          <SectionHeading
                            section={{
                              ...section,
                              eyebrow: isSearching
                                ? "Results"
                                : catalog.campaign
                                  ? "Campaign collection"
                                  : section.eyebrow,
                              title: isSearching
                                ? "Search results"
                                : catalog.campaign
                                  ? campaignCollectionTitle(catalog)
                                  : section.title,
                              body: catalog.campaign ? "Selected products for this campaign." : section.body,
                            }}
                          />
                          <p className="hidden text-[13px] text-muted sm:block">
                            {filteredItems.length} {filteredItems.length === 1 ? "item" : "items"}
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
              </SectionShell>
            );
          case "contact":
            return (
              <SectionShell key={section.id} section={section} narrow>
                <div className={alignmentClass(section.alignment)}>
                  <SectionHeading section={section} />
                  <div className="mt-7">
                    <SectionAction
                      label={section.buttonLabel}
                      action={section.buttonAction}
                      onAction={onAction}
                    />
                  </div>
                </div>
              </SectionShell>
            );
          default:
            return null;
        }
      })}
    </main>
  );
}

function CampaignHero({
  campaign,
  onShop,
}: {
  campaign: NonNullable<Catalog["campaign"]>;
  onShop: () => void;
}) {
  return (
    <section className="storefront-section border-b border-border-subtle" data-section-style="contrast">
      <div className={`mx-auto grid max-w-7xl items-stretch ${campaign.heroImageUrl ? "lg:grid-cols-[1.08fr_0.92fr]" : ""}`}>
        <div className="flex flex-col justify-center px-5 py-16 sm:px-10 sm:py-24 lg:px-16">
          <div className="flex flex-wrap items-center gap-2">
            {campaign.badgeLabel && (
              <span className="rounded-full bg-accent px-3 py-1 text-[11px] font-bold uppercase tracking-[0.14em] text-background">
                {campaign.badgeLabel}
              </span>
            )}
            {campaign.eyebrow && (
              <span className="section-muted text-[11px] font-semibold uppercase tracking-[0.18em]">
                {campaign.eyebrow}
              </span>
            )}
          </div>
          <h1 className="mt-5 max-w-3xl font-display text-4xl leading-[1.05] tracking-tight sm:text-6xl">
            {campaign.title}
          </h1>
          {campaign.description && (
            <p className="section-muted mt-5 max-w-2xl text-[15px] leading-7 sm:text-[17px]">
              {campaign.description}
            </p>
          )}
          {campaign.highlights.length > 0 && (
            <ul className="mt-7 grid gap-3 sm:grid-cols-2">
              {campaign.highlights.map((highlight) => (
                <li key={highlight} className="flex items-start gap-2 text-[13px] text-muted-strong">
                  <BadgeCheck className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
                  <span>{highlight}</span>
                </li>
              ))}
            </ul>
          )}
          <button
            type="button"
            onClick={onShop}
            className="section-primary-action mt-8 inline-flex w-fit items-center gap-2 rounded-[var(--theme-radius)] px-6 py-3.5 text-[13px] font-bold transition hover:-translate-y-0.5"
          >
            {campaign.buttonLabel || "Shop the campaign"}
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
        {campaign.heroImageUrl && (
          <div className="min-h-[320px] overflow-hidden lg:min-h-[620px]">
            <img
              src={campaign.heroImageUrl}
              alt=""
              className="h-full w-full object-cover"
            />
          </div>
        )}
      </div>
    </section>
  );
}

export function StorefrontAnnouncement({
  section,
  onAction,
}: {
  section: StorefrontSection;
  onAction: (action: StorefrontSectionAction) => void;
}) {
  return (
    <section
      className="storefront-section border-b border-border-subtle px-4 py-2.5 text-center"
      data-section-style={section.style}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-center gap-3 text-[12px] font-semibold sm:text-[13px]">
        <span>{section.text}</span>
        <SectionAction
          label={section.buttonLabel}
          action={section.buttonAction}
          onAction={onAction}
          compact
        />
      </div>
    </section>
  );
}

function SectionShell({
  section,
  children,
  narrow = false,
}: {
  section: StorefrontSection;
  children: ReactNode;
  narrow?: boolean;
}) {
  return (
    <section
      className="storefront-section border-b border-border-subtle px-4 sm:px-6 lg:px-10"
      data-section-style={section.style}
      data-section-spacing={section.spacing || "comfortable"}
      data-section-width={section.width || (narrow ? "narrow" : "contained")}
      data-image-position={section.imagePosition || "right"}
    >
      <div className={`theme-section-inner mx-auto ${narrow ? "max-w-4xl" : ""}`}>
        {children}
      </div>
    </section>
  );
}

function DynamicGrid({ columns = 3, className, children }: { columns?: number; className?: string; children: ReactNode }) {
  return (
    <div
      className={`theme-dynamic-grid grid ${className || ""}`}
      style={{ "--section-columns": Math.max(1, Math.min(4, columns)) } as CSSProperties}
    >
      {children}
    </div>
  );
}

function isBenefit(item: StorefrontBenefit | StorefrontFaqItem | StorefrontGalleryItem): item is StorefrontBenefit {
  return "title" in item && "icon" in item;
}

function isFaqItem(item: StorefrontBenefit | StorefrontFaqItem | StorefrontGalleryItem): item is StorefrontFaqItem {
  return "question" in item && "answer" in item;
}

function isGalleryItem(item: StorefrontBenefit | StorefrontFaqItem | StorefrontGalleryItem): item is StorefrontGalleryItem {
  return "imageUrl" in item;
}

function SectionHeading({ section }: { section: StorefrontSection }) {
  const Icon = resolveSectionIcon(section.icon);
  return (
    <div className="max-w-2xl">
      {Icon && (
        <span className="theme-section-icon mb-4 inline-flex h-10 w-10 items-center justify-center text-accent">
          <Icon className="h-5 w-5" />
        </span>
      )}
      {section.eyebrow && (
        <p className="section-muted text-[11px] font-semibold uppercase tracking-[0.18em]">
          {section.eyebrow}
        </p>
      )}
      {section.title && (
        <h2 className="theme-section-heading mt-2 font-display text-3xl tracking-tight sm:text-4xl">
          {section.title}
        </h2>
      )}
      {section.body && (
        <p className="section-muted mt-4 text-[14px] leading-7 sm:text-[15px]">
          {section.body}
        </p>
      )}
    </div>
  );
}

function resolveSectionIcon(value?: string): LucideIcon | null {
  const requested = String(value || "").replace(/[^a-z0-9]/gi, "").toLowerCase();
  if (!requested) return null;
  const match = Object.entries(icons).find(([name]) =>
    name.replace(/[^a-z0-9]/gi, "").toLowerCase() === requested,
  );
  return (match?.[1] as LucideIcon | undefined) || null;
}

function SectionAction({
  label,
  action = "none",
  onAction,
  compact = false,
}: {
  label?: string;
  action?: StorefrontSectionAction;
  onAction: (action: StorefrontSectionAction) => void;
  compact?: boolean;
}) {
  if (!label || action === "none") return null;
  return (
    <button
      onClick={() => onAction(action)}
      className={compact
        ? "inline-flex items-center gap-1 underline decoration-current/40 underline-offset-4 transition hover:decoration-current"
        : "section-primary-action inline-flex items-center gap-2 rounded-[var(--theme-radius)] px-5 py-3 text-[13px] font-semibold transition hover:-translate-y-0.5"}
    >
      {label}
      <ArrowRight className="h-4 w-4" />
    </button>
  );
}

function BenefitCard({ item }: { item: StorefrontBenefit }) {
  const icons: Record<StorefrontBenefit["icon"], ComponentType<{ className?: string }>> = {
    sparkles: Sparkles,
    shield: ShieldCheck,
    truck: Truck,
    clock: Clock3,
    heart: Heart,
    message: MessageCircle,
    star: Star,
  };
  const Icon = icons[item.icon] || Sparkles;
  return (
    <div className="rounded-[var(--theme-radius)] border border-border-subtle bg-surface-elevated p-6">
      <div className="flex h-10 w-10 items-center justify-center rounded-full bg-accent text-background">
        <Icon className="h-4 w-4" />
      </div>
      <h3 className="mt-5 text-[16px] font-semibold">{item.title}</h3>
      {item.body && (
        <p className="section-muted mt-2 text-[13px] leading-6">{item.body}</p>
      )}
    </div>
  );
}

function CatalogEmptyState({
  catalog,
  selectedBranch,
  isSearching,
  onClear,
}: {
  catalog: Catalog;
  selectedBranch: Branch | null;
  isSearching: boolean;
  onClear: () => void;
}) {
  if (catalog.products.length === 0 && !isSearching) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-center">
        <p className="font-display text-2xl tracking-tight">
          {catalog.storefront.type === "services"
            ? "No services published for this branch yet"
            : catalog.storefront.type === "restaurant"
              ? "No menu items published for this branch yet"
              : "No products published for this branch yet"}
        </p>
        <p className="section-muted mt-2 text-[13px]">
          {selectedBranch?.name
            ? `Switch to another branch or publish items for ${selectedBranch.name}.`
            : "Publish items to see them in this store."}
        </p>
      </div>
    );
  }
  return (
    <div className="flex flex-col items-center justify-center py-20 text-center">
      <p className="font-display text-2xl tracking-tight">No items match your search</p>
      <p className="section-muted mt-2 text-[13px]">Try a different keyword or clear your filters.</p>
      <button
        onClick={onClear}
        className="section-primary-action mt-5 rounded-[var(--theme-radius)] px-4 py-2 text-[13px] font-semibold"
      >
        Clear filters
      </button>
    </div>
  );
}

function alignmentClass(alignment: StorefrontSection["alignment"]) {
  return alignment === "center"
    ? "mx-auto flex max-w-2xl flex-col items-center text-center"
    : alignment === "right"
      ? "ml-auto flex max-w-2xl flex-col items-end text-right"
      : "flex max-w-2xl flex-col items-start text-left";
}

function campaignCollectionTitle(catalog: Catalog) {
  return catalog.campaign?.name || "Campaign products";
}

function campaignCategories(catalog: Catalog) {
  if (!catalog.campaign) return catalog.categories;
  const selectedIds = new Set(catalog.campaign.productIds);
  return [...new Set(
    catalog.products
      .filter((item) => selectedIds.has(item.id))
      .map((item) => item.category)
      .filter((value): value is string => Boolean(value)),
  )].sort((first, second) => first.localeCompare(second));
}
