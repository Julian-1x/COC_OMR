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
