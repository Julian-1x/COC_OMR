"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { BrandHeader } from "@/components/brand";
import { Button } from "@/components/ui/button";

/**
 * Shown when the teacher desk cannot load /api/me (DB wake, brief deploy, etc.).
 * Only leave this page after the session check succeeds — /up alone is not enough
 * (that caused a warming ↔ dashboard loop).
 */
export default function WarmingPage() {
  const router = useRouter();
  const [seconds, setSeconds] = useState(0);
  const [status, setStatus] = useState("Connecting to the school server…");
  const [busy, setBusy] = useState(false);
  const apiBase =
    process.env.NEXT_PUBLIC_API_BASE_URL?.replace(/\/$/, "") ??
    "https://coc-omr-api.onrender.com";
  const upUrl = `${apiBase}/up`;

  async function tryOpenDashboard(manual: boolean) {
    if (busy) return;
    if (manual) setBusy(true);

    try {
      const up = await fetch(upUrl, { cache: "no-store" });
      if (!up.ok) {
        setStatus("School API is not answering yet. Waiting…");
        return;
      }

      setStatus("Server is up — checking your sign-in…");
      const me = await fetch("/api/laravel/me", {
        cache: "no-store",
        credentials: "same-origin",
      });

      if (me.status === 401 || me.status === 403) {
        setStatus("Your session expired. Signing you out…");
        router.replace("/auth/signout?next=/login");
        return;
      }

      if (!me.ok) {
        const payload = (await me.json().catch(() => null)) as {
          message?: string;
        } | null;
        setStatus(
          payload?.message?.trim() ||
            "School API is up, but loading your account failed (often the database waking). Retrying…",
        );
        return;
      }

      setStatus("Signed in — opening your dashboard…");
      router.replace("/dashboard");
      router.refresh();
    } catch {
      setStatus("Could not reach the school API. Retrying…");
    } finally {
      if (manual) setBusy(false);
    }
  }

  useEffect(() => {
    let cancelled = false;
    const started = Date.now();

    const tick = window.setInterval(() => {
      setSeconds(Math.floor((Date.now() - started) / 1000));
    }, 500);

    const run = () => {
      if (!cancelled) void tryOpenDashboard(false);
    };

    run();
    const intervalId = window.setInterval(run, 5000);

    const timeoutId = window.setTimeout(() => {
      if (!cancelled) {
        setStatus(
          "Still connecting. Confirm https://coc-omr-api.onrender.com/up says Application up, " +
            "wake Neon (SQL Editor → SELECT 1), then tap Try dashboard. " +
            "If this keeps looping, check Render Logs for errors.",
        );
      }
    }, 60_000);

    return () => {
      cancelled = true;
      window.clearInterval(tick);
      window.clearInterval(intervalId);
      window.clearTimeout(timeoutId);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- mount-only retry loop
  }, [router, upUrl]);

  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-slate-50 px-4">
      <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-8 shadow-sm">
        <BrandHeader />
        <h1 className="mt-6 text-xl font-extrabold text-slate-800">
          Connecting to school server
        </h1>
        <p className="mt-2 text-sm leading-relaxed text-slate-600">{status}</p>
        <p className="mt-2 text-xs text-slate-400">Waited {seconds}s</p>
        <div className="mt-6 flex flex-col gap-2">
          <Button
            type="button"
            disabled={busy}
            onClick={() => void tryOpenDashboard(true)}
          >
            {busy ? "Checking…" : "Try dashboard"}
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() => {
              window.open(upUrl, "_blank");
            }}
          >
            Open API status
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() => router.replace("/auth/signout?next=/login")}
          >
            Sign out and try again
          </Button>
        </div>
      </div>
    </main>
  );
}
