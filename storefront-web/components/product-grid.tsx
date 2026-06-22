"use client";

import type { CatalogItem } from "@/lib/types";
import { StaggerContainer } from "./motion";
import { ProductCard } from "./product-card";
import { ServiceCard } from "./service-card";

interface ProductGridProps {
  items: CatalogItem[];
  currencySymbol: string;
  currencyCode: string;
}

export function ProductGrid({ items, currencySymbol, currencyCode }: ProductGridProps) {
  return (
    <StaggerContainer className="grid grid-cols-2 gap-4 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4 xl:gap-6">
      {items.map((item) =>
        (item.itemType || item.type) === "service" ? (
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
