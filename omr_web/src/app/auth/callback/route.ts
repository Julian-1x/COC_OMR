import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import {
  API_TOKEN_COOKIE,
  apiTokenCookieOptions,
} from "@/lib/api/laravel-client";

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const token = searchParams.get("token");
  const verified = searchParams.get("verified");
  const next = searchParams.get("next") ?? "/dashboard";

  if (token && verified === "1") {
    const cookieStore = await cookies();
    cookieStore.set(API_TOKEN_COOKIE, token, apiTokenCookieOptions());
    const destination = new URL(next, origin);
    destination.searchParams.set("confirmed", "1");
    return NextResponse.redirect(destination.toString());
  }

  return NextResponse.redirect(`${origin}/login?error=confirm`);
}
