import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { isSchoolAdmin } from "@/lib/api/admin";
import { fetchProfile } from "@/lib/api/data";
import { getSupabaseServerEnv } from "@/lib/supabase/env";
import type { DbTeacherProfile } from "@/lib/types/database";
import type { User } from "@supabase/supabase-js";

export async function requireTeacherSession(): Promise<{
  supabase: Awaited<ReturnType<typeof createServerClient>>;
  user: User;
  profile: DbTeacherProfile | null;
}> {
  const cookieStore = await cookies();
  const { url, key } = getSupabaseServerEnv();
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Server Component — middleware handles refresh.
        }
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const profile = await fetchProfile(supabase, user.id);
  return { supabase, user, profile };
}

export async function requireAdminSession(): Promise<{
  supabase: Awaited<ReturnType<typeof createServerClient>>;
  user: User;
  profile: DbTeacherProfile;
}> {
  const session = await requireTeacherSession();
  if (!isSchoolAdmin(session.profile, session.user)) {
    redirect("/dashboard");
  }
  if (!session.profile) {
    redirect("/dashboard");
  }
  return {
    supabase: session.supabase,
    user: session.user,
    profile: session.profile,
  };
}
