import { cookies } from "next/headers";
import { getApiBaseUrl } from "@/lib/api/env";
import { ApiClient, API_TOKEN_COOKIE } from "@/lib/api/laravel-client";

export { API_TOKEN_COOKIE, apiTokenCookieOptions } from "@/lib/api/laravel-client";

export async function getServerApiToken(): Promise<string | null> {
  const cookieStore = await cookies();
  return cookieStore.get(API_TOKEN_COOKIE)?.value ?? null;
}

export function createServerApiClient(token: string): ApiClient {
  return new ApiClient(token, getApiBaseUrl());
}

export async function createAuthenticatedServerApiClient(): Promise<ApiClient | null> {
  const token = await getServerApiToken();
  if (!token) return null;
  return createServerApiClient(token);
}
