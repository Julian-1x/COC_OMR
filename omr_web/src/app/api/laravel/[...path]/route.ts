import { cookies } from "next/headers";
import { NextResponse, type NextRequest } from "next/server";
import {
  API_TOKEN_COOKIE,
  decodeApiTokenCookie,
} from "@/lib/api/laravel-client";
import { tryGetApiBaseUrl } from "@/lib/api/env";

export const dynamic = "force-dynamic";

const ALLOWED_METHODS = new Set(["GET", "POST", "PUT", "PATCH", "DELETE"]);

/**
 * Same-origin BFF: browser calls /api/laravel/* ; this route attaches the
 * httpOnly Sanctum cookie and forwards to the school Laravel API.
 * Keeps the bearer token out of document.cookie / XSS reach.
 */
async function proxy(request: NextRequest, pathParts: string[]) {
  const method = request.method.toUpperCase();
  if (!ALLOWED_METHODS.has(method)) {
    return NextResponse.json({ message: "Method not allowed." }, { status: 405 });
  }

  const baseUrl = tryGetApiBaseUrl();
  if (!baseUrl) {
    return NextResponse.json(
      { message: "API is not configured. Set API_BASE_URL on the web host." },
      { status: 503 },
    );
  }

  const cookieStore = await cookies();
  const token = decodeApiTokenCookie(cookieStore.get(API_TOKEN_COOKIE)?.value);
  if (!token) {
    return NextResponse.json({ message: "Sign in required." }, { status: 401 });
  }

  const suffix = pathParts.map(encodeURIComponent).join("/");
  const upstream = new URL(`${baseUrl}/api/${suffix}`);
  request.nextUrl.searchParams.forEach((value, key) => {
    upstream.searchParams.set(key, value);
  });

  const headers: Record<string, string> = {
    Accept: "application/json",
    Authorization: `Bearer ${token}`,
  };
  if (baseUrl.includes("loca.lt")) {
    headers["Bypass-Tunnel-Reminder"] = "true";
  }

  let body: string | undefined;
  if (method !== "GET" && method !== "DELETE") {
    const text = await request.text();
    if (text) {
      body = text;
      headers["Content-Type"] = request.headers.get("content-type") ?? "application/json";
    }
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 25_000);
  let response: Response;
  try {
    response = await fetch(upstream.toString(), {
      method,
      headers,
      body,
      cache: "no-store",
      signal: controller.signal,
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      return NextResponse.json(
        { message: "The school server took too long to respond." },
        { status: 504 },
      );
    }
    return NextResponse.json(
      {
        message:
          "Could not reach the school API. Confirm the campus server is online, then try again.",
      },
      { status: 502 },
    );
  } finally {
    clearTimeout(timer);
  }

  const responseText = await response.text();
  const contentType = response.headers.get("content-type") ?? "application/json";
  return new NextResponse(responseText, {
    status: response.status,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "no-store",
    },
  });
}

type Ctx = { params: Promise<{ path: string[] }> };

export async function GET(request: NextRequest, ctx: Ctx) {
  const { path } = await ctx.params;
  return proxy(request, path ?? []);
}

export async function POST(request: NextRequest, ctx: Ctx) {
  const { path } = await ctx.params;
  return proxy(request, path ?? []);
}

export async function PUT(request: NextRequest, ctx: Ctx) {
  const { path } = await ctx.params;
  return proxy(request, path ?? []);
}

export async function PATCH(request: NextRequest, ctx: Ctx) {
  const { path } = await ctx.params;
  return proxy(request, path ?? []);
}

export async function DELETE(request: NextRequest, ctx: Ctx) {
  const { path } = await ctx.params;
  return proxy(request, path ?? []);
}
