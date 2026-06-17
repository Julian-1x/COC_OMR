import Link from "next/link";
import { Card } from "@/components/ui/card";
import { fetchSyncDiagnostics } from "@/lib/api/sync-diagnostics";
import { requireTeacherSession } from "@/lib/api/session";
import { formatDistanceToNow } from "date-fns";

export default async function SyncCheckPage() {
  const { user, profile, supabase } = await requireTeacherSession();
  const diagnostic = await fetchSyncDiagnostics(supabase, user, profile);

  return (
    <>
      <div className="mb-6">
        <Link href="/dashboard/settings" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Settings
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Sync check</h1>
        <p className="mt-1 text-sm text-slate-500">
          Verify that phone data reached the cloud for this account.
        </p>
      </div>

      <Card
        title={diagnostic.ok ? "Cloud data found" : "Waiting for phone sync"}
        className={diagnostic.ok ? "border-emerald-200 bg-emerald-50" : "border-amber-200 bg-amber-50"}
      >
        <p className="text-sm text-slate-700">
          Signed in as <strong>{diagnostic.email}</strong>
          {diagnostic.schoolName ? ` · ${diagnostic.schoolName}` : ""}
        </p>
        <p className="mt-1 font-mono text-xs text-slate-500">Account ID: {diagnostic.userId}</p>
        {diagnostic.lastCloudUpdate ? (
          <p className="mt-2 text-sm text-slate-600">
            Last cloud update:{" "}
            {formatDistanceToNow(new Date(diagnostic.lastCloudUpdate), { addSuffix: true })}
          </p>
        ) : null}
      </Card>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card title="Cloud counts">
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between">
              <dt className="font-bold text-slate-500">Classes</dt>
              <dd>{diagnostic.stats.sectionCount}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="font-bold text-slate-500">Students</dt>
              <dd>{diagnostic.stats.studentCount}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="font-bold text-slate-500">Answer keys</dt>
              <dd>{diagnostic.stats.subjectCount}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="font-bold text-slate-500">Scans</dt>
              <dd>{diagnostic.stats.scanCount}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="font-bold text-slate-500">Needs review (phone)</dt>
              <dd>{diagnostic.stats.pendingReview}</dd>
            </div>
          </dl>
        </Card>

        <Card title="Per-table status">
          <ul className="space-y-2 text-sm">
            {diagnostic.tableSamples.map((row) => (
              <li key={row.table} className="flex justify-between gap-4">
                <span className="font-bold text-slate-600">{row.table}</span>
                <span className="text-slate-800">
                  {row.count} rows
                  {row.latestUpdated
                    ? ` · ${formatDistanceToNow(new Date(row.latestUpdated), { addSuffix: true })}`
                    : ""}
                </span>
              </li>
            ))}
          </ul>
        </Card>
      </div>

      <Card title="Sync checklist" className="mt-4">
        <ol className="list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-700">
          <li>Phone app signed in as <strong>{diagnostic.email}</strong>.</li>
          <li>Connect to Wi‑Fi.</li>
          <li>Settings → <strong>Sync Now</strong> and wait for success.</li>
          <li>
            Refresh this page —{" "}
            <Link href="/dashboard/sync-check" className="font-bold text-emerald-700 hover:underline">
              Sync check
            </Link>
            .
          </li>
          <li>Open Classes and Results to confirm rosters and scans.</li>
        </ol>
        {diagnostic.hints.length > 0 ? (
          <ul className="mt-4 space-y-2">
            {diagnostic.hints.map((hint) => (
              <li key={hint} className="rounded-lg bg-amber-100 px-3 py-2 text-sm font-semibold text-amber-900">
                {hint}
              </li>
            ))}
          </ul>
        ) : null}
      </Card>
    </>
  );
}
