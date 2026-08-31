import { NextResponse } from "next/server";
import { tryGetApiBaseUrl } from "@/lib/api/env";
import { fetchAuthUpstream, wakeSchoolApi } from "@/lib/api/wake-api";

type SetupResponse = {
  secret?: string;
  otpauth_url?: string;
  message?: string;
  errors?: Record<string, string[]>;
};

function errorMessage(payload: SetupResponse | null, fallback: string): string {
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
      return NextResponse.json({ error: "Sign-in expired. Enter your password again." }, { status: 400 });
    }

    await wakeSchoolApi(baseUrl, { attempts: 3, delayMs: 2000, probeTimeoutMs: 30_000 });

    const response = await fetchAuthUpstream(
      `${baseUrl}/api/login/mfa/setup`,
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

    const payload = (await response.json()) as SetupResponse;
    if (!response.ok || !payload.secret) {
      return NextResponse.json(
        { error: errorMessage(payload, "Could not start two-factor setup. Sign in again.") },
        { status: response.status || 400 },
      );
    }

    return NextResponse.json({
      secret: payload.secret,
      otpauthUrl: payload.otpauth_url,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not reach the school API.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
