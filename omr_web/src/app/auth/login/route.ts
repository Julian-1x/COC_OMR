import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import {
  API_TOKEN_COOKIE,
  apiTokenCookieOptions,
} from "@/lib/api/laravel-client";
import { tryGetApiBaseUrl } from "@/lib/api/env";

type AuthResponse = {
  token?: string;
  user?: {
    email_verified_at?: string | null;
  };
  message?: string;
  errors?: Record<string, string[]>;
};

function authErrorMessage(payload: AuthResponse | null, fallback: string): string {
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

    const body = (await request.json()) as {
      mode?: "login" | "register";
      email?: string;
      password?: string;
      name?: string;
      school?: string;
    };

    const mode = body.mode ?? "login";
    const email = body.email?.trim().toLowerCase() ?? "";
    const password = body.password ?? "";

    if (!email || !password) {
      return NextResponse.json({ error: "Email and password are required." }, { status: 400 });
    }

    if (mode === "register") {
      const name = body.name?.trim() ?? "";
      const school = body.school?.trim() ?? "";
      if (!name || !school) {
        return NextResponse.json(
          { error: "Name and school are required for registration." },
          { status: 400 },
        );
      }

      const response = await fetch(`${baseUrl}/api/register`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          email,
          password,
          password_confirmation: password,
          full_name: name,
          school,
        }),
      });

      const payload = (await response.json()) as AuthResponse;
      if (!response.ok) {
        return NextResponse.json(
          { error: authErrorMessage(payload, "Registration failed.") },
          { status: response.status },
        );
      }

      const needsEmailConfirmation = !payload.user?.email_verified_at;
      if (!needsEmailConfirmation && payload.token) {
        const cookieStore = await cookies();
        cookieStore.set(API_TOKEN_COOKIE, payload.token, apiTokenCookieOptions());
      }

      return NextResponse.json({
        ok: true,
        needsEmailConfirmation,
      });
    }

    const response = await fetch(`${baseUrl}/api/login`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        email,
        password,
        device_name: "web",
      }),
    });

    const payload = (await response.json()) as AuthResponse;
    if (!response.ok || !payload.token) {
      return NextResponse.json(
        { error: authErrorMessage(payload, "Sign in failed.") },
        { status: response.status || 400 },
      );
    }

    const cookieStore = await cookies();
    cookieStore.set(API_TOKEN_COOKIE, payload.token, apiTokenCookieOptions());

    return NextResponse.json({ ok: true });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Could not reach the API. Check your internet.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
