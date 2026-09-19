import { NextResponse } from "next/server";
import { isAccessApproved } from "@/lib/api/admin";
import { ApiError, setApiTokenCookie } from "@/lib/api/laravel-client";
import { unsealLoginHandoff } from "@/lib/api/login-handoff";
import {
  createServerApiClient,
  getServerApiToken,
} from "@/lib/api/laravel-server";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

async function openDashboard(origin: string, token: string) {
  try {
    const api = createServerApiClient(token);
    const { user } = await api.get<{
      user: { profile: Parameters<typeof isAccessApproved>[0] };
    }>("/me");

    if (!isAccessApproved(user.profile)) {
      return NextResponse.redirect(
        `${origin}/auth/signout?next=/login&pending=1`,
        { status: 303 },
      );
    }

    const response = NextResponse.redirect(`${origin}/dashboard`, { status: 303 });
    setApiTokenCookie(response.cookies, token);
    return response;
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      return NextResponse.redirect(
        `${origin}/login?error=rejected`,
        { status: 303 },
      );
    }
    if (error instanceof ApiError && error.status === 403) {
      return NextResponse.redirect(
        `${origin}/auth/signout?next=/login&pending=1`,
        { status: 303 },
      );
    }
    // Keep any cookie we can set and let warming retry.
    const warming = NextResponse.redirect(`${origin}/warming`, { status: 303 });
    setApiTokenCookie(warming.cookies, token);
    return warming;
  }
}

/**
 * Preferred path: form POST from login with a sealed one-time handoff.
 * Set-Cookie on a document navigation is reliable; fetch() Set-Cookie is not.
 */
export async function POST(request: Request) {
  const origin = new URL(request.url).origin;
  const form = await request.formData();
  const sealed = String(form.get("handoff") ?? "").trim();
  const token = sealed ? unsealLoginHandoff(sealed) : null;

  if (!token) {
    return NextResponse.redirect(`${origin}/login?error=session`, { status: 303 });
  }

  return openDashboard(origin, token);
}

/** Fallback if a session cookie was already stored by /auth/login. */
export async function GET(request: Request) {
  const origin = new URL(request.url).origin;
  const token = await getServerApiToken();

  if (!token) {
    return NextResponse.redirect(`${origin}/login?error=session`, { status: 303 });
  }

  return openDashboard(origin, token);
}
