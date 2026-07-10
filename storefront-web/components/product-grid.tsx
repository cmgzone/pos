"use client";

import type { CatalogItem, StorefrontType } from "@/lib/types";
import { StaggerContainer } from "./motion";
import { ProductCard } from "./product-card";
import { ServiceCard } from "./service-card";
import { RestaurantMenuCard } from "./restaurant-menu-card";

interface ProductGridProps {
  items: CatalogItem[];
  currencySymbol: string;
  currencyCode: string;
  storefrontType?: StorefrontType;
}

export function ProductGrid({
  items,
  currencySymbol,
  currencyCode,
  storefrontType = "retail",
}: ProductGridProps) {
  return (
    <StaggerContainer className={
      storefrontType === "restaurant"
        ? "grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:gap-6"
        : "grid grid-cols-2 gap-4 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4 xl:gap-6"
    }>
      {items.map((item) =>
        storefrontType === "restaurant" ? (
          <RestaurantMenuCard
            key={item.id}
            item={item}
            currencySymbol={currencySymbol}
            currencyCode={currencyCode}
          />
        ) : (item.itemType || item.type) === "service" ? (
          <ServiceCard
            key={item.id}
            item={item}
            currencySymbol={currencySymbol}
            currencyCode={currencyCode}
          />
        ) : (
          <ProductCard
            key={item.id}
            item={item}
            currencySymbol={currencySymbol}
            currencyCode={currencyCode}
          />
        )
      )}
    </StaggerContainer>
  );
}
