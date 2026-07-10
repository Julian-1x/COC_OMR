import { fetchScanResults, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { AnalysisContent } from "./analysis-content";

export default async function ItemAnalysisPage() {
  const { api } = await requireTeacherSession();
  const [scans, students, subjects] = await Promise.all([
    fetchScanResults(api),
    fetchStudents(api),
    fetchSubjects(api),
  ]);

  return <AnalysisContent scans={scans} students={students} subjects={subjects} />;
}
