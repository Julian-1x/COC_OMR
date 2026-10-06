import Link from "next/link";
import { fetchSections, fetchStudents } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { formatSectionTerm } from "@/lib/academic-term";
import { SectionRosterPanel } from "./section-roster-panel";
import { SectionTermControls } from "./section-term-controls";

export default async function SectionDetailPage({
  params,
}: {
  params: Promise<{ name: string }>;
}) {
  const { name } = await params;
  const sectionName = decodeURIComponent(name);
  const { api } = await requireTeacherSession();
  const [students, allActive, allArchived] = await Promise.all([
    fetchStudents(api, sectionName),
    fetchSections(api, { archived: false }),
    fetchSections(api, { archived: true }),
  ]);
  const section =
    allActive.find((s) => s.name === sectionName) ??
    allArchived.find((s) => s.name === sectionName) ??
    null;
  const termLine = section
    ? formatSectionTerm({
        school_year: section.school_year,
        term_label: section.term_label,
      })
    : null;
  const archived = Boolean(section?.archived_at);

  return (
    <>
      <div className="mb-4">
        <Link href="/dashboard/classes" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Back to classes
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">{sectionName}</h1>
        <p className="mt-1 text-sm text-slate-500">
          {students.length} students
          {termLine ? ` · ${termLine}` : ""}
          {archived ? " · Archived" : ""}
        </p>
      </div>

      {section ? (
        <SectionTermControls
          sectionId={section.id}
          sectionName={sectionName}
          schoolYear={section.school_year}
          termLabel={section.term_label}
          archived={archived}
        />
      ) : null}

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
