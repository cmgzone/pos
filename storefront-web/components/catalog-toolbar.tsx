"use client";

import { Search, Store } from "lucide-react";
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
      <div id="catalog" className="sticky top-14 z-30 -mx-4 px-4 sm:-mx-6 sm:px-6 lg:-mx-8 lg:px-8 xl:-mx-12 xl:px-12">
        <div className="rounded-b-2xl bg-[#111114]/90 px-4 py-3.5 backdrop-blur-lg ring-1 ring-white/[0.06] sm:px-6">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex flex-1 items-center gap-2">
              <div className="relative flex-1 max-w-sm">
                <Search className="absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
                <input
                  type="text"
                  value={search}
                  onChange={(e) => onSearchChange(e.target.value)}
                  placeholder="Search..."
                  className="h-9 w-full rounded-full bg-surface-elevated pl-9 pr-3 text-xs text-foreground placeholder:text-muted ring-1 ring-white/[0.06] focus:outline-none focus:ring-2 focus:ring-accent/40"
                />
              </div>

              {branches.length > 1 && (
                <div className="relative">
                  <Store className="absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted" />
                  <select
                    value={selectedBranch?.id || ""}
                    onChange={(e) => onBranchChange(e.target.value)}
                    className="h-9 appearance-none rounded-full bg-surface-elevated pl-8 pr-7 text-xs ring-1 ring-white/[0.06] focus:outline-none focus:ring-2 focus:ring-accent/40"
                  >
                    {branches.map((branch) => (
                      <option key={branch.id} value={branch.id}>
                        {branch.name}
                      </option>
                    ))}
                  </select>
                </div>
              )}
            </div>

            <select
              value={sortBy}
              onChange={(e) => onSortChange(e.target.value)}
              className="h-8 w-fit rounded-full bg-surface-elevated px-3 text-[11px] font-medium ring-1 ring-white/[0.06] focus:outline-none focus:ring-2 focus:ring-accent/40"
            >
              <option value="featured">Featured</option>
              <option value="priceAsc">Price: Low to High</option>
              <option value="priceDesc">Price: High to Low</option>
              <option value="name">Name</option>
            </select>
          </div>

          {categories.length > 0 && (
            <div className="mt-3 flex gap-1.5 overflow-x-auto pb-0.5">
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
      className="relative shrink-0 rounded-full px-3 py-1 text-[11px] font-medium transition"
    >
      {active && (
        <motion.div
          layoutId="activeCategory"
          className="absolute inset-0 rounded-full bg-accent/12 ring-1 ring-accent/25"
          transition={{ type: "spring", bounce: 0.2, duration: 0.4 }}
        />
      )}
      <span className={active ? "text-accent" : "text-muted hover:text-foreground"}>
        {label}
      </span>
    </button>
  );
}
