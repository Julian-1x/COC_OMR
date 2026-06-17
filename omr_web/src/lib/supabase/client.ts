import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { getSupabaseClientEnv, isSupabaseConfigured } from "@/lib/supabase/env";

export { isSupabaseConfigured };

export function createClient() {
  const { url, key } = getSupabaseClientEnv();
  if (!url?.startsWith("https://") || !key) {
    throw new Error(
      "Supabase is not configured. Add omr_web/.env.local, then restart: npm run dev",
    );
  }
  return createSupabaseClient(url, key);
}
