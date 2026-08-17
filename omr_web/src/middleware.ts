import { NextResponse, type NextRequest } from "next/server";
import { API_TOKEN_COOKIE } from "@/lib/api/laravel-client";

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const isAuthPage = pathname.startsWith("/login") || pathname.startsWith("/auth");
  const isDashboard = pathname.startsWith("/dashboard");
  const hasToken = Boolean(request.cookies.get(API_TOKEN_COOKIE)?.value);

  if (!hasToken) {
    if (isDashboard) {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      return NextResponse.redirect(url);
    }
    return NextResponse.next({ request });
  }

  // Stale tokens after a DB reset must be able to reach login / signout / warming.
  if (
    pathname.startsWith("/auth/signout") ||
    pathname.startsWith("/warming")
  ) {
    return NextResponse.next({ request });
  }

  if (pathname === "/login" || pathname === "/") {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    return NextResponse.redirect(url);
  }

  if (isAuthPage) {
    return NextResponse.next({ request });
  }

  return NextResponse.next({ request });
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|coc_seal.png|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
