import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { API_TOKEN_COOKIE } from "@/lib/api/laravel-client";
import { tryGetApiBaseUrl } from "@/lib/api/env";

async function clearSessionCookie() {
  const cookieStore = await cookies();
  const token = cookieStore.get(API_TOKEN_COOKIE)?.value;
  const baseUrl = tryGetApiBaseUrl();

  if (token && baseUrl) {
    try {
      await fetch(`${baseUrl}/api/logout`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
        },
      });
    } catch {
      // Best-effort remote logout — token may already be invalid after a DB reset.
    }
  }

  cookieStore.delete(API_TOKEN_COOKIE);
}

/** Browser navigation: clear stale cookie then go to login (breaks redirect loops). */
export async function GET(request: Request) {
  await clearSessionCookie();

  const url = new URL(request.url);
  const nextPath = url.searchParams.get("next") || "/login";
  const destination = new URL(nextPath, url.origin);
  // Preserve pending / error query flags from callers.
  for (const key of ["pending", "error", "confirmed", "reset"] as const) {
    const value = url.searchParams.get(key);
    if (value) {
      destination.searchParams.set(key, value);
    }
  }

  const response = NextResponse.redirect(destination);
  response.cookies.set(API_TOKEN_COOKIE, "", {
    path: "/",
    maxAge: 0,
  });
  return response;
}

export async function POST() {
  await clearSessionCookie();
  const response = NextResponse.json({ ok: true });
  response.cookies.set(API_TOKEN_COOKIE, "", {
    path: "/",
    maxAge: 0,
  });
  return response;
}
