import {
  displaySectionStudentCount,
  fetchCloudLastUpdated,
  fetchSections,
  fetchStudents,
  fetchSubjects,
  studentCountsFromRoster,
} from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { PrepareContent } from "./prepare-content";

export default async function PreparePage() {
  const { api } = await requireTeacherSession();

  const [sectionRows, students, subjects, lastUpdated] = await Promise.all([
    fetchSections(api),
    fetchStudents(api),
    fetchSubjects(api),
    fetchCloudLastUpdated(api),
  ]);
  const counts = studentCountsFromRoster(students);

  const sections = sectionRows
    .map((section) => {
      const live = counts.get(section.name);
      const { count, rosterPending } = displaySectionStudentCount(
        live,
        section.student_count,
      );
      return { name: section.name, studentCount: count, rosterPending };
    })
    .sort((a, b) => a.name.localeCompare(b.name));

  return (
    <PrepareContent
      sections={sections}
      studentCount={students.length}
      subjects={subjects}
      lastUpdated={lastUpdated}
    />
  );
}
