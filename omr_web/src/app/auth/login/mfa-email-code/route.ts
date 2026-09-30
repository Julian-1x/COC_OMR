import { NextResponse } from "next/server";
import { tryGetApiBaseUrl } from "@/lib/api/env";
import { fetchAuthUpstream, wakeSchoolApi } from "@/lib/api/wake-api";

type EmailCodeResponse = {
  ok?: boolean;
  message?: string;
  email_hint?: string;
  resend_after_seconds?: number;
  errors?: Record<string, string[]>;
};

function errorMessage(payload: EmailCodeResponse | null, fallback: string): string {
  if (payload?.message) return payload.message;
  const first = payload?.errors ? Object.values(payload.errors)[0]?.[0] : undefined;
  return first ?? fallback;
}

export async function POST(request: Request) {
  try {
    const baseUrl = tryGetApiBaseUrl();
    if (!baseUrl) {
      return NextResponse.json(
        { error: "API is not configured. Check omr_web/.env.local and restart npm run dev." },
        { status: 500 },
      );
    }

    const body = (await request.json()) as { mfa_ticket?: string };
    const mfaTicket = body.mfa_ticket?.trim() ?? "";
    if (!mfaTicket) {
      return NextResponse.json(
        { error: "Sign-in expired. Enter your password again." },
        { status: 400 },
      );
    }

    await wakeSchoolApi(baseUrl, { attempts: 3, delayMs: 2000, probeTimeoutMs: 30_000 });

    const response = await fetchAuthUpstream(
      `${baseUrl}/api/login/mfa/email-code`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({ mfa_ticket: mfaTicket }),
      },
      { attempts: 4, timeoutMs: 90_000 },
    );

    let payload: EmailCodeResponse | null = null;
    try {
      payload = (await response.json()) as EmailCodeResponse;
    } catch {
      payload = null;
    }

    if (response.status === 404) {
      return NextResponse.json(
        {
          error:
            "Email sign-in codes are not available on the school server yet. Use your authenticator app, or try again in a few minutes after the server updates.",
        },
        { status: 503 },
      );
    }

    if (!response.ok || payload?.ok !== true) {
      return NextResponse.json(
        { error: errorMessage(payload, "Could not email a sign-in code. Try again.") },
        { status: response.status || 400 },
      );
    }

    return NextResponse.json({
      ok: true,
      message: payload?.message,
      emailHint: payload?.email_hint,
      resendAfterSeconds: payload?.resend_after_seconds ?? 60,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not reach the school API.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
