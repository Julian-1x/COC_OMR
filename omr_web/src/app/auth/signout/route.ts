import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { getSupabaseServerEnv } from "@/lib/supabase/env";

export async function POST() {
  const cookieStore = await cookies();
  const { url, key } = getSupabaseServerEnv();
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) =>
          cookieStore.set(name, value, options),
        );
      },
    },
  });

  await supabase.auth.signOut();
  return NextResponse.json({ ok: true });
}
