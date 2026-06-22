/** Where Supabase sends teachers after they tap the email-confirm link (web sign-up). */
export function webAuthCallbackUrl(siteOrigin: string): string {
  const base = siteOrigin.replace(/\/$/, "");
  return `${base}/auth/callback`;
}
