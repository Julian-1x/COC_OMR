import { Card, StatCard } from "@/components/ui/card";
import { fetchDashboardStats } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import Link from "next/link";

export default async function DashboardHomePage() {
  const { user, profile, supabase } = await requireTeacherSession();
  const stats = await fetchDashboardStats(supabase);

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">Welcome back</h1>
        <p className="mt-1 text-sm text-slate-500">
          Prep on the web, scan on your phone, then sync to see results here.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Classes" value={stats.sectionCount} />
        <StatCard label="Students" value={stats.studentCount} />
        <StatCard label="Answer keys" value={stats.subjectCount} />
        <StatCard label="Scans synced" value={stats.scanCount} hint={`${stats.pendingReview} need review on phone`} />
      </div>

      {stats.sectionCount === 0 &&
      stats.studentCount === 0 &&
      stats.subjectCount === 0 &&
      stats.scanCount === 0 ? (
        <Card className="mt-6 border-amber-200 bg-amber-50" title="No cloud data yet" subtitle="Phone data does not appear automatically">
          <ol className="list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-700">
            <li>
              Sign in on the web with the <strong>same email</strong> as the mobile app ({user.email}).
            </li>
            <li>
              On your phone, open the app → <strong>Settings</strong> → <strong>Sync Now</strong> while on Wi‑Fi.
            </li>
            <li>Refresh this page. Classes, rosters, and scans should appear here.</li>
          </ol>
          <p className="mt-3 text-sm text-slate-600">
            Or import a roster here in Prepare — then sync on the phone to use it for scanning.
          </p>
        </Card>
      ) : null}

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card title="Quick start" subtitle="Common desk tasks">
          <ul className="space-y-2 text-sm font-semibold text-slate-700">
            <li>
              <Link className="text-emerald-700 hover:underline" href="/dashboard/prepare/import">
                1. Import roster
              </Link>
            </li>
            <li>
              <Link className="text-emerald-700 hover:underline" href="/dashboard/prepare/answer-keys">
                2. Create answer keys
              </Link>
            </li>
            <li>
              <Link className="text-emerald-700 hover:underline" href="/dashboard/prepare/print-sheets">
                3. Print OMR sheets
              </Link>
            </li>
            <li>
              <Link className="text-emerald-700 hover:underline" href="/dashboard/results">
                4. View results after phone sync
              </Link>
            </li>
          </ul>
        </Card>
        <Card title="Exam day reminder" subtitle="Phone only">
          <p className="text-sm leading-relaxed text-slate-600">
            Scanning and offline PIN unlock happen in the <strong>mobile app</strong>. This portal
            does not include a scanner. After the exam, open the app on Wi‑Fi and tap{" "}
            <strong>Sync Now</strong> in Settings.
          </p>
        </Card>
      </div>
    </>
  );
}
