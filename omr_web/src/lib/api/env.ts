/** Server/runtime API base URL (not inlined at compile time). */
export function getApiBaseUrl(): string {
  const url = (
    process.env.API_BASE_URL ??
    process.env.NEXT_PUBLIC_API_BASE_URL
  )?.trim();

  if (!url) {
    throw new Error(
      "API is not configured. Set API_BASE_URL in omr_web/.env.local and restart npm run dev.",
    );
  }

  return url.replace(/\/$/, "");
}

/** Client bundle config (NEXT_PUBLIC_*; requires dev server restart after changes). */
export function getPublicApiBaseUrl(): string {
  const url = process.env.NEXT_PUBLIC_API_BASE_URL?.trim();

  if (!url) {
    throw new Error(
      "API is not configured. Set NEXT_PUBLIC_API_BASE_URL in omr_web/.env.local and restart npm run dev.",
    );
  }

  return url.replace(/\/$/, "");
}

export function tryGetApiBaseUrl(): string | null {
  const url = (
    process.env.API_BASE_URL ??
    process.env.NEXT_PUBLIC_API_BASE_URL
  )?.trim();
  return url ? url.replace(/\/$/, "") : null;
}

export function isApiConfigured(): boolean {
  const url = process.env.NEXT_PUBLIC_API_BASE_URL?.trim();
  return Boolean(url && /^https?:\/\//.test(url));
}

/** Human-readable deploy/config checklist for teachers/devs when sign-in fails. */
export function apiConfigHint(): string {
  if (!isApiConfigured()) {
    return (
      "Set NEXT_PUBLIC_API_BASE_URL and API_BASE_URL to your Laravel API URL " +
      "(same value, no trailing slash), then restart or redeploy the web app. " +
      "On the API host, set FRONTEND_URL to this website’s URL so email links work."
    );
  }
  return (
    "If email verification or password reset links fail, set FRONTEND_URL on the " +
    "Laravel API to this website’s public URL, then redeploy the API."
  );
}

/** True when public and server API bases disagree (common deploy mistake). */
export function apiBaseUrlMismatch(): boolean {
  const pub = process.env.NEXT_PUBLIC_API_BASE_URL?.trim().replace(/\/$/, "") ?? "";
  const srv = (
    process.env.API_BASE_URL ??
    process.env.NEXT_PUBLIC_API_BASE_URL
  )
    ?.trim()
    .replace(/\/$/, "");
  if (!pub || !srv) return false;
  return pub !== srv;
}
