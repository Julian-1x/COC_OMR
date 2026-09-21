"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { TurnstileField } from "@/components/auth/turnstile-field";

declare global {
  interface Window {
    TurnstileChannel?: {
      postMessage: (message: string) => void;
    };
  }
}

function postToApp(token: string | null) {
  window.TurnstileChannel?.postMessage(token ?? "");
}

function MobileCaptchaInner() {
  const params = useSearchParams();
  const siteKey =
    params.get("siteKey")?.trim() ??
    process.env.NEXT_PUBLIC_CAPTCHA_SITE_KEY?.trim() ??
    "";

  if (!siteKey) {
    return (
      <p style={{ margin: 8, fontFamily: "system-ui", fontSize: 13 }}>
        Security check is not configured.
      </p>
    );
  }

  return (
    <div style={{ padding: 8, minHeight: 72, background: "transparent" }}>
      <TurnstileField siteKey={siteKey} onToken={postToApp} />
    </div>
  );
}

/** Loaded inside the Flutter app WebView — Turnstile must run on omrweb.vercel.app. */
export default function MobileCaptchaPage() {
  return (
    <Suspense fallback={<div style={{ minHeight: 72 }} />}>
      <MobileCaptchaInner />
    </Suspense>
  );
}
