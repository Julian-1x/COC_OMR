import Link from "next/link";
import { Card, StatCard } from "@/components/ui/card";
import { fetchSchoolAdminStats, fetchSchoolTeacherSummaries } from "@/lib/api/admin";
import { requireAdminSession } from "@/lib/api/session";

export default async function AdminDashboardPage() {
  const { user, profile, supabase } = await requireAdminSession();
  const schoolName = profile.school_name ?? "Your school";

  const [stats, teachers] = await Promise.all([
    fetchSchoolAdminStats(supabase, schoolName),
    fetchSchoolTeacherSummaries(supabase, schoolName),
  ]);

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">School admin</h1>
        <p className="mt-1 text-sm text-slate-500">
          Read-only overview for <strong>{schoolName}</strong>. Scanning stays on teacher phones.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Teachers" value={stats.teacherCount} />
        <StatCard label="Classes" value={stats.sectionCount} />
        <StatCard label="Students" value={stats.studentCount} />
        <StatCard label="Scans synced" value={stats.scanCount} />
      </div>

      <Card title="Teachers in your school" className="mt-6">
        {teachers.length === 0 ? (
          <p className="text-sm text-slate-500">
            No teachers found. Ensure each teacher profile has the same school name ({schoolName}).
          </p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">Teacher</th>
                  <th className="px-2 py-2 text-left">Role</th>
                  <th className="px-2 py-2 text-left">Classes</th>
                  <th className="px-2 py-2 text-left">Students</th>
                  <th className="px-2 py-2 text-left">Keys</th>
                  <th className="px-2 py-2 text-left">Scans</th>
                </tr>
              </thead>
              <tbody>
                {teachers.map((teacher) => (
                  <tr key={teacher.id} className="border-b border-slate-100">
                    <td className="px-2 py-2">
                      <div className="font-semibold text-slate-800">{teacher.full_name}</div>
                      {teacher.id === user.id ? (
                        <div className="text-xs text-emerald-600">You</div>
                      ) : null}
                    </td>
                    <td className="px-2 py-2 capitalize">{teacher.role.replace("_", " ")}</td>
                    <td className="px-2 py-2">{teacher.sectionCount}</td>
                    <td className="px-2 py-2">{teacher.studentCount}</td>
                    <td className="px-2 py-2">{teacher.subjectCount}</td>
                    <td className="px-2 py-2">{teacher.scanCount}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card title="Setup note" className="mt-4">
        <p className="text-sm leading-relaxed text-slate-600">
          Admin access requires running <code className="text-xs">supabase/add_admin_rls.sql</code> in Supabase,
          then setting your profile role to <strong>school_admin</strong>. Teachers only see their own data;
          admins see aggregated school-wide stats here.
        </p>
        <Link href="/dashboard/sync-check" className="mt-3 inline-block text-sm font-bold text-emerald-700 hover:underline">
          Run sync check for your account →
        </Link>
      </Card>
    </>
  );
}
