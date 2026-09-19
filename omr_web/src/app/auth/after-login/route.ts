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

/**
 * Set-Cookie on 303 redirects is unreliable in some browsers (including
 * embedded webviews). A 200 HTML bridge applies the cookie, then navigates.
 */
function htmlBridgeToDashboard(token: string) {
  const response = new NextResponse(
    `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8"/>
    <title>Opening desk…</title>
    <meta http-equiv="refresh" content="0;url=/dashboard"/>
    <script>location.replace("/dashboard");</script>
  </head>
  <body>
    <p style="font-family:system-ui,sans-serif;padding:2rem">Opening your desk…</p>
  </body>
</html>`,
    {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  );
  setApiTokenCookie(response.cookies, token);
  return response;
}

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

    return htmlBridgeToDashboard(token);
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
    const warming = NextResponse.redirect(`${origin}/warming`, { status: 303 });
    setApiTokenCookie(warming.cookies, token);
    return warming;
  }
}

/**
 * Preferred path: form POST from login with a sealed one-time handoff.
 */
export async function POST(request: Request) {
  const origin = new URL(request.url).origin;
  const form = await request.formData();
  const sealed = String(form.get("handoff") ?? "").trim();
  const token = sealed ? unsealLoginHandoff(sealed) : null;

  if (!token) {
    return NextResponse.redirect(`${origin}/login?error=session`, {
      status: 303,
    });
  }

  return openDashboard(origin, token);
}

/** Fallback if a session cookie was already stored by /auth/login. */
export async function GET(request: Request) {
  const origin = new URL(request.url).origin;
  const token = await getServerApiToken();

  if (!token) {
    return NextResponse.redirect(`${origin}/login?error=session`, {
      status: 303,
    });
  }

  return openDashboard(origin, token);
}
