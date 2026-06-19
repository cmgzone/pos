"use client";

import { AlertCircle } from "lucide-react";

interface ErrorStateProps {
  message: string;
}

export function ErrorState({ message }: ErrorStateProps) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center p-6 text-center">
      <div className="flex h-16 w-16 items-center justify-center rounded-full bg-red-500/10">
        <AlertCircle className="h-8 w-8 text-red-400" />
      </div>
      <h1 className="mt-6 text-2xl font-bold">Store unavailable</h1>
      <p className="mt-2 max-w-md text-muted">{message}</p>
      <button
        onClick={() => window.location.reload()}
        className="mt-6 rounded-full bg-accent px-6 py-2.5 text-sm font-semibold text-background transition hover:opacity-90"
      >
        Try again
      </button>
    </div>
  );
}
