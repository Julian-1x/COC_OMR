"use server";

import { revalidatePath } from "next/cache";
import { requireTeacherSession } from "@/lib/api/session";
import {
  archiveSection,
  unarchiveSection,
  updateSectionMeta,
} from "@/lib/api/data";
import { commonTermLabels } from "@/lib/academic-term";

function revalidateSectionPaths(sectionName?: string) {
  revalidatePath("/dashboard/classes");
  revalidatePath("/dashboard/results");
  revalidatePath("/dashboard");
  if (sectionName) {
    revalidatePath(`/dashboard/classes/${encodeURIComponent(sectionName)}`);
  }
}

export async function restoreSection(name: string) {
  const { api } = await requireTeacherSession();
  const trimmed = name.trim();
  if (!trimmed) {
    throw new Error("Section name is required.");
  }

  await unarchiveSection(api, trimmed);
  revalidateSectionPaths(trimmed);
  return { ok: true };
}

export async function archiveSectionAction(
  name: string,
  meta?: { schoolYear?: string; termLabel?: string },
) {
  const { api } = await requireTeacherSession();
  const trimmed = name.trim();
  if (!trimmed) {
    throw new Error("Section name is required.");
  }

  const term = meta?.termLabel?.trim();
  if (term && !(commonTermLabels as readonly string[]).includes(term)) {
    throw new Error("Term must be 1st Sem, 2nd Sem, or Summer.");
  }

  await archiveSection(api, trimmed, {
    schoolYear: meta?.schoolYear?.trim() || undefined,
    termLabel: term || undefined,
  });
  revalidateSectionPaths(trimmed);
  return { ok: true };
}

export async function updateSectionTermAction(input: {
  sectionId: string;
  sectionName: string;
  schoolYear: string;
  termLabel: string;
}) {
  const { api } = await requireTeacherSession();
  const sectionId = input.sectionId.trim();
  const sectionName = input.sectionName.trim();
  const schoolYear = input.schoolYear.trim();
  const termLabel = input.termLabel.trim();

  if (!sectionId || !sectionName) {
    throw new Error("Section is required.");
  }
  if (!schoolYear) {
    throw new Error("Choose a school year.");
  }
  if (!(commonTermLabels as readonly string[]).includes(termLabel)) {
    throw new Error("Choose 1st Sem or 2nd Sem (or Summer if needed).");
  }

  await updateSectionMeta(api, sectionId, { schoolYear, termLabel });
  revalidateSectionPaths(sectionName);
  return { ok: true };
}
