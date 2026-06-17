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
import { nextOmrId } from "@/lib/import/roster";

export async function saveStudent(input: {
  school_id: string;
  omr_id?: string;
  name: string;
  section_name: string;
}) {
  const { user, supabase } = await requireTeacherSession();
  const existing = await fetchStudents(supabase);
  const omrId = input.omr_id ?? nextOmrId(existing, new Set());

  await upsertStudent(supabase, user.id, {
    school_id: input.school_id.trim(),
    omr_id: omrId,
    name: input.name.trim(),
    section_name: input.section_name,
  });

  const counts = await fetchSectionStudentCounts(supabase);
  await upsertSection(supabase, user.id, input.section_name, counts.get(input.section_name) ?? 0);

  revalidatePath("/dashboard/classes");
  revalidatePath(`/dashboard/classes/${encodeURIComponent(input.section_name)}`);
  revalidatePath("/dashboard");
  return { omr_id: omrId };
}

export async function removeStudent(omrId: string, sectionName: string) {
  const { user, supabase } = await requireTeacherSession();
  await deleteStudent(supabase, omrId);
  const counts = await fetchSectionStudentCounts(supabase);
  await upsertSection(supabase, user.id, sectionName, counts.get(sectionName) ?? 0);
  revalidatePath("/dashboard/classes");
  revalidatePath(`/dashboard/classes/${encodeURIComponent(sectionName)}`);
  revalidatePath("/dashboard");
}
