import { Suspense } from "react";
import { fetchScanResults, fetchSections, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { schoolYearOptions } from "@/lib/academic-term";
import { ResultsContent } from "./results-content";

export default async function ResultsPage({
  searchParams,
}: {
  searchParams: Promise<{ view?: string; year?: string; review?: string }>;
}) {
  const { view, year, review } = await searchParams;
  const showArchived = view === "archived";
  const schoolYear = year?.trim() || undefined;
  const reviewFilter =
    review === "pending" || review === "passed" || review === "failed" ? review : "";
  const { api } = await requireTeacherSession();
  const [scans, students, subjects, sections] = await Promise.all([
    fetchScanResults(api),
    fetchStudents(api),
    fetchSubjects(api),
    fetchSections(api, { archived: showArchived ? true : false, schoolYear }),
  ]);

  const allowedSectionNames = new Set(sections.map((section) => section.name));

  return (
    <Suspense fallback={<p className="text-sm text-slate-500">Loading results…</p>}>
      <ResultsContent
        scans={scans}
        students={students}
        subjects={subjects}
        sections={sections}
        allowedSectionNames={allowedSectionNames}
        showArchived={showArchived}
        schoolYear={schoolYear}
        yearOptions={schoolYearOptions()}
        initialReviewFilter={reviewFilter}
      />
    </Suspense>
  );
}
