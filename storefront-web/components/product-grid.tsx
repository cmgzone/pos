"use client";

import type { CatalogItem } from "@/lib/types";
import { StaggerContainer } from "./motion";
import { ProductCard } from "./product-card";
import { ServiceCard } from "./service-card";

interface ProductGridProps {
  items: CatalogItem[];
  currency: string;
}

export function ProductGrid({ items, currency }: ProductGridProps) {
  return (
    <StaggerContainer className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {items.map((item) =>
        item.itemType === "service" ? (
          <ServiceCard key={item.id} item={item} currency={currency} />
        ) : (
          <ProductCard key={item.id} item={item} currency={currency} />
        )
      )}
    </StaggerContainer>
  );
}
