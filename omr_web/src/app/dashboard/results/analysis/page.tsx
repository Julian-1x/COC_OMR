import { fetchScanResults, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { AnalysisContent } from "./analysis-content";

export default async function ItemAnalysisPage() {
  const { supabase } = await requireTeacherSession();
  const [scans, students, subjects] = await Promise.all([
    fetchScanResults(supabase),
    fetchStudents(supabase),
    fetchSubjects(supabase),
  ]);

  return <AnalysisContent scans={scans} students={students} subjects={subjects} />;
}
