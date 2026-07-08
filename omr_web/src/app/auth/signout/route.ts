import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { API_TOKEN_COOKIE } from "@/lib/api/laravel-client";
import { tryGetApiBaseUrl } from "@/lib/api/env";

export async function POST() {
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
      // Best-effort remote logout.
    }
  }

  cookieStore.delete(API_TOKEN_COOKIE);
  return NextResponse.json({ ok: true });
}
