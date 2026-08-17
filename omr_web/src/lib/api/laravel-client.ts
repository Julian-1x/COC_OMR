import { getPublicApiBaseUrl } from "@/lib/api/env";
import type { DbTeacherProfile } from "@/lib/types/database";

export const API_TOKEN_COOKIE = "coc_api_token";

export type ApiUser = {
  id: string;
  email: string;
  email_verified_at: string | null;
  profile: DbTeacherProfile | null;
};

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body?: unknown,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

type RequestOptions = {
  params?: Record<string, string | number | boolean | undefined | null>;
};

export class ApiClient {
  constructor(
    private readonly token: string,
    private readonly baseUrl: string,
  ) {}

  async get<T>(path: string, options?: RequestOptions): Promise<T> {
    return this.request<T>("GET", path, undefined, options);
  }

  async post<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return this.request<T>("POST", path, body, options);
  }

  async put<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return this.request<T>("PUT", path, body, options);
  }

  async patch<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return this.request<T>("PATCH", path, body, options);
  }

  async delete<T>(path: string, options?: RequestOptions): Promise<T> {
    return this.request<T>("DELETE", path, undefined, options);
  }

  private buildUrl(path: string, options?: RequestOptions): string {
    const normalized = path.startsWith("/") ? path : `/${path}`;
    const url = new URL(`${this.baseUrl}/api${normalized}`);
    if (options?.params) {
      for (const [key, value] of Object.entries(options.params)) {
        if (value === undefined || value === null || value === "") continue;
        url.searchParams.set(key, String(value));
      }
    }
    return url.toString();
  }

  private async request<T>(
    method: string,
    path: string,
    body?: unknown,
    options?: RequestOptions,
  ): Promise<T> {
    const headers: Record<string, string> = {
      Accept: "application/json",
    };

    if (this.token) {
      headers.Authorization = `Bearer ${this.token}`;
    }

    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
    }

    if (this.baseUrl.includes("loca.lt")) {
      headers["Bypass-Tunnel-Reminder"] = "true";
    }

    const response = await fetch(this.buildUrl(path, options), {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      cache: "no-store",
    });

    const text = await response.text();
    const payload = text ? safeJsonParse(text) : null;

    if (!response.ok) {
      const message = extractErrorMessage(payload) ?? `Request failed (${response.status}).`;
      throw new ApiError(message, response.status, payload);
    }

    return payload as T;
  }
}

function safeJsonParse(text: string): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return text;
  }
}

function extractErrorMessage(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") return null;
  const record = payload as Record<string, unknown>;
  if (typeof record.message === "string" && record.message.trim()) {
    const msg = record.message.trim();
    if (msg.toLowerCase().includes("csrf")) {
      return "Could not save — please sign out, sign in again, and retry. If this keeps happening, the school API may need an update.";
    }
    return msg;
  }
  const errors = record.errors;
  if (errors && typeof errors === "object") {
    const first = Object.values(errors as Record<string, unknown>)[0];
    if (Array.isArray(first) && typeof first[0] === "string") {
      return first[0];
    }
  }
  return null;
}

/** Web-only session lifetime. Mobile app tokens are not time-limited. */
const WEB_SESSION_MAX_AGE_SECONDS = (() => {
  const raw = process.env.WEB_SESSION_MAX_AGE_SECONDS?.trim();
  if (raw) {
    const parsed = Number.parseInt(raw, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return 60 * 60 * 24 * 7;
})();

export function apiTokenCookieOptions(): {
  path: string;
  sameSite: "lax";
  secure: boolean;
  maxAge: number;
} {
  return {
    path: "/",
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    maxAge: WEB_SESSION_MAX_AGE_SECONDS,
  };
}


function readBrowserToken(): string {
  if (typeof document === "undefined") {
    throw new Error("Browser API client is only available in the browser.");
  }
  const match = document.cookie.match(new RegExp(`(?:^|; )${API_TOKEN_COOKIE}=([^;]*)`));
  const token = match?.[1] ? decodeURIComponent(match[1]) : "";
  if (!token) {
    throw new Error("Sign in required.");
  }
  return token;
}

export function createBrowserApiClient(): ApiClient {
  return new ApiClient(readBrowserToken(), getPublicApiBaseUrl());
}
