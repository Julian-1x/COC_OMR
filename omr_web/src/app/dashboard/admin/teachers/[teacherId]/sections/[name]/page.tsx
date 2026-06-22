import Link from "next/link";
import { notFound } from "next/navigation";
import { Card } from "@/components/ui/card";
import { fetchSectionStudentsForAdmin, fetchTeacherProfileForAdmin } from "@/lib/api/admin";
import { requireAdminSession } from "@/lib/api/session";

export default async function AdminSectionRosterPage({
  params,
}: {
  params: Promise<{ teacherId: string; name: string }>;
}) {
  const { teacherId, name } = await params;
  const sectionName = decodeURIComponent(name);
  const { profile, supabase } = await requireAdminSession();
  const schoolName = profile.school_name?.trim() ?? null;

  const teacher = await fetchTeacherProfileForAdmin(supabase, teacherId, schoolName);
  if (!teacher) notFound();

  const students = await fetchSectionStudentsForAdmin(supabase, teacherId, sectionName, schoolName);
  if (students === null) notFound();

  return (
    <>
      <div className="mb-4">
        <Link
          href={`/dashboard/admin/teachers/${teacherId}`}
          className="text-sm font-bold text-emerald-700 hover:underline"
        >
          ← {teacher.full_name}
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">{sectionName}</h1>
        <p className="mt-1 text-sm text-slate-500">
          Read-only list · {students.length} students
        </p>
      </div>

      <Card>
        {students.length === 0 ? (
          <p className="text-sm text-slate-500">No students in this section yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">OMR ID</th>
                  <th className="px-2 py-2 text-left">Name</th>
                  <th className="px-2 py-2 text-left">Student ID</th>
                </tr>
              </thead>
              <tbody>
                {students.map((student) => (
                  <tr key={student.id} className="border-b border-slate-100">
                    <td className="px-2 py-2 font-mono font-bold text-emerald-800">{student.omr_id}</td>
                    <td className="px-2 py-2 font-semibold text-slate-800">{student.name}</td>
                    <td className="px-2 py-2">{student.school_id}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}
