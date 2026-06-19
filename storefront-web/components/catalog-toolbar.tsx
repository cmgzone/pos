"use client";

import { Search, SlidersHorizontal, Store } from "lucide-react";
import { motion } from "framer-motion";
import type { Branch } from "@/lib/types";
import { FadeIn } from "./motion";

interface CatalogToolbarProps {
  categories: string[];
  activeCategory: string;
  onCategoryChange: (category: string) => void;
  search: string;
  onSearchChange: (value: string) => void;
  sortBy: string;
  onSortChange: (value: string) => void;
  branches: Branch[];
  selectedBranch: Branch | null;
  onBranchChange: (branchId: string) => void;
}

export function CatalogToolbar({
  categories,
  activeCategory,
  onCategoryChange,
  search,
  onSearchChange,
  sortBy,
  onSortChange,
  branches,
  selectedBranch,
  onBranchChange,
}: CatalogToolbarProps) {
  return (
    <FadeIn>
      <div
        id="catalog"
        className="sticky top-0 z-30 -mx-4 px-4 py-4 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8 xl:-mx-12 xl:px-12 glass"
      >
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex flex-1 items-center gap-3">
            <div className="relative flex-1 max-w-md">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
              <input
                type="text"
                value={search}
                onChange={(e) => onSearchChange(e.target.value)}
                placeholder="Search products & services..."
                className="h-11 w-full rounded-full bg-surface pl-10 pr-4 text-sm text-foreground placeholder:text-muted ring-1 ring-white/10 focus:outline-none focus:ring-2 focus:ring-accent/50"
              />
            </div>

            {branches.length > 1 && (
              <div className="relative">
                <Store className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
                <select
                  value={selectedBranch?.id || ""}
                  onChange={(e) => onBranchChange(e.target.value)}
                  className="h-11 appearance-none rounded-full bg-surface pl-10 pr-8 text-sm ring-1 ring-white/10 focus:outline-none focus:ring-2 focus:ring-accent/50"
                >
                  {branches.map((branch) => (
                    <option key={branch.id} value={branch.id}>
                      {branch.name}
                    </option>
                  ))}
                </select>
                <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2">
                  <SlidersHorizontal className="h-3.5 w-3.5 text-muted" />
                </div>
              </div>
            )}
          </div>

          <div className="flex items-center gap-3 overflow-x-auto pb-1 lg:pb-0">
            <select
              value={sortBy}
              onChange={(e) => onSortChange(e.target.value)}
              className="h-9 whitespace-nowrap rounded-full bg-surface px-4 text-xs font-medium ring-1 ring-white/10 focus:outline-none focus:ring-2 focus:ring-accent/50"
            >
              <option value="featured">Featured</option>
              <option value="priceAsc">Price: Low to High</option>
              <option value="priceDesc">Price: High to Low</option>
              <option value="name">Name</option>
            </select>
          </div>
        </div>

        {categories.length > 0 && (
          <div className="mt-4 flex gap-2 overflow-x-auto pb-1">
            <CategoryPill
              label="All"
              active={activeCategory === "all"}
              onClick={() => onCategoryChange("all")}
            />
            {categories.map((cat) => (
              <CategoryPill
                key={cat}
                label={cat}
                active={activeCategory === cat}
                onClick={() => onCategoryChange(cat)}
              />
            ))}
          </div>
        )}
      </div>
    </FadeIn>
  );
}

function CategoryPill({
  label,
  active,
  onClick,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="relative shrink-0 rounded-full px-4 py-1.5 text-xs font-medium transition"
    >
      {active && (
        <motion.div
          layoutId="activeCategory"
          className="absolute inset-0 rounded-full bg-accent/10 ring-1 ring-accent/30"
          transition={{ type: "spring", bounce: 0.2, duration: 0.5 }}
        />
      )}
      <span className={active ? "text-accent" : "text-muted hover:text-foreground"}>
        {label}
      </span>
    </button>
  );
}