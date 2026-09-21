export const PORTAL_MODE_COOKIE = "coc_portal_mode";

export type PortalMode = "teacher" | "admin";

export function parsePortalMode(value: string | undefined | null): PortalMode {
  return value === "admin" ? "admin" : "teacher";
}

export function portalModeCookieValue(mode: PortalMode): string {
  const secure =
    typeof window !== "undefined" && window.location.protocol === "https:"
      ? "; Secure"
      : "";
  // Preference only — not a secret. Auth roles still come from the API profile.
  return `${PORTAL_MODE_COOKIE}=${mode}; path=/; max-age=31536000; SameSite=Lax${secure}`;
}
