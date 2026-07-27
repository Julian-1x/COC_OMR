import { redirect } from "next/navigation";
import {
  isAccessApproved,
  isSchoolAdmin,
  isSuperAdmin,
} from "@/lib/api/admin";
import {
  ApiClient,
  ApiError,
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
  try {
    const { user } = await api.get<{ user: ApiUser }>("/me");
    if (!isAccessApproved(user.profile)) {
      redirect("/login?pending=1");
    }
    return { api, user, profile: user.profile };
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      redirect("/login");
    }
    if (error instanceof ApiError && error.status === 403) {
      redirect("/login?pending=1");
    }
    throw error;
  }
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

export async function requireSuperAdminSession(): Promise<{
  api: ApiClient;
  user: ApiUser;
  profile: DbTeacherProfile;
}> {
  const session = await requireAdminSession();
  if (!isSuperAdmin(session.profile, session.user)) {
    redirect("/dashboard/admin");
  }
  return session;
}
