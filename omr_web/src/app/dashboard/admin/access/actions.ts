"use server";

import { revalidatePath } from "next/cache";
import {
  approveTeacherAccess,
  deleteTeacherAccount,
  revokeTeacherAccess,
} from "@/lib/api/admin";
import { requireAdminSession, requireSuperAdminSession } from "@/lib/api/session";

export async function approveTeacherAction(teacherId: string): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    const { api } = await requireAdminSession();
    await approveTeacherAccess(api, teacherId);
    revalidatePath("/dashboard/admin");
    revalidatePath("/dashboard/admin/access");
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Could not approve teacher.",
    };
  }
}

export async function revokeTeacherAction(teacherId: string): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    const { api } = await requireAdminSession();
    await revokeTeacherAccess(api, teacherId);
    revalidatePath("/dashboard/admin");
    revalidatePath("/dashboard/admin/access");
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Could not revoke teacher.",
    };
  }
}

export async function deleteTeacherAction(
  teacherId: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  try {
    const { api } = await requireSuperAdminSession();
    await deleteTeacherAccount(api, teacherId);
    revalidatePath("/dashboard/admin");
    revalidatePath("/dashboard/admin/access");
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Could not delete teacher.",
    };
  }
}
