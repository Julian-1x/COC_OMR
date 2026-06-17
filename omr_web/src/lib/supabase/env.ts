/** Server/runtime Supabase config (not inlined at compile time). */
export function getSupabaseServerEnv() {
  const url = (
    process.env.SUPABASE_URL ??
    process.env["NEXT_PUBLIC_SUPABASE_URL"]
  )?.trim();
  const key = (
    process.env.SUPABASE_PUBLISHABLE_KEY ??
    process.env["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"]
  )?.trim();

  if (!url?.startsWith("https://") || !key) {
    throw new Error(
      "Supabase is not configured. Check omr_web/.env.local and restart npm run dev.",
    );
  }

  return { url, key };
}

/** Client bundle config (NEXT_PUBLIC_*; requires dev server restart after changes). */
export function getSupabaseClientEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  return { url, key };
}

export function isSupabaseConfigured(): boolean {
  const { url, key } = getSupabaseClientEnv();
  return Boolean(url?.startsWith("https://") && key);
}
