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
  return decodeApiTokenCookie(raw);
}

export function createServerApiClient(token: string): ApiClient {
  return new ApiClient(token, getApiBaseUrl());
}

export async function createAuthenticatedServerApiClient(): Promise<ApiClient | null> {
  const token = await getServerApiToken();
  if (!token) return null;
  return createServerApiClient(token);
}
