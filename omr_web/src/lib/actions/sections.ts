"use server";

import { revalidatePath } from "next/cache";
import { requireTeacherSession } from "@/lib/api/session";
import { unarchiveSection } from "@/lib/api/data";

export async function restoreSection(name: string) {
  const { api } = await requireTeacherSession();
  const trimmed = name.trim();
  if (!trimmed) {
    throw new Error("Section name is required.");
  }

  await unarchiveSection(api, trimmed);

  revalidatePath("/dashboard/classes");
  revalidatePath("/dashboard/results");
  revalidatePath("/dashboard");
  return { ok: true };
}
