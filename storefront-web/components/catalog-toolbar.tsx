"use client";

import { Search, Store, ChevronDown } from "lucide-react";
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
        className="sticky top-16 z-30 -mx-4 border-b border-border-subtle bg-background/95 px-4 backdrop-blur-md sm:-mx-6 sm:px-6 lg:-mx-10 lg:px-10"
      >
        <div className="flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex flex-1 items-center gap-2.5">
            <div className="relative flex-1 sm:max-w-xs">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
              <input
                type="text"
                value={search}
                onChange={(e) => onSearchChange(e.target.value)}
                placeholder="Search the store"
                className="h-10 w-full rounded-md border border-border-subtle bg-surface pl-9 pr-3 text-[13px] text-foreground placeholder:text-muted focus:border-accent focus:outline-none"
              />
            </div>

            {branches.length > 1 && (
              <div className="relative">
                <Store className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
                <select
                  value={selectedBranch?.id || ""}
                  onChange={(e) => onBranchChange(e.target.value)}
                  className="h-10 appearance-none rounded-md border border-border-subtle bg-surface pl-9 pr-9 text-[13px] text-foreground focus:border-accent focus:outline-none"
                  aria-label="Choose branch"
                >
                  {branches.map((branch) => (
                    <option key={branch.id} value={branch.id}>
                      {branch.name}
                    </option>
                  ))}
                </select>
                <ChevronDown className="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
              </div>
            )}
          </div>

          <div className="relative">
            <select
              value={sortBy}
              onChange={(e) => onSortChange(e.target.value)}
              className="h-10 appearance-none rounded-md border border-border-subtle bg-surface pl-3 pr-9 text-[13px] font-medium text-foreground focus:border-accent focus:outline-none"
              aria-label="Sort by"
            >
              <option value="featured">Featured</option>
              <option value="priceAsc">Price: Low to High</option>
              <option value="priceDesc">Price: High to Low</option>
              <option value="name">Name: A–Z</option>
            </select>
            <ChevronDown className="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          </div>
        </div>

        {categories.length > 0 && (
          <div className="flex gap-1 overflow-x-auto border-t border-border-subtle py-2.5">
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
      className="relative shrink-0 rounded-md px-3 py-1.5 text-[13px] font-medium transition"
    >
      {active && (
        <motion.div
          layoutId="activeCategory"
          className="absolute inset-0 rounded-md bg-surface-elevated ring-1 ring-border-strong"
          transition={{ type: "spring", bounce: 0.18, duration: 0.35 }}
        />
      )}
      <span
        className={
          active
            ? "relative text-foreground"
            : "relative text-muted transition hover:text-foreground"
        }
      >
        {label}
      </span>
    </button>
  );
}
