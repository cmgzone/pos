"use client";

export function SkeletonGrid() {
  return (
    <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {Array.from({ length: 8 }).map((_, i) => (
        <div
          key={i}
          className="overflow-hidden rounded-2xl bg-surface ring-1 ring-white/[0.06]"
        >
          <div className="aspect-[4/3] shimmer bg-surface-elevated" />
          <div className="p-4">
            <div className="h-3 w-16 rounded shimmer bg-surface-elevated" />
            <div className="mt-3 h-5 w-3/4 rounded shimmer bg-surface-elevated" />
            <div className="mt-2 h-4 w-1/2 rounded shimmer bg-surface-elevated" />
            <div className="mt-5 flex items-center justify-between">
              <div className="h-6 w-20 rounded shimmer bg-surface-elevated" />
              <div className="h-9 w-9 rounded-full shimmer bg-surface-elevated" />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
