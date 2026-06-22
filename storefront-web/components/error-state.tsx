"use client";

import { AlertCircle } from "lucide-react";

interface ErrorStateProps {
  message: string;
}

export function ErrorState({ message }: ErrorStateProps) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center px-6 text-center">
      <div className="flex h-14 w-14 items-center justify-center rounded-full bg-surface-elevated ring-1 ring-border-subtle">
        <AlertCircle className="h-7 w-7 text-muted-strong" />
      </div>
      <h1 className="mt-6 font-display text-3xl tracking-tight">Store unavailable</h1>
      <p className="mt-2 max-w-md text-[14px] leading-relaxed text-muted">{message}</p>
      <button
        onClick={() => window.location.reload()}
        className="mt-6 rounded-md bg-foreground px-6 py-3 text-[14px] font-semibold text-background transition hover:opacity-90"
      >
        Try again
      </button>
    </div>
  );
}
