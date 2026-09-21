import { Suspense } from "react";
import { fetchScanResults, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { AnalysisContent } from "./analysis-content";

export default async function ItemAnalysisPage({
  searchParams,
}: {
  searchParams: Promise<{ subject?: string; section?: string }>;
}) {
  const { subject, section } = await searchParams;
  const { api } = await requireTeacherSession();
  const [scans, students, subjects] = await Promise.all([
    fetchScanResults(api, { includeAnswers: true }),
    fetchStudents(api),
    fetchSubjects(api),
  ]);

  return (
    <Suspense fallback={<p className="text-sm text-slate-500">Loading analysis…</p>}>
      <AnalysisContent
        scans={scans}
        students={students}
        subjects={subjects}
        initialSubjectId={subject?.trim() ?? ""}
        initialSection={section?.trim() ?? ""}
      />
    </Suspense>
  );
}
