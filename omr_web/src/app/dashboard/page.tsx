import Link from "next/link";
import { formatDistanceToNow } from "date-fns";
import { BookOpen, GraduationCap, BarChart3, Smartphone } from "lucide-react";
import { Card, StatCard } from "@/components/ui/card";
import { fetchCloudLastUpdated, fetchDashboardStats } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";

const deskTasks = [
  {
    href: "/dashboard/prepare/import",
    title: "Import roster",
    body: "Upload your class list from Excel or CSV.",
    icon: GraduationCap,
  },
  {
    href: "/dashboard/prepare/answer-keys",
    title: "Answer keys",
    body: "Set up subjects and correct answers before printing.",
    icon: BookOpen,
  },
  {
    href: "/dashboard/prepare/print-sheets",
    title: "Print sheets",
    body: "Download OMR bubble sheets for your students.",
    icon: BookOpen,
  },
  {
    href: "/dashboard/results",
    title: "Results & export",
    body: "View scores and download PDF or CSV after exam day.",
    icon: BarChart3,
  },
];

export default async function DashboardHomePage() {
  const { user, profile, supabase } = await requireTeacherSession();
  const [stats, lastUpdated] = await Promise.all([
    fetchDashboardStats(supabase),
    fetchCloudLastUpdated(supabase),
  ]);

  const firstName = profile?.full_name?.split(" ")[0] ?? "Teacher";
  const hasData =
    stats.sectionCount > 0 ||
    stats.studentCount > 0 ||
    stats.subjectCount > 0 ||
    stats.scanCount > 0;

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">Hello, {firstName}</h1>
        <p className="mt-1 text-sm text-slate-500">
          Prep and print here on your desk. Scan on your phone. Results show up after you sync.
        </p>
        {lastUpdated && hasData ? (
          <p className="mt-1 text-xs text-slate-400">
            Last updated {formatDistanceToNow(new Date(lastUpdated), { addSuffix: true })}
          </p>
        ) : null}
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Classes" value={stats.sectionCount} />
        <StatCard label="Students" value={stats.studentCount} />
        <StatCard label="Answer keys" value={stats.subjectCount} />
        <StatCard
          label="Graded sheets"
          value={stats.scanCount}
          hint={stats.pendingReview > 0 ? `${stats.pendingReview} to review on phone` : undefined}
        />
      </div>

      {!hasData ? (
        <Card className="mt-6 border-amber-200 bg-amber-50" title="Get started">
          <p className="text-sm leading-relaxed text-slate-700">
            This desk is empty. You can build everything here, or start on your phone and sync over.
          </p>
          <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-slate-700">
            <li>
              <Link href="/dashboard/prepare/import" className="font-bold text-emerald-700 hover:underline">
                Import a roster
              </Link>{" "}
              or add students in the phone app.
            </li>
            <li>
              <Link href="/dashboard/prepare/answer-keys" className="font-bold text-emerald-700 hover:underline">
                Create answer keys
              </Link>{" "}
              and print OMR sheets.
            </li>
            <li>
              On your phone ({user.email}): <strong>Settings</strong> → <strong>Sync Now</strong> on Wi‑Fi.
            </li>
          </ol>
        </Card>
      ) : null}

      <div className="mt-6">
        <h2 className="mb-3 text-sm font-extrabold uppercase tracking-wide text-slate-500">What you can do here</h2>
        <div className="grid gap-4 sm:grid-cols-2">
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
                      <p className="mt-1 text-sm text-slate-500">{task.body}</p>
                    </div>
                  </div>
                </Card>
              </Link>
            );
          })}
        </div>
      </div>

      <Card className="mt-6" title="Phone app">
        <div className="flex items-start gap-3">
          <div className="rounded-xl bg-slate-100 p-2 text-slate-600">
            <Smartphone className="h-5 w-5" />
          </div>
          <p className="text-sm leading-relaxed text-slate-600">
            <strong>Scanning</strong> and your <strong>offline PIN</strong> are only on the Android app. This
            website is for prep, printing, viewing results, and exporting — not for scanning during the exam.
          </p>
        </div>
      </Card>
    </>
  );
}
