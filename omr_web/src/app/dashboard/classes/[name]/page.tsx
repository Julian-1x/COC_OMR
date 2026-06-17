import Link from "next/link";
import { fetchStudents } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { SectionRosterPanel } from "./section-roster-panel";

export default async function SectionDetailPage({
  params,
}: {
  params: Promise<{ name: string }>;
}) {
  const { name } = await params;
  const sectionName = decodeURIComponent(name);
  const { supabase } = await requireTeacherSession();
  const students = await fetchStudents(supabase, sectionName);

  return (
    <>
      <div className="mb-4">
        <Link href="/dashboard/classes" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Back to classes
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">{sectionName}</h1>
        <p className="mt-1 text-sm text-slate-500">{students.length} students</p>
      </div>

      <div className="mb-4 flex flex-wrap gap-2">
        <Link
          href={`/dashboard/prepare/omr-ids?section=${encodeURIComponent(sectionName)}`}
          className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm font-bold text-emerald-800"
        >
          Export OMR IDs
        </Link>
        <Link
          href={`/dashboard/prepare/print-sheets?section=${encodeURIComponent(sectionName)}`}
          className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700"
        >
          Print sheets
        </Link>
      </div>

      <SectionRosterPanel sectionName={sectionName} students={students} />
    </>
  );
}
