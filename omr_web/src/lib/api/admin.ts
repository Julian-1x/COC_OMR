import type { SupabaseClient } from "@supabase/supabase-js";
import type { User } from "@supabase/supabase-js";
import type { DbTeacherProfile } from "@/lib/types/database";

export function normalizeRole(role: string | null | undefined): string {
  return role?.trim().toLowerCase() ?? "";
}

export function isSchoolAdmin(
  profile: DbTeacherProfile | null,
  user?: User | null,
): boolean {
  if (profile?.is_active === false) return false;

  const profileRole = normalizeRole(profile?.role);
  if (profileRole === "admin" || profileRole === "school_admin") return true;

  if (!user) return false;
  const metaRole = normalizeRole(
    (user.app_metadata?.role as string | undefined) ??
      (user.user_metadata?.role as string | undefined),
  );
  return metaRole === "admin" || metaRole === "school_admin";
}

export type SchoolTeacherSummary = {
  id: string;
  full_name: string;
  email: string | null;
  role: string;
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
};

export type SchoolAdminStats = {
  teacherCount: number;
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
  pendingReview: number;
};

export async function fetchSchoolTeachers(
  supabase: SupabaseClient,
  schoolName: string,
): Promise<DbTeacherProfile[]> {
  const { data, error } = await supabase
    .from("teacher_profiles")
    .select("*")
    .eq("school_name", schoolName)
    .order("full_name");
  if (error) throw error;
  return (data ?? []) as DbTeacherProfile[];
}

async function countForTeacher(
  supabase: SupabaseClient,
  table: "sections" | "students" | "subjects" | "scan_results",
  teacherId: string,
  filter?: { column: string; value: boolean },
): Promise<number> {
  let query = supabase
    .from(table)
    .select("*", { count: "exact", head: true })
    .eq("owner_teacher_id", teacherId);
  if (filter) query = query.eq(filter.column, filter.value);
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

export async function fetchSchoolTeacherSummaries(
  supabase: SupabaseClient,
  schoolName: string,
): Promise<SchoolTeacherSummary[]> {
  const teachers = await fetchSchoolTeachers(supabase, schoolName);
  const summaries = await Promise.all(
    teachers.map(async (teacher) => {
      const [sectionCount, studentCount, subjectCount, scanCount] = await Promise.all([
        countForTeacher(supabase, "sections", teacher.id),
        countForTeacher(supabase, "students", teacher.id),
        countForTeacher(supabase, "subjects", teacher.id),
        countForTeacher(supabase, "scan_results", teacher.id, {
          column: "needs_review",
          value: false,
        }),
      ]);
      return {
        id: teacher.id,
        full_name: teacher.full_name,
        email: null,
        role: teacher.role,
        sectionCount,
        studentCount,
        subjectCount,
        scanCount,
      };
    }),
  );
  return summaries;
}

export async function fetchSchoolAdminStats(
  supabase: SupabaseClient,
  schoolName: string,
): Promise<SchoolAdminStats> {
  const teachers = await fetchSchoolTeachers(supabase, schoolName);
  const summaries = await fetchSchoolTeacherSummaries(supabase, schoolName);
  return {
    teacherCount: teachers.length,
    sectionCount: summaries.reduce((sum, t) => sum + t.sectionCount, 0),
    studentCount: summaries.reduce((sum, t) => sum + t.studentCount, 0),
    subjectCount: summaries.reduce((sum, t) => sum + t.subjectCount, 0),
    scanCount: summaries.reduce((sum, t) => sum + t.scanCount, 0),
    pendingReview: 0,
  };
}
