import { fetchScanResults, fetchSections, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { schoolYearOptions } from "@/lib/academic-term";
import { ResultsContent } from "./results-content";

export default async function ResultsPage({
  searchParams,
}: {
  searchParams: Promise<{ view?: string; year?: string }>;
}) {
  const { view, year } = await searchParams;
  const showArchived = view === "archived";
  const schoolYear = year?.trim() || undefined;
  const { supabase } = await requireTeacherSession();
  const [scans, students, subjects, sections] = await Promise.all([
    fetchScanResults(supabase),
    fetchStudents(supabase),
    fetchSubjects(supabase),
    fetchSections(supabase, { archived: showArchived ? true : false, schoolYear }),
  ]);

  const allowedSectionNames = new Set(sections.map((section) => section.name));

  return (
    <ResultsContent
      scans={scans}
      students={students.filter((student) => allowedSectionNames.has(student.section_name))}
      subjects={subjects}
      sections={sections}
      showArchived={showArchived}
      schoolYear={schoolYear}
      yearOptions={schoolYearOptions()}
    />
  );
}
