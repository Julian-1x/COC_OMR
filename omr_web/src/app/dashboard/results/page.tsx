import { fetchScanResults, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { ResultsContent } from "./results-content";

export default async function ResultsPage() {
  const { supabase } = await requireTeacherSession();
  const [scans, students, subjects] = await Promise.all([
    fetchScanResults(supabase),
    fetchStudents(supabase),
    fetchSubjects(supabase),
  ]);

  return <ResultsContent scans={scans} students={students} subjects={subjects} />;
}
