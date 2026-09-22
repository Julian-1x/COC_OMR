"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { resignSuperAdmin, transferSuperAdmin } from "@/lib/api/admin";
import { API_TOKEN_COOKIE, ApiError } from "@/lib/api/laravel-client";
import { requireSuperAdminSession } from "@/lib/api/session";

async function clearWebSessionCookie(): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.set(API_TOKEN_COOKIE, "", {
    path: "/",
    maxAge: 0,
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });
}

export async function transferSuperAdminAction(input: {
  targetTeacherId: string;
  targetEmail: string;
  currentPassword: string;
  confirmation: string;
}): Promise<{ ok: true; message: string } | { ok: false; error: string }> {
  try {
    const { api } = await requireSuperAdminSession();
    const result = await transferSuperAdmin(api, input);
    await clearWebSessionCookie();
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

export async function resignSuperAdminAction(input: {
  currentPassword: string;
  confirmation: string;
}): Promise<{ ok: true; message: string } | { ok: false; error: string }> {
  try {
    const { api } = await requireSuperAdminSession();
    const result = await resignSuperAdmin(api, input);
    await clearWebSessionCookie();
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
      error: error instanceof Error ? error.message : "Could not resign super admin.",
    };
  }
}
