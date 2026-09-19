import type { DbTeacherProfile } from "@/lib/types/database";

export const API_TOKEN_COOKIE = "coc_api_token";

/**
 * Sanctum plain-text tokens contain `|`. Store them base64url-encoded so
 * proxies/cookie parsers cannot truncate or alter the value.
 * Raw `id|hash` values are still accepted for older sessions.
 */
export function encodeApiTokenCookie(token: string): string {
  const trimmed = token.trim();
  if (!trimmed) return trimmed;
  if (typeof Buffer !== "undefined") {
    return Buffer.from(trimmed, "utf8").toString("base64url");
  }
  const bytes = new TextEncoder().encode(trimmed);
  let binary = "";
  bytes.forEach((b) => {
    binary += String.fromCharCode(b);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function decodeApiTokenCookie(value: string | undefined | null): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  // Legacy unencoded Sanctum token.
  if (trimmed.includes("|")) return trimmed;
  try {
    if (typeof Buffer !== "undefined") {
      const decoded = Buffer.from(trimmed, "base64url").toString("utf8");
      return decoded.includes("|") ? decoded : trimmed;
    }
    const padded = trimmed.replace(/-/g, "+").replace(/_/g, "/");
    const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
    const binary = atob(padded + pad);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    const decoded = new TextDecoder().decode(bytes);
    return decoded.includes("|") ? decoded : trimmed;
  } catch {
    return trimmed;
  }
}

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

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20_000);
    let response: Response;
    try {
      response = await fetch(this.buildUrl(path, options), {
        method,
        headers,
        body: body !== undefined ? JSON.stringify(body) : undefined,
        cache: "no-store",
        signal: controller.signal,
      });
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        throw new ApiError("The school server took too long to respond.", 504);
      }
      throw error;
    } finally {
      clearTimeout(timer);
    }

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
  httpOnly: boolean;
  maxAge: number;
} {
  return {
    path: "/",
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    // Token must not be readable by page JS (XSS). Browser calls go through /api/laravel.
    httpOnly: true,
    maxAge: WEB_SESSION_MAX_AGE_SECONDS,
  };
}

/** Set the Sanctum bearer on a NextResponse (preferred) or cookie store. */
export function setApiTokenCookie(
  target: { set: (name: string, value: string, options: ReturnType<typeof apiTokenCookieOptions>) => void },
  token: string,
): void {
  target.set(API_TOKEN_COOKIE, encodeApiTokenCookie(token), apiTokenCookieOptions());
}

/**
 * Browser client talks to the same-origin BFF (`/api/laravel/...`), which attaches
 * the httpOnly Sanctum cookie. Never read the bearer token from document.cookie.
 */
export function createBrowserApiClient(): ApiClient {
  if (typeof window === "undefined") {
    throw new Error("createBrowserApiClient is only for client components.");
  }
  // Relative base: ApiClient appends /api{path}. Path /laravel/subjects → /api/laravel/subjects.
  const origin = window.location.origin;
  return new BrowserBffApiClient(origin);
}

/** Same as ApiClient but prefixes Laravel paths with /laravel for the BFF route. */
class BrowserBffApiClient extends ApiClient {
  constructor(origin: string) {
    // Token unused — BFF reads httpOnly cookie. Empty string keeps Authorization off.
    super("", origin);
  }

  override async get<T>(path: string, options?: RequestOptions): Promise<T> {
    return super.get<T>(toBffPath(path), options);
  }

  override async post<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return super.post<T>(toBffPath(path), body, options);
  }

  override async put<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return super.put<T>(toBffPath(path), body, options);
  }

  override async patch<T>(path: string, body?: unknown, options?: RequestOptions): Promise<T> {
    return super.patch<T>(toBffPath(path), body, options);
  }

  override async delete<T>(path: string, options?: RequestOptions): Promise<T> {
    return super.delete<T>(toBffPath(path), options);
  }
}

function toBffPath(path: string): string {
  const normalized = path.startsWith("/") ? path : `/${path}`;
  if (normalized.startsWith("/laravel/") || normalized === "/laravel") {
    return normalized;
  }
  return `/laravel${normalized}`;
}
