"use client";

export function SkeletonGrid() {
  return (
    <div className="grid grid-cols-2 gap-4 sm:gap-5 lg:grid-cols-3 xl:grid-cols-4 xl:gap-6">
      {Array.from({ length: 8 }).map((_, i) => (
        <div
          key={i}
          className="overflow-hidden rounded-lg border border-border-subtle bg-surface"
        >
          <div className="aspect-[4/5] placeholder-shimmer" />
          <div className="p-4">
            <div className="h-2.5 w-16 rounded placeholder-shimmer" />
            <div className="mt-3 h-4 w-3/4 rounded placeholder-shimmer" />
            <div className="mt-1.5 h-3 w-1/2 rounded placeholder-shimmer" />
            <div className="mt-4 flex items-center justify-between">
              <div className="h-5 w-20 rounded placeholder-shimmer" />
            </div>
            <div className="mt-3 h-10 rounded-md placeholder-shimmer" />
          </div>
        </div>
      ))}
    </div>
  );
}
