"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { BrandHeader } from "@/components/brand";
import { Button } from "@/components/ui/button";

/**
 * Shown when the school API is sleeping (Render free tier).
 * Keeps the login cookie and retries the dashboard after /up is healthy.
 */
export default function WarmingPage() {
  const router = useRouter();
  const [seconds, setSeconds] = useState(0);
  const [status, setStatus] = useState("Waking the school server…");

  useEffect(() => {
    let cancelled = false;
    const started = Date.now();

    const tick = window.setInterval(() => {
      setSeconds(Math.floor((Date.now() - started) / 1000));
    }, 500);

    const probe = async () => {
      try {
        const apiBase =
          process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") ??
          "https://coc-omr-api.onrender.com";
        const response = await fetch(`${apiBase}/up`, { cache: "no-store" });
        if (!cancelled && response.ok) {
          setStatus("Server is up — opening your dashboard…");
          router.replace("/dashboard");
          router.refresh();
          return true;
        }
      } catch {
        // keep trying
      }
      return false;
    };

    void probe();
    const intervalId = window.setInterval(() => {
      void probe();
    }, 4000);

    const timeoutId = window.setTimeout(() => {
      if (!cancelled) {
        setStatus(
          "Still waking up. Open the API /up page once, wait for Application up, then tap Try dashboard.",
        );
      }
    }, 90_000);

    return () => {
      cancelled = true;
      window.clearInterval(tick);
      window.clearInterval(intervalId);
      window.clearTimeout(timeoutId);
    };
  }, [router]);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-slate-50 px-4">
      <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-8 shadow-sm">
        <BrandHeader />
        <h1 className="mt-6 text-xl font-extrabold text-slate-800">
          School server is starting
        </h1>
        <p className="mt-2 text-sm leading-relaxed text-slate-600">{status}</p>
        <p className="mt-2 text-xs text-slate-400">Waited {seconds}s</p>
        <div className="mt-6 flex flex-col gap-2">
          <Button type="button" onClick={() => router.replace("/dashboard")}>
            Try dashboard
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() => {
              window.open("https://coc-omr-api.onrender.com/up", "_blank");
            }}
          >
            Open API status
          </Button>
        </div>
      </div>
    </main>
  );
}
