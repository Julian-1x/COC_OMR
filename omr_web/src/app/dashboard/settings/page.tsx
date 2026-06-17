import Link from "next/link";
import { Card } from "@/components/ui/card";
import { isSchoolAdmin, normalizeRole } from "@/lib/api/admin";
import { fetchCloudLastUpdated, fetchDashboardStats } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { getSupabaseProjectRef } from "@/lib/supabase/env";
import { workspaceName } from "@/lib/theme";
import { formatDistanceToNow } from "date-fns";

export default async function SettingsPage() {
  const { user, profile, supabase } = await requireTeacherSession();
  const admin = isSchoolAdmin(profile, user);
  const cloudProject = getSupabaseProjectRef();
  const metaRole =
    normalizeRole(user.app_metadata?.role as string | undefined) ||
    normalizeRole(user.user_metadata?.role as string | undefined) ||
    "none";
  const [stats, lastUpdated] = await Promise.all([
    fetchDashboardStats(supabase),
    fetchCloudLastUpdated(supabase),
  ]);

  const lastSyncLabel = lastUpdated
    ? formatDistanceToNow(new Date(lastUpdated), { addSuffix: true })
    : "Never";

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">Settings</h1>
        <p className="mt-1 text-sm text-slate-500">Account and sync notes.</p>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Workspace">
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">School</dt>
              <dd className="font-semibold text-slate-800">{workspaceName}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Teacher</dt>
              <dd className="font-semibold text-slate-800">{profile?.full_name ?? user.email}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Email</dt>
              <dd className="font-semibold text-slate-800">{user.email}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Portal role</dt>
              <dd className="font-semibold capitalize text-slate-800">
                {profile?.role?.replace("_", " ") ?? "unknown"}
                {admin ? " · admin access" : ""}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Auth metadata role</dt>
              <dd className="font-semibold text-slate-800">{metaRole}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Cloud project</dt>
              <dd className="font-mono text-xs text-slate-800">{cloudProject}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Account ID</dt>
              <dd className="font-mono text-xs text-slate-800">{user.id}</dd>
            </div>
          </dl>
          {!admin ? (
            <p className="mt-3 text-sm leading-relaxed text-amber-800">
              Admin access needs <strong>school_admin</strong> in Supabase for project{" "}
              <strong>{cloudProject}</strong>. In SQL Editor, confirm the URL shows{" "}
              <strong>{cloudProject}.supabase.co</strong>, then run{" "}
              <code className="text-xs">supabase/get_my_teacher_profile.sql</code> and promote your
              account.
            </p>
          ) : null}
        </Card>

        <Card title="Cloud data for this account">
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Classes</dt>
              <dd className="font-semibold text-slate-800">{stats.sectionCount}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Students</dt>
              <dd className="font-semibold text-slate-800">{stats.studentCount}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Answer keys</dt>
              <dd className="font-semibold text-slate-800">{stats.subjectCount}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Scans</dt>
              <dd className="font-semibold text-slate-800">{stats.scanCount}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Last cloud update</dt>
              <dd className="font-semibold text-slate-800">{lastSyncLabel}</dd>
            </div>
          </dl>
          {stats.studentCount === 0 ? (
            <p className="mt-3 text-sm leading-relaxed text-amber-800">
              If your phone has data but counts are 0 here, tap <strong>Sync Now</strong> in the mobile app
              while signed in as <strong>{user.email}</strong>.
            </p>
          ) : null}
        </Card>

        <Card title="Sync from phone" subtitle="Checklist">
          <ol className="list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-700">
            <li>
              Phone app signed in as <strong>{user.email}</strong> (same as this portal).
            </li>
            <li>Connect to school Wi‑Fi.</li>
            <li>
              Open app → <strong>Settings</strong> → <strong>Sync Now</strong>.
            </li>
            <li>Refresh this page — classes and results should appear.</li>
          </ol>
          <Link
            href="/dashboard/sync-check"
            className="mt-4 inline-block rounded-xl bg-emerald-500 px-4 py-2 text-sm font-extrabold text-white hover:bg-emerald-600"
          >
            Open sync check
          </Link>
        </Card>

        {admin ? (
          <Card title="School admin">
            <p className="text-sm text-slate-600">
              View school-wide teacher activity and cloud totals.
            </p>
            <Link
              href="/dashboard/admin"
              className="mt-3 inline-block text-sm font-bold text-emerald-700 hover:underline"
            >
              Open admin dashboard →
            </Link>
          </Card>
        ) : null}

        <Card title="Sync with phone">
          <p className="text-sm leading-relaxed text-slate-600">
            This portal reads and writes the same cloud data as the mobile app. After you change
            rosters or answer keys here, open the app and tap <strong>Sync Now</strong> in Settings.
            After scanning on exam day, sync from the phone to see results here.
          </p>
        </Card>

        <Card title="Scanner">
          <p className="text-sm leading-relaxed text-slate-600">
            OMR scanning is only available in the <strong>Android app</strong>. Use your offline PIN
            on exam day — no Wi‑Fi required for scanning.
          </p>
        </Card>
      </div>
    </>
  );
}
