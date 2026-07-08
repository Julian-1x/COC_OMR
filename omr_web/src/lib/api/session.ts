import { redirect } from "next/navigation";
import { isSchoolAdmin } from "@/lib/api/admin";
import {
  ApiClient,
  ApiUser,
} from "@/lib/api/laravel-client";
import {
  createServerApiClient,
  getServerApiToken,
} from "@/lib/api/laravel-server";
import type { DbTeacherProfile } from "@/lib/types/database";

export async function requireTeacherSession(): Promise<{
  api: ApiClient;
  user: ApiUser;
  profile: DbTeacherProfile | null;
}> {
  const token = await getServerApiToken();
  if (!token) redirect("/login");

  const api = createServerApiClient(token);
  const { user } = await api.get<{ user: ApiUser }>("/me");

  return { api, user, profile: user.profile };
}

export async function requireAdminSession(): Promise<{
  api: ApiClient;
  user: ApiUser;
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
    api: session.api,
    user: session.user,
    profile: session.profile,
  };
}
