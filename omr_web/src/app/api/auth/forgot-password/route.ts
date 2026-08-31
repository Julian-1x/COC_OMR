import { NextResponse } from "next/server";
import { tryGetApiBaseUrl } from "@/lib/api/env";

type ForgotResponse = {
  message?: string;
  errors?: Record<string, string[]>;
};

function errorMessage(payload: ForgotResponse | null, fallback: string): string {
  if (payload?.message) return payload.message;
  const first = payload?.errors ? Object.values(payload.errors)[0]?.[0] : undefined;
  return first ?? fallback;
}

export async function POST(request: Request) {
  try {
    const baseUrl = tryGetApiBaseUrl();
    if (!baseUrl) {
      return NextResponse.json(
        { error: "API is not configured." },
        { status: 500 },
      );
    }

    const body = (await request.json()) as { email?: string; captcha_token?: string };
    const email = body.email?.trim().toLowerCase() ?? "";
    if (!email) {
      return NextResponse.json({ error: "Email is required." }, { status: 400 });
    }

    const response = await fetch(`${baseUrl}/api/forgot-password`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        email,
        captcha_token: body.captcha_token,
      }),
    });

    const payload = (await response.json()) as ForgotResponse;
    if (!response.ok) {
      const fallback =
        response.status >= 500
          ? "We could not send the reset email right now. Try again in a few minutes."
          : "Could not send reset link.";
      return NextResponse.json(
        { error: errorMessage(payload, fallback) },
        { status: response.status },
      );
    }

    return NextResponse.json({
      ok: true,
      message: payload.message ?? "Reset link sent.",
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not reach the API.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
