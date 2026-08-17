import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import {
  API_TOKEN_COOKIE,
  apiTokenCookieOptions,
} from "@/lib/api/laravel-client";
import { tryGetApiBaseUrl } from "@/lib/api/env";
import { fetchAuthUpstream, wakeSchoolApi } from "@/lib/api/wake-api";
import { COC_SCHOOL_NAME, isCocDepartment } from "@/lib/coc-school";
import { normalizePersonName } from "@/lib/person-name";

type AuthResponse = {
  token?: string;
  user?: {
    email_verified_at?: string | null;
    profile?: {
      access_status?: string | null;
    };
  };
  message?: string;
  access_status?: string;
  access_pending?: boolean;
  errors?: Record<string, string[]>;
};

function authErrorMessage(payload: AuthResponse | null, fallback: string): string {
  if (payload?.message) return payload.message;
  const first = payload?.errors ? Object.values(payload.errors)[0]?.[0] : undefined;
  return first ?? fallback;
}

function upstreamErrorMessage(
  response: Response,
  payload: AuthResponse | null,
  fallback: string,
  rawBody?: string,
): string {
  if (payload) {
    return authErrorMessage(payload, fallback);
  }
  if (response.status === 502 || response.status === 504) {
    return "School server is waking up. Wait about a minute, then try again.";
  }
  if (response.status >= 500) {
    return "School server error. Try again in a minute.";
  }
  const snippet = (rawBody ?? "").replace(/\s+/g, " ").trim().slice(0, 80).toLowerCase();
  if (snippet.startsWith("an error") || snippet.includes("<html")) {
    return "School server is not responding with a usable reply. Confirm the API is running, then try again.";
  }
  return fallback;
}

  return fallback;
}

async function readUpstream(
  response: Response,
): Promise<{ payload: AuthResponse | null; rawBody: string }> {
  const rawBody = await response.text();
  if (!rawBody.trim()) {
    return { payload: null, rawBody };
  }
  try {
    return { payload: JSON.parse(rawBody) as AuthResponse, rawBody };
  } catch {
    return { payload: null, rawBody };
  }
}

function friendlyCatchMessage(error: unknown): string {
  if (error instanceof Error) {
    const lower = error.message.toLowerCase();
    if (
      error.name === "AbortError" ||
      lower.includes("aborted") ||
      lower.includes("timeout")
    ) {
      return "School server is waking up. Wait about a minute, then try again.";
    }
    if (
      lower.includes("fetch failed") ||
      lower.includes("econnrefused") ||
      lower.includes("enotfound") ||
      lower.includes("network")
    ) {
      return "Could not reach the school API. Check API_BASE_URL and that the campus server is online.";
    }
    return error.message;
  }
  return "Could not reach the API. Check your internet.";
}

export async function POST(request: Request) {
  try {
    const baseUrl = tryGetApiBaseUrl();
    if (!baseUrl) {
      return NextResponse.json(
        { error: "API is not configured. Check omr_web/.env.local and restart npm run dev." },
        { status: 500 },
      );
    }

    const body = (await request.json()) as {
      mode?: "login" | "register";
      email?: string;
      password?: string;
      name?: string;
      school?: string;
      department?: string;
    };

    const mode = body.mode ?? "login";
    const email = body.email?.trim().toLowerCase() ?? "";
    const password = body.password ?? "";

    if (!email || !password) {
      return NextResponse.json({ error: "Email and password are required." }, { status: 400 });
    }

    await wakeSchoolApi(baseUrl, { attempts: 2, delayMs: 1500 });

    const jsonHeaders = {
      "Content-Type": "application/json",
      Accept: "application/json",
    };

    if (mode === "register") {
      const name = normalizePersonName(body.name?.trim() ?? "");
      const department = body.department?.trim().toUpperCase() ?? "";
      if (!name) {
        return NextResponse.json(
          { error: "Enter your full name (first name, then last name)." },
          { status: 400 },
        );
      }
      if (!isCocDepartment(department)) {
        return NextResponse.json(
          { error: "Select a valid COC department (COE, SCCJ, CMA, CIT, CEA, or CAHS)." },
          { status: 400 },
        );
      }

      const response = await fetchAuthUpstream(`${baseUrl}/api/register`, {
        method: "POST",
        headers: jsonHeaders,
        body: JSON.stringify({
          email,
          password,
          password_confirmation: password,
          full_name: name,
          school: COC_SCHOOL_NAME,
          department,
        }),
      });

      const { payload, rawBody } = await readUpstream(response);
      if (!response.ok) {
        return NextResponse.json(
          {
            error: upstreamErrorMessage(
              response,
              payload,
              "Registration failed.",
              rawBody,
            ),
          },
          { status: response.status },
        );
      }

      const needsEmailConfirmation = !payload?.user?.email_verified_at;
      const accessPending =
        payload?.access_pending === true ||
        payload?.access_status === "pending" ||
        payload?.user?.profile?.access_status === "pending";

      if (!needsEmailConfirmation && payload?.token) {
        const cookieStore = await cookies();
        cookieStore.set(API_TOKEN_COOKIE, payload.token, apiTokenCookieOptions());
      }

      return NextResponse.json({
        ok: true,
        needsEmailConfirmation,
        accessPending: !needsEmailConfirmation && accessPending,
        message: payload?.message,
      });
    }

    const response = await fetchAuthUpstream(`${baseUrl}/api/login`, {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({
        email,
        password,
        device_name: "web",
      }),
    });

    const { payload, rawBody } = await readUpstream(response);
    if (!response.ok || !payload?.token) {
      const message = upstreamErrorMessage(
        response,
        payload,
        "Sign in failed.",
        rawBody,
      );
      const lower = message.toLowerCase();
      const unverified =
        lower.includes("not confirmed") || lower.includes("not verified");
      const pendingApproval =
        lower.includes("waiting for school admin") ||
        lower.includes("admin approval") ||
        lower.includes("revoked by your school admin");

      if (unverified) {
        return NextResponse.json(
          {
            error:
              "This email has not been confirmed yet. Open the confirmation email, then sign in again.",
          },
          { status: 403 },
        );
      }
      if (pendingApproval) {
        return NextResponse.json(
          {
            error: message,
            accessPending: true,
          },
          { status: 403 },
        );
      }
      return NextResponse.json(
        { error: message },
        { status: response.status || 400 },
      );
    }

    if (!payload.user?.email_verified_at) {
      return NextResponse.json(
        {
          error:
            "This email has not been confirmed yet. Open the confirmation email, then sign in again.",
        },
        { status: 403 },
      );
    }

    const cookieStore = await cookies();
    cookieStore.set(API_TOKEN_COOKIE, payload.token, apiTokenCookieOptions());

    return NextResponse.json({ ok: true });
  } catch (error) {
    return NextResponse.json({ error: friendlyCatchMessage(error) }, { status: 500 });
  }
}
