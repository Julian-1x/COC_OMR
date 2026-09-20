import { cookies } from "next/headers";
import { getApiBaseUrl } from "@/lib/api/env";
import {
  ApiClient,
  API_TOKEN_COOKIE,
  decodeApiTokenCookie,
} from "@/lib/api/laravel-client";

export {
  API_TOKEN_COOKIE,
  apiTokenCookieOptions,
  decodeApiTokenCookie,
  encodeApiTokenCookie,
  setApiTokenCookie,
} from "@/lib/api/laravel-client";

export async function getServerApiToken(): Promise<string | null> {
  const cookieStore = await cookies();
  const raw = cookieStore.get(API_TOKEN_COOKIE)?.value ?? null;
  const token = decodeApiTokenCookie(raw);
  // #region agent log
  const { agentDebugLog } = await import("@/lib/debug-agent-log");
  agentDebugLog(
    "laravel-server.ts:getServerApiToken",
    "read session cookie",
    {
      hasRaw: Boolean(raw),
      rawLen: raw?.length ?? 0,
      decoded: Boolean(token),
      decodedHasPipe: Boolean(token?.includes("|")),
    },
    "B",
  );
  // #endregion
  return token;
}

export function createServerApiClient(token: string): ApiClient {
  return new ApiClient(token, getApiBaseUrl());
}

export async function createAuthenticatedServerApiClient(): Promise<ApiClient | null> {
  const token = await getServerApiToken();
  if (!token) return null;
  return createServerApiClient(token);
}
