"use server";

import { revalidatePath } from "next/cache";
import { makeDepartmentAdmin, revokeDepartmentAdmin } from "@/lib/api/admin";
import { requireSuperAdminSession } from "@/lib/api/session";

export async function makeDeptAdminAction(
  teacherId: string,
  department: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    const { api } = await requireSuperAdminSession();
    await makeDepartmentAdmin(api, teacherId, department);
    revalidatePath("/dashboard/admin");
    revalidatePath("/dashboard/admin/access");
    revalidatePath("/dashboard/admin/departments");
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Could not assign department admin.",
    };
  }
}

export async function revokeDeptAdminAction(
  teacherId: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    const { api } = await requireSuperAdminSession();
    await revokeDepartmentAdmin(api, teacherId);
    revalidatePath("/dashboard/admin");
    revalidatePath("/dashboard/admin/access");
    revalidatePath("/dashboard/admin/departments");
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Could not remove department admin.",
    };
  }
}
