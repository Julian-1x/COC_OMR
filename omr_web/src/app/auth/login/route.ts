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

async function readJsonBody(response: Response): Promise<AuthResponse | null> {
  const text = await response.text();
  if (!text.trim()) {
    return null;
  }
  try {
    return JSON.parse(text) as AuthResponse;
  } catch {
    return null;
  }
}

function upstreamErrorMessage(
  response: Response,
  payload: AuthResponse | null,
  fallback: string,
): string {
  if (payload) {
    return authErrorMessage(payload, fallback);
  }
  if (response.status === 502 || response.status === 504) {
    return "School server timed out. Wait a minute and try again.";
  }
  if (response.status >= 500) {
    return "School server error. Try again in a minute.";
  }
  return fallback;
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

      const payload = await readJsonBody(response);
      if (!response.ok) {
        return NextResponse.json(
          { error: upstreamErrorMessage(response, payload, "Registration failed.") },
          { status: response.status },
        );
      }

      const needsEmailConfirmation = !payload?.user?.email_verified_at;
      if (!needsEmailConfirmation && payload.token) {
        const cookieStore = await cookies();
        cookieStore.set(API_TOKEN_COOKIE, payload.token, apiTokenCookieOptions());
      }

      return NextResponse.json({
        ok: true,
        needsEmailConfirmation,
        message: payload?.message,
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

    const payload = await readJsonBody(response);
    if (!response.ok || !payload?.token) {
      const unverified =
        payload?.user?.email_verified_at == null &&
        (payload?.message?.toLowerCase().includes('not confirmed') ||
          payload?.message?.toLowerCase().includes('not verified') ||
          payload?.errors?.email?.some((m) =>
            m.toLowerCase().includes('not confirmed') ||
            m.toLowerCase().includes('not verified'),
          ));
      if (unverified) {
        return NextResponse.json(
          {
            error:
              "This email has not been confirmed yet. Open the confirmation email, then sign in again.",
          },
          { status: 403 },
        );
      }
      return NextResponse.json(
        { error: upstreamErrorMessage(response, payload, "Sign in failed.") },
        { status: response.status || 400 },
      );
    }

    if (!payload) {
      return NextResponse.json({ error: "Sign in failed." }, { status: 500 });
    }

    if (!payload.user?.email_verified_at) {
      return NextResponse.json(
        {
          error:
            "This email has not been confirmed yet. Open the confirmation email, then sign in again.",
        },
        { status: 403 },
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
