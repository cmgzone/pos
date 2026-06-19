"use client";

export function SkeletonGrid() {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
      {Array.from({ length: 8 }).map((_, i) => (
        <div
          key={i}
          className="overflow-hidden rounded-2xl bg-[#141418] ring-1 ring-white/[0.05]"
        >
          <div className="aspect-[4/3] shimmer bg-surface" />
          <div className="p-3.5">
            <div className="h-2.5 w-16 rounded shimmer bg-surface" />
            <div className="mt-2.5 h-4 w-3/4 rounded shimmer bg-surface" />
            <div className="mt-1.5 h-3 w-1/2 rounded shimmer bg-surface" />
            <div className="mt-3 flex items-center justify-between">
              <div className="h-5 w-16 rounded shimmer bg-surface" />
              <div className="h-8 w-8 rounded-full shimmer bg-surface" />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
