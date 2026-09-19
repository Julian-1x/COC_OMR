import { NextResponse } from "next/server";
import { setApiTokenCookie } from "@/lib/api/laravel-client";

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const token = searchParams.get("token");
  const verified = searchParams.get("verified");
  const accessPending = searchParams.get("access_pending") === "1";
  const next = searchParams.get("next") ?? "/dashboard";

  if (verified === "1" && accessPending) {
    return NextResponse.redirect(`${origin}/login?pending=1&confirmed=1`);
  }

  if (token && verified === "1") {
    const destination = new URL(next, origin);
    destination.searchParams.set("confirmed", "1");
    const response = NextResponse.redirect(destination.toString());
    setApiTokenCookie(response.cookies, token);
    return response;
  }

  return NextResponse.redirect(`${origin}/login?error=confirm`);
}
