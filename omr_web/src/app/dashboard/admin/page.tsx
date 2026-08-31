import Link from "next/link";

import { Card, StatCard } from "@/components/ui/card";

import {
  fetchSchoolAdminStats,
  fetchSchoolTeacherSummaries,
  isSuperAdmin,
  teacherStatusLabel,
} from "@/lib/api/admin";
import { requireAdminSession } from "@/lib/api/session";

function statusBadgeClass(status: string): string {
  switch (status) {
    case "You":
      return "bg-emerald-100 text-emerald-800";
    case "Not started":
      return "bg-amber-100 text-amber-800";
    case "Pending approval":
      return "bg-amber-100 text-amber-900";
    case "Revoked":
      return "bg-red-100 text-red-800";
    default:
      return "bg-slate-100 text-slate-700";
  }
}

export default async function AdminDashboardPage() {
  const { user, profile, api } = await requireAdminSession();
  const schoolName = profile.school_name?.trim() ?? "";
  const schoolLabel = schoolName || "your school";
  const viewerIsSuperAdmin = isSuperAdmin(profile, user);

  let stats = {
    teacherCount: 0,
    scanCount: 0,
    teachersWithNoScans: 0,
    sectionCount: 0,
    studentCount: 0,
    subjectCount: 0,
    pendingReview: 0,
  };
  let teachers: Awaited<ReturnType<typeof fetchSchoolTeacherSummaries>> = [];
  let cloudSlow = false;

  if (schoolName) {
    try {
      [stats, teachers] = await Promise.all([
        fetchSchoolAdminStats(api, schoolName, user.id),
        fetchSchoolTeacherSummaries(api, schoolName, user.id),
      ]);
    } catch {
      cloudSlow = true;
    }
  }

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">School overview</h1>
        <p className="mt-1 text-sm text-slate-500">
          See how teachers at <strong>{schoolLabel}</strong>
          {viewerIsSuperAdmin
            ? ""
            : profile.department
              ? ` (${profile.department})`
              : ""}{" "}
          are using COC OMR. View only — teachers manage their own classes on their phones.
        </p>
      </div>

      {cloudSlow ? (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          School server is slow or waking up. Open{" "}
          <a
            className="font-semibold underline"
            href="https://coc-omr-api.onrender.com/up"
            target="_blank"
            rel="noreferrer"
          >
            API status
          </a>
          , wait for Application up, then refresh.
        </div>
      ) : null}

      {!schoolName ? (
        <Card className="mb-4 border-amber-200 bg-amber-50">
          <p className="text-sm text-amber-900">
            Your account is not linked to a school yet. Ask your IT coordinator to connect your admin profile
            to your school so teacher lists appear here.
          </p>
        </Card>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard label="Teachers" value={stats.teacherCount} />
        <StatCard label="Classes" value={stats.sectionCount} />
        <StatCard label="Students" value={stats.studentCount} />
        <StatCard label="Graded sheets" value={stats.scanCount} />
        <StatCard
          label="Pending review"
          value={stats.pendingReview}
          hint={stats.pendingReview > 0 ? "On teachers' phones" : undefined}
        />
      </div>

      {stats.teachersWithNoScans > 0 && teachers.length > 1 ? (
        <p className="mt-4 text-sm text-amber-800">
          <strong>{stats.teachersWithNoScans}</strong> teacher
          {stats.teachersWithNoScans === 1 ? " has" : "s have"} not uploaded any graded sheets yet.
        </p>
      ) : null}

      <Card title="Teachers" className="mt-6" subtitle="Open a teacher to see their classes and rosters">
        <div className="mb-4 flex flex-wrap gap-3">
          <div>
            <Link
              href="/dashboard/admin/access"
              className="inline-flex rounded-xl bg-emerald-700 px-3 py-2 text-sm font-bold text-white hover:bg-emerald-800"
            >
              Open access control
            </Link>
            <p className="mt-2 text-xs text-slate-500">
              Approve or revoke which teachers can use the app and web portal.
            </p>
          </div>
          {viewerIsSuperAdmin ? (
            <>
              <div>
                <Link
                  href="/dashboard/admin/departments"
                  className="inline-flex rounded-xl border border-emerald-700 px-3 py-2 text-sm font-bold text-emerald-800 hover:bg-emerald-50"
                >
                  Department admins
                </Link>
                <p className="mt-2 text-xs text-slate-500">
                  Assign who can approve instructors in each department.
                </p>
              </div>
              <div>
                <Link
                  href="/dashboard/admin/security"
                  className="inline-flex rounded-xl border border-slate-300 px-3 py-2 text-sm font-bold text-slate-700 hover:bg-slate-50"
                >
                  Sign-in activity
                </Link>
                <p className="mt-2 text-xs text-slate-500">
                  Review failed logins, lockouts, and two-factor events.
                </p>
              </div>
            </>
          ) : null}
        </div>
        {teachers.length === 0 ? (
          <p className="text-sm text-slate-500">
            No teachers listed yet. Each teacher needs the same school name on their account.
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">Teacher</th>
                  <th className="px-2 py-2 text-left">Status</th>
                  <th className="px-2 py-2 text-left">Classes</th>
                  <th className="px-2 py-2 text-left">Students</th>
                  <th className="px-2 py-2 text-left">Sheets</th>
                  <th className="px-2 py-2 text-left">Review</th>
                  <th className="px-2 py-2 text-left" />
                </tr>
              </thead>
              <tbody>
                {teachers.map((teacher) => {
                  const status = teacherStatusLabel(teacher.status);
                  return (
                    <tr key={teacher.id} className="border-b border-slate-100">
                      <td className="px-2 py-2">
                        <div className="font-semibold text-slate-800">{teacher.full_name}</div>
                        {teacher.email ? (
                          <div className="text-xs text-slate-400">{teacher.email}</div>
                        ) : null}
                      </td>
                      <td className="px-2 py-2">
                        <span
                          className={`rounded-full px-2 py-0.5 text-xs font-bold ${statusBadgeClass(status)}`}
                        >
                          {status}
                        </span>
                      </td>
                      <td className="px-2 py-2">{teacher.sectionCount}</td>
                      <td className="px-2 py-2">{teacher.studentCount}</td>
                      <td className="px-2 py-2">{teacher.scanCount}</td>
                      <td className="px-2 py-2">
                        {teacher.pendingReviewCount > 0 ? (
                          <span className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-bold text-amber-800">
                            {teacher.pendingReviewCount}
                          </span>
                        ) : (
                          "—"
                        )}
                      </td>
                      <td className="px-2 py-2">
                        <Link
                          href={`/dashboard/admin/teachers/${teacher.id}`}
                          className="text-sm font-bold text-emerald-700 hover:underline"
                        >
                          Open
                        </Link>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
