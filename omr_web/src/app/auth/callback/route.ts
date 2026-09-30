import { NextResponse } from "next/server";
import { clearApiTokenCookie, setApiTokenCookie } from "@/lib/api/laravel-client";

/**
 * Lands here after Laravel email verification (web platform).
 * Always clears any previous teacher session first — shared school phones often
 * still have another account's cookie when a new teacher taps Verify email.
 */
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const token = searchParams.get("token");
  const verified = searchParams.get("verified");
  const accessPending = searchParams.get("access_pending") === "1";
  const email = searchParams.get("email")?.trim() ?? "";
  const message = searchParams.get("message")?.trim() ?? "";
  const next = searchParams.get("next") ?? "/dashboard";

  const withEmail = (url: URL) => {
    if (email) url.searchParams.set("email", email);
    if (message) url.searchParams.set("verify_message", message);
    return url;
  };

  if (verified === "1" && accessPending) {
    const destination = withEmail(new URL("/login", origin));
    destination.searchParams.set("pending", "1");
    destination.searchParams.set("confirmed", "1");
    const response = NextResponse.redirect(destination.toString());
    clearApiTokenCookie(response.cookies);
    return response;
  }

  if (token && verified === "1") {
    // New account is approved — sign in as the verified teacher only (not the prior session).
    const destination = withEmail(new URL(next, origin));
    destination.searchParams.set("confirmed", "1");
    const response = NextResponse.redirect(destination.toString());
    clearApiTokenCookie(response.cookies);
    setApiTokenCookie(response.cookies, token);
    return response;
  }

  if (verified === "1") {
    // Verified but no session token yet — ask them to sign in with that email.
    const destination = withEmail(new URL("/login", origin));
    destination.searchParams.set("confirmed", "1");
    const response = NextResponse.redirect(destination.toString());
    clearApiTokenCookie(response.cookies);
    return response;
  }

  const destination = withEmail(new URL("/login", origin));
  destination.searchParams.set("error", "confirm");
  const response = NextResponse.redirect(destination.toString());
  clearApiTokenCookie(response.cookies);
  return response;
}
