"use client";

import Script from "next/script";
import { useEffect, useRef, useState } from "react";

declare global {
  interface Window {
    turnstile?: {
      render: (
        container: HTMLElement,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          "expired-callback"?: () => void;
          "error-callback"?: () => void;
          theme?: "light" | "dark" | "auto";
        },
      ) => string;
      reset: (widgetId?: string) => void;
      remove: (widgetId: string) => void;
    };
  }
}

type TurnstileFieldProps = {
  siteKey: string;
  onToken: (token: string | null) => void;
};

export function TurnstileField({ siteKey, onToken }: TurnstileFieldProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const widgetIdRef = useRef<string | null>(null);
  const onTokenRef = useRef(onToken);
  const [ready, setReady] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    onTokenRef.current = onToken;
  }, [onToken]);

  useEffect(() => {
    if (!ready || !containerRef.current || !window.turnstile || !siteKey) {
      return;
    }

    setLoadError(null);
    onTokenRef.current(null);

    widgetIdRef.current = window.turnstile.render(containerRef.current, {
      sitekey: siteKey,
      theme: "light",
      callback: (token) => onTokenRef.current(token),
      "expired-callback": () => onTokenRef.current(null),
      "error-callback": () => {
        onTokenRef.current(null);
        setLoadError("Security check failed to load. Refresh the page.");
      },
    });

    return () => {
      if (widgetIdRef.current && window.turnstile) {
        window.turnstile.remove(widgetIdRef.current);
        widgetIdRef.current = null;
      }
    };
  }, [ready, siteKey]);

  if (!siteKey) {
    return null;
  }

  return (
    <div className="my-3">
      <p className="mb-2 text-xs font-bold uppercase tracking-wide text-slate-500">
        Security check
      </p>
      <Script
        src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
        strategy="afterInteractive"
        onLoad={() => setReady(true)}
        onError={() =>
          setLoadError("Could not load security check. Check your connection and refresh.")
        }
      />
      {!ready && !loadError ? (
        <p className="mb-2 text-xs text-slate-500">Loading security check…</p>
      ) : null}
      <div className="flex w-full justify-center">
        <div ref={containerRef} className="inline-flex min-h-[65px] justify-center" />
      </div>
      {loadError ? (
        <p className="mt-2 rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-700">
          {loadError}
        </p>
      ) : null}
    </div>
  );
}
