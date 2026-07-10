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

export async function commitRosterImport(
  rows: ImportRow[],
  meta?: { schoolYear: string; termLabel: string },
) {
  const { user, api } = await requireTeacherSession();
  const existing = await fetchStudents(api);
  const plan = buildImportPlan(rows, existing);

  await upsertStudentsBatch(
    api,
    user.id,
    plan.toUpsert.map((r) => ({
      school_id: r.schoolId,
      omr_id: r.omrId,
      name: r.name,
      section_name: r.section,
    })),
  );

  const counts = await fetchSectionStudentCounts(api);
  const sectionNames = new Set([
    ...existing.map((s) => s.section_name),
    ...plan.toUpsert.map((r) => r.section),
  ]);
  for (const sectionName of sectionNames) {
    await upsertSection(api, user.id, sectionName, counts.get(sectionName) ?? 0, meta);
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
