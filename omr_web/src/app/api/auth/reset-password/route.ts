import { NextResponse } from "next/server";
import { tryGetApiBaseUrl } from "@/lib/api/env";

type ResetResponse = {
  message?: string;
  errors?: Record<string, string[]>;
};

function errorMessage(payload: ResetResponse | null, fallback: string): string {
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

    const body = (await request.json()) as {
      email?: string;
      token?: string;
      password?: string;
      password_confirmation?: string;
    };

    const email = body.email?.trim().toLowerCase() ?? "";
    const token = body.token?.trim() ?? "";
    const password = body.password ?? "";
    const passwordConfirmation = body.password_confirmation ?? password;

    if (!email || !token || !password) {
      return NextResponse.json(
        { error: "Email, reset token, and new password are required." },
        { status: 400 },
      );
    }

    const response = await fetch(`${baseUrl}/api/reset-password`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        email,
        token,
        password,
        password_confirmation: passwordConfirmation,
      }),
    });

    const payload = (await response.json()) as ResetResponse;
    if (!response.ok) {
      return NextResponse.json(
        { error: errorMessage(payload, "Password reset failed.") },
        { status: response.status },
      );
    }

    return NextResponse.json({
      ok: true,
      message: payload.message ?? "Password reset successfully.",
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not reach the API.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
