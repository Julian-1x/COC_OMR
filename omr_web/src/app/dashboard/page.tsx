import Link from "next/link";
import { formatDistanceToNow } from "date-fns";
import { BookOpen, GraduationCap, BarChart3, Printer } from "lucide-react";
import { Card, StatCard } from "@/components/ui/card";
import { ExamDeskPanel } from "@/components/exam-desk-panel";
import { PendingReviewNotice } from "@/components/desk-notices";
import {
  fetchCloudLastUpdated,
  fetchDashboardStats,
  fetchScanResults,
  fetchSections,
  fetchStudents,
  fetchSubjects,
} from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import {
  buildAttentionItems,
  buildClassSnapshots,
  suggestExamTarget,
} from "@/lib/omr/desk-insights";

const deskTasks = [
  {
    href: "/dashboard/prepare/import",
    title: "Import roster",
    body: "Excel class list",
    icon: GraduationCap,
  },
  {
    href: "/dashboard/prepare/answer-keys",
    title: "Answer keys",
    body: "Set correct answers",
    icon: BookOpen,
  },
  {
    href: "/dashboard/prepare/print-sheets",
    title: "Print sheets",
    body: "OMR bubble sheets",
    icon: Printer,
  },
  {
    href: "/dashboard/results",
    title: "Results",
    body: "Scores & exports",
    icon: BarChart3,
  },
];

export default async function DashboardHomePage() {
  const { profile, api } = await requireTeacherSession();

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
  let sections: Awaited<ReturnType<typeof fetchSections>> = [];
  let students: Awaited<ReturnType<typeof fetchStudents>> = [];
  let subjects: Awaited<ReturnType<typeof fetchSubjects>> = [];
  let scans: Awaited<ReturnType<typeof fetchScanResults>> = [];

  try {
    const [nextStats, nextSections, nextStudents, nextSubjects, nextScans] = await Promise.all([
      fetchDashboardStats(api),
      fetchSections(api, { archived: false }),
      fetchStudents(api),
      fetchSubjects(api),
      fetchScanResults(api),
    ]);
    stats = nextStats;
    lastUpdated = nextStats.lastUpdated ?? (await fetchCloudLastUpdated(api));
    sections = nextSections;
    students = nextStudents;
    subjects = nextSubjects;
    scans = nextScans;
  } catch {
    cloudSlow = true;
  }

  const firstName = profile?.full_name?.split(" ")[0] ?? "Teacher";
  const hasData =
    stats.sectionCount > 0 ||
    stats.studentCount > 0 ||
    stats.subjectCount > 0 ||
    stats.scanCount > 0;

  const activeNames = sections.map((s) => s.name);
  const snapshots = buildClassSnapshots(sections, students, scans, subjects);
  const attention = buildAttentionItems({
    pendingReview: stats.pendingReview,
    sections,
    students,
    subjects,
  });
  const suggested = suggestExamTarget(subjects, activeNames, scans, students);
  const spotlight = snapshots
    .filter((s) => s.gradedCount > 0 || s.pendingCount > 0)
    .slice(0, 4);

  return (
    <>
      <div className="mb-5">
        <h1 className="text-2xl font-extrabold text-slate-800">Hello, {firstName}</h1>
        <p className="mt-1 text-sm text-slate-500">Prep · print · sync results from the phone</p>
        {cloudSlow ? (
          <p className="mt-2 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm font-semibold text-amber-900">
            School server is busy — reload in a minute.
          </p>
        ) : null}
        {!cloudSlow && lastUpdated && hasData ? (
          <p className="mt-2 text-sm text-slate-600">
            Last sync {formatDistanceToNow(new Date(lastUpdated), { addSuffix: true })}
          </p>
        ) : null}
      </div>

      <PendingReviewNotice count={stats.pendingReview} className="mb-4" />

      <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
        <StatCard label="Classes" value={stats.sectionCount} />
        <StatCard label="Students" value={stats.studentCount} />
        <StatCard label="Answer keys" value={stats.subjectCount} />
        <StatCard
          label="Graded sheets"
          value={stats.scanCount}
          hint={stats.pendingReview > 0 ? `${stats.pendingReview} need review` : undefined}
        />
      </div>

      {!cloudSlow ? (
        <div className="mt-5">
          <ExamDeskPanel
            subjects={subjects}
            activeSectionNames={activeNames}
            initialTarget={suggested}
          />
        </div>
      ) : null}

      {attention.length > 0 ? (
        <Card className="mt-5 border-amber-200" title="Needs attention">
          <ul className="space-y-2">
            {attention.map((item) => (
              <li key={item.id}>
                <Link
                  href={item.href}
                  className={`block rounded-xl px-3 py-2 text-sm font-semibold hover:underline ${
                    item.tone === "red"
                      ? "bg-red-50 text-red-800"
                      : item.tone === "amber"
                        ? "bg-amber-50 text-amber-950"
                        : "bg-slate-50 text-slate-700"
                  }`}
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}

      {spotlight.length > 0 ? (
        <div className="mt-5">
          <h2 className="mb-3 text-sm font-extrabold uppercase tracking-wide text-slate-500">
            Class snapshot
          </h2>
          <div className="grid gap-3 sm:grid-cols-2">
            {spotlight.map((snap) => (
              <Link key={snap.sectionName} href={`/dashboard/classes/${encodeURIComponent(snap.sectionName)}`}>
                <Card className="h-full transition hover:border-emerald-300 hover:shadow-md">
                  <p className="font-extrabold text-slate-800">{snap.sectionName}</p>
                  <p className="mt-1 text-sm text-slate-500">
                    {snap.studentCount} students
                    {snap.gradedCount > 0 ? ` · ${snap.gradedCount} graded` : ""}
                    {snap.pendingCount > 0 ? ` · ${snap.pendingCount} pending` : ""}
                  </p>
                  {snap.averagePercent != null ? (
                    <div className="mt-3 flex gap-3 text-sm">
                      <span className="rounded-lg bg-emerald-50 px-2 py-1 font-bold text-emerald-800">
                        Avg {snap.averagePercent}%
                      </span>
                      <span className="rounded-lg bg-slate-100 px-2 py-1 font-bold text-slate-700">
                        Pass {snap.passRate}%
                      </span>
                      {snap.failCount > 0 ? (
                        <span className="rounded-lg bg-amber-50 px-2 py-1 font-bold text-amber-900">
                          {snap.failCount} failed
                        </span>
                      ) : null}
                    </div>
                  ) : (
                    <p className="mt-3 text-sm text-slate-500">No graded sheets yet</p>
                  )}
                </Card>
              </Link>
            ))}
          </div>
        </div>
      ) : null}

      {!hasData && !cloudSlow ? (
        <Card className="mt-5 border-amber-200 bg-amber-50" title="Get started">
          <ol className="list-decimal space-y-1.5 pl-5 text-sm text-slate-700">
            <li>
              <Link href="/dashboard/prepare/import" className="font-bold text-emerald-700 hover:underline">
                Import a roster
              </Link>
            </li>
            <li>
              <Link href="/dashboard/prepare/answer-keys" className="font-bold text-emerald-700 hover:underline">
                Create answer keys
              </Link>{" "}
              and print
            </li>
            <li>
              Phone: <strong>Settings → Sync Now</strong>
            </li>
          </ol>
        </Card>
      ) : null}

      <div className="mt-6">
        <h2 className="mb-3 text-sm font-extrabold uppercase tracking-wide text-slate-500">
          Shortcuts
        </h2>
        <div className="grid gap-3 sm:grid-cols-2">
          {deskTasks.map((task) => {
            const Icon = task.icon;
            return (
              <Link key={task.href} href={task.href}>
                <Card className="h-full transition hover:border-emerald-300 hover:shadow-md">
                  <div className="flex items-start gap-3">
                    <div className="rounded-xl bg-emerald-50 p-2 text-emerald-700">
                      <Icon className="h-5 w-5" />
                    </div>
                    <div>
                      <h3 className="font-extrabold text-slate-800">{task.title}</h3>
                      <p className="mt-0.5 text-sm text-slate-500">{task.body}</p>
                    </div>
                  </div>
                </Card>
              </Link>
            );
          })}
        </div>
      </div>
    </>
  );
}
