import { cache } from "react";
import { redirect } from "next/navigation";
import {
  isAccessApproved,
  isSchoolAdmin,
  isSuperAdmin,
} from "@/lib/api/admin";
import {
  ApiClient,
  ApiError,
  ApiUser,
} from "@/lib/api/laravel-client";
import {
  createServerApiClient,
  getServerApiToken,
} from "@/lib/api/laravel-server";
import type { DbTeacherProfile } from "@/lib/types/database";
import { agentDebugLog } from "@/lib/debug-agent-log";

/**
 * One login check per page request. Layout and the page used to each wake
 * Render and call /me, which made every click feel slow.
 */
export const requireTeacherSession = cache(async (): Promise<{
  api: ApiClient;
  user: ApiUser;
  profile: DbTeacherProfile | null;
}> => {
  const token = await getServerApiToken();
  if (!token) {
    // #region agent log
    agentDebugLog(
      "session.ts:no-token",
      "dashboard requireTeacherSession missing cookie token",
      {},
      "B",
    );
    // #endregion
    redirect("/login?error=session&dbg=dash_no_cookie");
  }

  const api = createServerApiClient(token);
  // Brief retries: Neon free can take a few seconds after idle; one failure
  // used to bounce teachers warming ↔ dashboard forever.
  let lastError: unknown;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const { user } = await api.get<{ user: ApiUser }>("/me");
      if (!isAccessApproved(user.profile)) {
        // #region agent log
        agentDebugLog(
          "session.ts:not-approved",
          "dashboard /me ok but not approved",
          { accessStatus: user.profile?.access_status ?? null },
          "E",
        );
        // #endregion
        redirect("/auth/signout?next=/login&pending=1&dbg=dash_not_approved");
      }
      // #region agent log
      agentDebugLog(
        "session.ts:ok",
        "dashboard session ok",
        { attempt, hasProfile: Boolean(user.profile) },
        "B",
      );
      // #endregion
      return { api, user, profile: user.profile };
    } catch (error) {
      lastError = error;
      if (error instanceof ApiError && error.status === 401) {
        // #region agent log
        agentDebugLog(
          "session.ts:me-401",
          "dashboard /me 401",
          { attempt },
          "C",
        );
        // #endregion
        // Clear the cookie or middleware will bounce login ↔ dashboard forever
        // (common after a DB reset like Neon cutover).
        redirect("/auth/signout?next=/login&error=session&dbg=dash_me_401");
      }
      if (error instanceof ApiError && error.status === 403) {
        redirect("/auth/signout?next=/login&pending=1&dbg=dash_me_403");
      }
      if (attempt < 3) {
        await new Promise((resolve) => setTimeout(resolve, 1500 * attempt));
      }
    }
  }

  if (lastError instanceof ApiError && lastError.status === 401) {
    redirect("/auth/signout?next=/login&error=session&dbg=dash_me_401_final");
  }
  // Keep the session cookie — transient API/DB errors should not force logout.
  // /warming retries until /me succeeds (not only /up).
  redirect("/warming?dbg=dash_me_retry_exhausted");
});

export async function requireAdminSession(): Promise<{
  api: ApiClient;
  user: ApiUser;
  profile: DbTeacherProfile;
}> {
  const session = await requireTeacherSession();
  if (!isSchoolAdmin(session.profile, session.user)) {
    redirect("/dashboard");
  }
  if (!session.profile) {
    redirect("/dashboard");
  }
  return {
    api: session.api,
    user: session.user,
    profile: session.profile,
  };
}

export async function requireSuperAdminSession(): Promise<{
  api: ApiClient;
  user: ApiUser;
  profile: DbTeacherProfile;
}> {
  const session = await requireAdminSession();
  if (!isSuperAdmin(session.profile, session.user)) {
    redirect("/dashboard/admin");
  }
  return session;
}
