"use server";

import { revalidatePath } from "next/cache";
import { requireTeacherSession } from "@/lib/api/session";
import {
  fetchSectionStudentCounts,
  fetchStudents,
  upsertSection,
  upsertStudentsBatch,
} from "@/lib/api/data";
import { buildImportPlan, type ImportRow } from "@/lib/import/roster";

export async function commitRosterImport(rows: ImportRow[]) {
  const { user, supabase } = await requireTeacherSession();
  const existing = await fetchStudents(supabase);
  const plan = buildImportPlan(rows, existing);

  await upsertStudentsBatch(
    supabase,
    user.id,
    plan.toUpsert.map((r) => ({
      school_id: r.schoolId,
      omr_id: r.omrId,
      name: r.name,
      section_name: r.section,
    })),
  );

  const counts = await fetchSectionStudentCounts(supabase);
  const sectionNames = new Set([
    ...existing.map((s) => s.section_name),
    ...plan.toUpsert.map((r) => r.section),
  ]);
  for (const sectionName of sectionNames) {
    await upsertSection(supabase, user.id, sectionName, counts.get(sectionName) ?? 0);
  }

  revalidatePath("/dashboard");
  revalidatePath("/dashboard/classes");
  revalidatePath("/dashboard/settings");
  revalidatePath("/dashboard/results");

  return {
    newCount: plan.toUpsert.filter((r) => r.isNew).length,
    updatedCount: plan.toUpsert.filter((r) => !r.isNew).length,
    unchanged: plan.unchanged,
  };
}
