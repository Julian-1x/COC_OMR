import { NextResponse } from "next/server";
import { ApiError } from "@/lib/api/laravel-client";
import { isAccessApproved } from "@/lib/api/admin";
import {
  createServerApiClient,
  getServerApiToken,
} from "@/lib/api/laravel-server";

export const dynamic = "force-dynamic";

/**
 * After /auth/login sets the httpOnly cookie, the browser lands here.
 * Verifies the cookie is readable server-side and /api/me accepts the token
 * before opening the desk — avoids a silent bounce back to /login.
 */
export async function GET(request: Request) {
  const origin = new URL(request.url).origin;
  const token = await getServerApiToken();

  if (!token) {
    return NextResponse.redirect(
      `${origin}/login?error=session`,
      { status: 303 },
    );
  }

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

    return NextResponse.redirect(`${origin}/dashboard`, { status: 303 });
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      return NextResponse.redirect(
        `${origin}/auth/signout?next=/login&error=session`,
        { status: 303 },
      );
    }
    if (error instanceof ApiError && error.status === 403) {
      return NextResponse.redirect(
        `${origin}/auth/signout?next=/login&pending=1`,
        { status: 303 },
      );
    }
    // API/DB briefly unavailable — keep cookie, show warming.
    return NextResponse.redirect(`${origin}/warming`, { status: 303 });
  }
}
