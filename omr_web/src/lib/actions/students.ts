"use server";

import { revalidatePath } from "next/cache";
import { requireTeacherSession } from "@/lib/api/session";
import {
  deleteStudent,
  fetchSectionStudentCounts,
  fetchStudents,
  upsertSection,
  upsertStudent,
} from "@/lib/api/data";
import { nextOmrId, normalizeSchoolId } from "@/lib/import/roster";
import { normalizePersonName } from "@/lib/person-name";

export async function saveStudent(input: {
  school_id: string;
  omr_id?: string;
  name: string;
  section_name: string;
}) {
  const { user, api } = await requireTeacherSession();
  const existing = await fetchStudents(api);
  const schoolId = normalizeSchoolId(input.school_id);
  if (!schoolId) {
    throw new Error("Student ID is required.");
  }

  const match = existing.find(
    (student) => normalizeSchoolId(student.school_id) === schoolId,
  );
  const omrId = input.omr_id ?? match?.omr_id ?? nextOmrId(existing, new Set());

  await upsertStudent(api, user.id, {
    school_id: schoolId,
    omr_id: omrId,
    name: normalizePersonName(input.name),
    section_name: input.section_name.trim(),
  });

  const counts = await fetchSectionStudentCounts(api);
  await upsertSection(
    api,
    user.id,
    input.section_name.trim(),
    counts.get(input.section_name.trim()) ?? 0,
  );

  revalidatePath("/dashboard/classes");
  revalidatePath(`/dashboard/classes/${encodeURIComponent(input.section_name.trim())}`);
  revalidatePath("/dashboard");
  return { omr_id: omrId };
}

export async function removeStudent(omrId: string, sectionName: string) {
  const { user, api } = await requireTeacherSession();
  await deleteStudent(api, omrId);
  const counts = await fetchSectionStudentCounts(api);
  await upsertSection(api, user.id, sectionName, counts.get(sectionName) ?? 0);
  revalidatePath("/dashboard/classes");
  revalidatePath(`/dashboard/classes/${encodeURIComponent(sectionName)}`);
  revalidatePath("/dashboard");
}
