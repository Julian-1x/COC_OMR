import { NextResponse } from "next/server";
import { isAccessApproved } from "@/lib/api/admin";
import { getApiBaseUrl } from "@/lib/api/env";
import { ApiError, setApiTokenCookie } from "@/lib/api/laravel-client";
import { agentDebugLog } from "@/lib/debug-agent-log";
import { unsealLoginHandoff } from "@/lib/api/login-handoff";
import {
  createServerApiClient,
  getServerApiToken,
} from "@/lib/api/laravel-server";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/**
 * Set-Cookie on 303 redirects is unreliable in some browsers (including
 * embedded webviews). A 200 HTML bridge applies the cookie, then navigates.
 */
function htmlBridgeToDashboard(token: string) {
  // #region agent log
  agentDebugLog(
    "after-login/route.ts:bridge",
    "returning HTML cookie bridge to /dashboard",
    { tokenLen: token.length, hasPipe: token.includes("|") },
    "B",
  );
  // #endregion
  const response = new NextResponse(
    `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8"/>
    <title>Opening desk…</title>
    <meta http-equiv="refresh" content="0;url=/dashboard"/>
    <script>location.replace("/dashboard");</script>
  </head>
  <body>
    <p style="font-family:system-ui,sans-serif;padding:2rem">Opening your desk…</p>
  </body>
</html>`,
    {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    },
  );
  setApiTokenCookie(response.cookies, token);
  return response;
}

async function openDashboard(origin: string, token: string) {
  let apiBase = "";
  try {
    apiBase = getApiBaseUrl();
  } catch {
    apiBase = "";
  }

  // #region agent log
  try {
    if (apiBase) {
      const probe = await fetch(`${apiBase}/api/health/auth-probe`, {
        method: "GET",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${token}`,
          "X-COC-Api-Token": token,
        },
        cache: "no-store",
      });
      const probeBody = (await probe.json().catch(() => null)) as Record<
        string,
        unknown
      > | null;
      agentDebugLog(
        "after-login/route.ts:auth-probe",
        "API auth-probe before /me",
        {
          status: probe.status,
          apiHost: (() => {
            try {
              return new URL(apiBase).host;
            } catch {
              return "invalid";
            }
          })(),
          has_authorization_header: probeBody?.has_authorization_header ?? null,
          has_bearer: probeBody?.has_bearer ?? null,
          bearer_len: probeBody?.bearer_len ?? null,
          has_alt_token_header: probeBody?.has_alt_token_header ?? null,
          server_has_http_authorization:
            probeBody?.server_has_http_authorization ?? null,
          tokenIdLen: token.split("|")[0]?.length ?? 0,
        },
        "F",
      );
    }
  } catch (probeError) {
    agentDebugLog(
      "after-login/route.ts:auth-probe-error",
      "auth-probe request failed",
      {
        name: probeError instanceof Error ? probeError.name : "unknown",
        message:
          probeError instanceof Error
            ? probeError.message.slice(0, 80)
            : "unknown",
      },
      "F",
    );
  }
  // #endregion

  try {
    const api = createServerApiClient(token);
    const { user } = await api.get<{
      user: { profile: Parameters<typeof isAccessApproved>[0] };
    }>("/me");

    const approved = isAccessApproved(user.profile);
    // #region agent log
    agentDebugLog(
      "after-login/route.ts:me-ok",
      "/me succeeded after handoff",
      {
        approved,
        hasProfile: Boolean(user.profile),
        accessStatus: user.profile?.access_status ?? null,
      },
      "C",
    );
    // #endregion

    if (!approved) {
      return NextResponse.redirect(
        `${origin}/auth/signout?next=/login&pending=1&dbg=not_approved`,
        { status: 303 },
      );
    }

    return htmlBridgeToDashboard(token);
  } catch (error) {
    const status = error instanceof ApiError ? error.status : 0;
    const message =
      error instanceof Error ? error.message.slice(0, 120) : "unknown";
    // #region agent log
    agentDebugLog(
      "after-login/route.ts:me-fail",
      "/me failed after handoff",
      { status, name: error instanceof Error ? error.name : "unknown", message },
      "C",
    );
    // #endregion
    if (error instanceof ApiError && error.status === 401) {
      return NextResponse.redirect(
        `${origin}/login?error=rejected&dbg=me_401`,
        { status: 303 },
      );
    }
    if (error instanceof ApiError && error.status === 403) {
      return NextResponse.redirect(
        `${origin}/auth/signout?next=/login&pending=1&dbg=me_403`,
        { status: 303 },
      );
    }
    const warming = NextResponse.redirect(
      `${origin}/warming?dbg=me_other`,
      { status: 303 },
    );
    setApiTokenCookie(warming.cookies, token);
    return warming;
  }
}

/**
 * Preferred path: form POST from login with a sealed one-time handoff.
 */
export async function POST(request: Request) {
  const origin = new URL(request.url).origin;
  const form = await request.formData();
  const sealed = String(form.get("handoff") ?? "").trim();
  const token = sealed ? unsealLoginHandoff(sealed) : null;

  // #region agent log
  agentDebugLog(
    "after-login/route.ts:POST",
    "handoff POST received",
    {
      sealedLen: sealed.length,
      unsealed: Boolean(token),
      tokenLen: token?.length ?? 0,
    },
    "A",
  );
  // #endregion

  if (!token) {
    return NextResponse.redirect(
      `${origin}/login?error=session&dbg=unseal_fail`,
      { status: 303 },
    );
  }

  return openDashboard(origin, token);
}

/** Fallback if a session cookie was already stored by /auth/login. */
export async function GET(request: Request) {
  const origin = new URL(request.url).origin;
  const token = await getServerApiToken();

  // #region agent log
  agentDebugLog(
    "after-login/route.ts:GET",
    "after-login GET fallback",
    { hasToken: Boolean(token), tokenLen: token?.length ?? 0 },
    "D",
  );
  // #endregion

  if (!token) {
    return NextResponse.redirect(
      `${origin}/login?error=session&dbg=no_cookie_get`,
      { status: 303 },
    );
  }

  return openDashboard(origin, token);
}
