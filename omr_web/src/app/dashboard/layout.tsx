import { cookies } from "next/headers";
import { DashboardShell } from "@/components/dashboard-shell";
import { isSchoolAdmin } from "@/lib/api/admin";
import { requireTeacherSession } from "@/lib/api/session";
import { parsePortalMode, PORTAL_MODE_COOKIE } from "@/lib/portal-mode";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, profile } = await requireTeacherSession();
  const admin = isSchoolAdmin(profile);
  const cookieStore = await cookies();
  const initialMode = parsePortalMode(cookieStore.get(PORTAL_MODE_COOKIE)?.value);

  return (
    <DashboardShell
      teacherName={profile?.full_name ?? user.email ?? "Teacher"}
      schoolName={profile?.school_name ?? undefined}
      isAdmin={admin}
      initialMode={initialMode}
    >
      {children}
    </DashboardShell>
  );
}
