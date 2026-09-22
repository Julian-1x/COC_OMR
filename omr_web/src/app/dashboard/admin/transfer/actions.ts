"use server";

import { revalidatePath } from "next/cache";
import { transferSuperAdmin } from "@/lib/api/admin";
import { ApiError } from "@/lib/api/laravel-client";
import { requireSuperAdminSession } from "@/lib/api/session";

export async function transferSuperAdminAction(input: {
  targetTeacherId: string;
  targetEmail: string;
  currentPassword: string;
  confirmation: string;
}): Promise<{ ok: true; message: string } | { ok: false; error: string }> {
  try {
    const { api } = await requireSuperAdminSession();
    const result = await transferSuperAdmin(api, input);
    revalidatePath("/dashboard");
    revalidatePath("/dashboard/admin");
    revalidatePath("/dashboard/admin/access");
    revalidatePath("/dashboard/settings");
    return { ok: true, message: result.message };
  } catch (error) {
    if (error instanceof ApiError) {
      return { ok: false, error: error.message };
    }
    return {
      ok: false,
      error: error instanceof Error ? error.message : "Could not transfer super admin.",
    };
  }
}
