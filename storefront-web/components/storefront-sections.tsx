"use client";

import type { ComponentType, ReactNode } from "react";
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
} from "lucide-react";
import type {
  Branch,
  Catalog,
  CatalogItem,
  StorefrontBenefit,
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
          case "benefits":
            if (!section.items?.length) return null;
            return (
              <SectionShell key={section.id} section={section}>
                <SectionHeading section={section} />
                <div className="mt-8 grid gap-4 md:grid-cols-3">
                  {section.items.map((item, index) => (
                    <BenefitCard key={`${item.title}-${index}`} item={item} />
                  ))}
                </div>
              </SectionShell>
            );
          case "story": {
            const cover = catalog.business.brand.coverUrls?.[0] ||
              catalog.business.brand.coverUrl;
            return (
              <SectionShell key={section.id} section={section}>
                <div className={`grid items-center gap-10 ${section.showImage && cover ? "lg:grid-cols-2" : ""}`}>
                  <div className={alignmentClass(section.alignment)}>
                    <SectionHeading section={section} />
                  </div>
                  {section.showImage && cover && (
                    <img
                      src={cover}
                      alt=""
                      className="aspect-[4/3] h-full w-full rounded-[var(--theme-radius)] object-cover ring-1 ring-border-subtle"
                    />
                  )}
                </div>
              </SectionShell>
            );
          }
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
      className="storefront-section border-b border-border-subtle px-4 py-16 sm:px-6 sm:py-20 lg:px-10"
      data-section-style={section.style}
    >
      <div className={`mx-auto ${narrow ? "max-w-4xl" : "max-w-6xl"}`}>
        {children}
      </div>
    </section>
  );
}

function SectionHeading({ section }: { section: StorefrontSection }) {
  return (
    <div className="max-w-2xl">
      {section.eyebrow && (
        <p className="section-muted text-[11px] font-semibold uppercase tracking-[0.18em]">
          {section.eyebrow}
        </p>
      )}
      {section.title && (
        <h2 className="mt-2 font-display text-3xl tracking-tight sm:text-4xl">
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
