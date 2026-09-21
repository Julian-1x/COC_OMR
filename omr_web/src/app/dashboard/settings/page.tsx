import Link from "next/link";
import { formatDistanceToNow } from "date-fns";
import { Card } from "@/components/ui/card";
import { isSchoolAdmin } from "@/lib/api/admin";
import { fetchCloudLastUpdated, fetchDashboardStats } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { workspaceName } from "@/lib/theme";
import { SyncLoopNotice } from "@/components/desk-notices";
import { apiBaseUrlMismatch } from "@/lib/api/env";

export default async function SettingsPage() {
  const { user, profile, api } = await requireTeacherSession();
  const admin = isSchoolAdmin(profile, user);

  let stats = {
    sectionCount: 0,
    studentCount: 0,
    subjectCount: 0,
    scanCount: 0,
    pendingReview: 0,
    lastUpdated: null as string | null,
  };
  let lastUpdated: string | null = null;
  let cloudSlow = false;

  try {
    const nextStats = await fetchDashboardStats(api);
    stats = nextStats;
    lastUpdated = nextStats.lastUpdated ?? (await fetchCloudLastUpdated(api));
  } catch {
    cloudSlow = true;
  }

  const hasData =
    stats.sectionCount > 0 ||
    stats.studentCount > 0 ||
    stats.subjectCount > 0 ||
    stats.scanCount > 0;

  const lastUpdatedLabel = lastUpdated
    ? formatDistanceToNow(new Date(lastUpdated), { addSuffix: true })
    : null;

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">Settings</h1>
        <p className="mt-1 text-sm text-slate-500">Account and phone sync</p>
      </div>

      <SyncLoopNotice className="mb-4" />

      {apiBaseUrlMismatch() ? (
        <div className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-900">
          Deploy config error: <code className="font-mono text-xs">API_BASE_URL</code> and{" "}
          <code className="font-mono text-xs">NEXT_PUBLIC_API_BASE_URL</code> must match.
        </div>
      ) : null}

      {cloudSlow ? (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          School server is busy — refresh in a minute for class counts.
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Account">
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">School</dt>
              <dd className="font-semibold text-slate-800">
                {profile?.school_name?.trim() || workspaceName}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Name</dt>
              <dd className="font-semibold text-slate-800">{profile?.full_name ?? "—"}</dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="font-bold text-slate-500">Email</dt>
              <dd className="font-semibold text-slate-800">{user.email}</dd>
            </div>
            {admin ? (
              <div className="flex justify-between gap-4">
                <dt className="font-bold text-slate-500">Access</dt>
                <dd className="font-semibold text-slate-800">Teacher + school admin</dd>
              </div>
            ) : null}
          </dl>
        </Card>

        <Card title="Data on this desk">
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
              <dt className="font-bold text-slate-500">Graded sheets</dt>
              <dd className="font-semibold text-slate-800">{stats.scanCount}</dd>
            </div>
            {lastUpdatedLabel ? (
              <div className="flex justify-between gap-4">
                <dt className="font-bold text-slate-500">Last updated</dt>
                <dd className="font-semibold text-slate-800">{lastUpdatedLabel}</dd>
              </div>
            ) : null}
          </dl>
          {!hasData ? (
            <p className="mt-3 text-sm text-amber-800">
              Nothing here yet — import a roster or sync from the phone.
            </p>
          ) : stats.pendingReview > 0 ? (
            <p className="mt-3 text-sm text-amber-800">
              {stats.pendingReview} sheet{stats.pendingReview === 1 ? "" : "s"} still need phone review.
            </p>
          ) : null}
        </Card>

        <Card title="Phone sync" subtitle={`Sign in as ${user.email}`}>
          <ol className="list-decimal space-y-1.5 pl-5 text-sm text-slate-700">
            <li>Connect to Wi‑Fi</li>
            <li>
              App → <strong>Settings</strong> → <strong>Sync Now</strong>
            </li>
            <li>Refresh this page</li>
          </ol>
          <p className="mt-3 text-sm text-slate-600">
            Scan offline with your PIN. Sync afterward so results show here.
          </p>
        </Card>

        {admin ? (
          <Card title="School admin">
            <div className="flex flex-wrap gap-2">
              <Link
                href="/dashboard/admin"
                className="inline-block rounded-xl bg-emerald-500 px-4 py-2 text-sm font-extrabold text-white hover:bg-emerald-600"
              >
                School overview
              </Link>
              <Link
                href="/dashboard/admin/access"
                className="inline-block rounded-xl border border-emerald-200 bg-white px-4 py-2 text-sm font-extrabold text-emerald-800 hover:bg-emerald-50"
              >
                Access control
              </Link>
            </div>
          </Card>
        ) : null}
      </div>
    </>
  );
}
