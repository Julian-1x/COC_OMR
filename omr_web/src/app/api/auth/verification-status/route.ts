import { NextResponse } from "next/server";
import { tryGetApiBaseUrl } from "@/lib/api/env";

type StatusResponse = {
  verified?: boolean;
  message?: string;
  errors?: Record<string, string[]>;
};

function errorMessage(payload: StatusResponse | null, fallback: string): string {
  if (payload?.message) return payload.message;
  const first = payload?.errors ? Object.values(payload.errors)[0]?.[0] : undefined;
  return first ?? fallback;
}

export async function POST(request: Request) {
  try {
    const baseUrl = tryGetApiBaseUrl();
    if (!baseUrl) {
      return NextResponse.json({ error: "API is not configured." }, { status: 500 });
    }

    const body = (await request.json()) as { email?: string };
    const email = body.email?.trim().toLowerCase() ?? "";
    if (!email) {
      return NextResponse.json({ error: "Email is required." }, { status: 400 });
    }

    const response = await fetch(`${baseUrl}/api/email/verification-check`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ email }),
    });

    const text = await response.text();
    let payload: StatusResponse | null = null;
    if (text.trim()) {
      try {
        payload = JSON.parse(text) as StatusResponse;
      } catch {
        payload = null;
      }
    }

    if (!response.ok) {
      return NextResponse.json(
        { error: errorMessage(payload, "Could not check verification status.") },
        { status: response.status },
      );
    }

    return NextResponse.json({
      ok: true,
      verified: payload?.verified === true,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not reach the API.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
