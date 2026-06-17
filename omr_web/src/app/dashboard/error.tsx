"use client";

import { useEffect } from "react";
import { Button } from "@/components/ui/button";

export default function DashboardError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center p-6 text-center">
      <h2 className="text-xl font-extrabold text-slate-800">Something went wrong</h2>
      <p className="mt-2 max-w-md text-sm text-slate-600">
        {error.message || "We could not load this page. Try again, or sign out and sign back in."}
      </p>
      <div className="mt-4 flex gap-2">
        <Button type="button" onClick={reset}>
          Try again
        </Button>
        <Button
          type="button"
          variant="secondary"
          onClick={() => {
            window.location.href = "/login";
          }}
        >
          Sign in
        </Button>
      </div>
    </div>
  );
}
