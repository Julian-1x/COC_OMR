import Link from "next/link";
import { formatDistanceToNow } from "date-fns";
import { Card } from "@/components/ui/card";
import { isSchoolAdmin } from "@/lib/api/admin";
import { fetchCloudLastUpdated, fetchDashboardStats } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { workspaceName } from "@/lib/theme";

export default async function SettingsPage() {
  const { user, profile, supabase } = await requireTeacherSession();
  const admin = isSchoolAdmin(profile, user);
  const [stats, lastUpdated] = await Promise.all([
    fetchDashboardStats(supabase),
    fetchCloudLastUpdated(supabase),
  ]);

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
        <p className="mt-1 text-sm text-slate-500">Your account and how the phone app connects to this desk.</p>
      </div>

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

        <Card title="Your data on this desk">
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
            <p className="mt-3 text-sm leading-relaxed text-amber-800">
              Nothing here yet. Use <strong>Prepare</strong> on this desk, or open the phone app →{" "}
              <strong>Settings</strong> → <strong>Sync Now</strong> while on Wi‑Fi (same email as above).
            </p>
          ) : stats.pendingReview > 0 ? (
            <p className="mt-3 text-sm leading-relaxed text-amber-800">
              <strong>{stats.pendingReview}</strong> sheet{stats.pendingReview === 1 ? "" : "s"} still need
              review on your phone before they count here.
            </p>
          ) : null}
        </Card>

        <Card title="Connect your phone" subtitle="Same email on both">
          <ol className="list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-700">
            <li>
              Sign in on the phone as <strong>{user.email}</strong>.
            </li>
            <li>Connect to Wi‑Fi.</li>
            <li>
              Open the app → <strong>Settings</strong> → <strong>Sync Now</strong>.
            </li>
            <li>Refresh this page — classes and results should match.</li>
          </ol>
        </Card>

        <Card title="Exam day">
          <p className="text-sm leading-relaxed text-slate-600">
            Scanning happens on your <strong>phone</strong> with your offline PIN — no Wi‑Fi needed during
            the exam. Afterward, sync on Wi‑Fi so results appear here for export and review.
          </p>
        </Card>

        {admin ? (
          <Card title="School admin" className="lg:col-span-2">
            <p className="text-sm text-slate-600">
              See teachers, classes, and rosters across your school. You cannot change another teacher&apos;s
              data from here — only view.
            </p>
            <Link
              href="/dashboard/admin"
              className="mt-3 inline-block rounded-xl bg-emerald-500 px-4 py-2 text-sm font-extrabold text-white hover:bg-emerald-600"
            >
              Open school overview
            </Link>
          </Card>
        ) : null}
      </div>
    </>
  );
}
