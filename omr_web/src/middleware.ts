import { NextResponse, type NextRequest } from "next/server";
import {
  API_TOKEN_COOKIE,
  clearApiTokenCookie,
  hasAuthResultQuery,
} from "@/lib/api/laravel-client";

/**
 * Soft cookie-presence gate only.
 * Real authorization is: httpOnly Sanctum cookie → BFF/server session → Laravel
 * teacher-owned rows / admin scope. Do not treat this middleware as full auth.
 */
export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const isAuthPage = pathname.startsWith("/login") || pathname.startsWith("/auth");
  const isDashboard = pathname.startsWith("/dashboard");
  const hasToken = Boolean(request.cookies.get(API_TOKEN_COOKIE)?.value);

  // Never treat static auth helper routes as "already signed in".
  if (
    pathname.startsWith("/auth/signout") ||
    pathname.startsWith("/auth/after-login") ||
    pathname.startsWith("/auth/callback") ||
    pathname.startsWith("/warming") ||
    pathname.startsWith("/api/")
  ) {
    return NextResponse.next({ request });
  }

  if (!hasToken) {
    if (isDashboard) {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      url.search = "";
      url.searchParams.set("next", pathname);
      return NextResponse.redirect(url);
    }
    return NextResponse.next({ request });
  }

  // Email verify / reset / transfer messages must show on /login even if another
  // teacher was already signed in on this browser (common on shared phones).
  if (pathname === "/login" && hasAuthResultQuery(request.nextUrl.searchParams)) {
    const response = NextResponse.next({ request });
    clearApiTokenCookie(response.cookies);
    return response;
  }

  if (pathname === "/login" || pathname === "/") {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    url.search = "";
    return NextResponse.redirect(url);
  }

  if (isAuthPage) {
    return NextResponse.next({ request });
  }

  const response = NextResponse.next({ request });
  if (isDashboard) {
    response.headers.set("Cache-Control", "private, no-store");
  }
  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|coc_seal.png|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
