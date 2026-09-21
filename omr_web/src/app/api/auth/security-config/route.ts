import { NextResponse } from "next/server";
import { tryGetApiBaseUrl } from "@/lib/api/env";

/** Public: site key for Cloudflare Turnstile (no sign-in required). */
export async function GET() {
  try {
    const baseUrl = tryGetApiBaseUrl();
    if (!baseUrl) {
      return NextResponse.json(
        { captcha_enabled: false, captcha_site_key: null },
        { status: 200 },
      );
    }

    const response = await fetch(`${baseUrl}/api/auth/security-config`, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
    });

    if (!response.ok) {
      return NextResponse.json(
        { captcha_enabled: false, captcha_site_key: null },
        { status: 200 },
      );
    }

    const payload = (await response.json()) as {
      captcha_enabled?: boolean;
      captcha_site_key?: string | null;
    };

    return NextResponse.json({
      captcha_enabled: Boolean(payload.captcha_enabled),
      captcha_site_key: payload.captcha_site_key ?? null,
    });
  } catch {
    return NextResponse.json(
      { captcha_enabled: false, captcha_site_key: null },
      { status: 200 },
    );
  }
}
