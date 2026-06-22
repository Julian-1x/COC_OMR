import type { SupabaseClient } from "@supabase/supabase-js";
import type { User } from "@supabase/supabase-js";
import type { DbStudent, DbTeacherProfile } from "@/lib/types/database";

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

export type TeacherMonitorStatus = "you" | "active" | "no_sync";

export type SchoolTeacherSummary = {
  id: string;
  full_name: string;
  email: string | null;
  role: string;
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
  pendingReviewCount: number;
  lastCloudUpdate: string | null;
  status: TeacherMonitorStatus;
};

export type SchoolAdminStats = {
  teacherCount: number;
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
  pendingReview: number;
  teachersWithNoScans: number;
};

export type TeacherAdminSection = {
  name: string;
  studentCount: number;
};

export type TeacherAdminDetail = {
  teacher: DbTeacherProfile;
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
  pendingReviewCount: number;
  lastCloudUpdate: string | null;
  sections: TeacherAdminSection[];
};

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

async function latestUpdateForTeacher(
  supabase: SupabaseClient,
  teacherId: string,
): Promise<string | null> {
  const tables = ["sections", "students", "subjects", "scan_results"] as const;
  const timestamps = await Promise.all(
    tables.map(async (table) => {
      const { data, error } = await supabase
        .from(table)
        .select("updated_at")
        .eq("owner_teacher_id", teacherId)
        .order("updated_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (error) throw error;
      return data?.updated_at ? String(data.updated_at) : null;
    }),
  );
  const valid = timestamps.filter((t): t is string => t != null);
  if (valid.length === 0) return null;
  return valid.sort().at(-1) ?? null;
}

function teacherStatus(
  teacherId: string,
  currentUserId: string,
  sectionCount: number,
  studentCount: number,
  scanCount: number,
): TeacherMonitorStatus {
  if (teacherId === currentUserId) return "you";
  if (sectionCount === 0 && studentCount === 0 && scanCount === 0) return "no_sync";
  return "active";
}

export function teacherStatusLabel(status: TeacherMonitorStatus): string {
  switch (status) {
    case "you":
      return "You";
    case "no_sync":
      return "Not started";
    default:
      return "Active";
  }
}

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

export async function fetchSchoolTeacherSummaries(
  supabase: SupabaseClient,
  schoolName: string,
  currentUserId: string,
): Promise<SchoolTeacherSummary[]> {
  const teachers = await fetchSchoolTeachers(supabase, schoolName);
  const summaries = await Promise.all(
    teachers.map(async (teacher) => {
      const [sectionCount, studentCount, subjectCount, scanCount, pendingReviewCount, lastCloudUpdate] =
        await Promise.all([
          countForTeacher(supabase, "sections", teacher.id),
          countForTeacher(supabase, "students", teacher.id),
          countForTeacher(supabase, "subjects", teacher.id),
          countForTeacher(supabase, "scan_results", teacher.id, {
            column: "needs_review",
            value: false,
          }),
          countForTeacher(supabase, "scan_results", teacher.id, {
            column: "needs_review",
            value: true,
          }),
          latestUpdateForTeacher(supabase, teacher.id),
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
        pendingReviewCount,
        lastCloudUpdate,
        status: teacherStatus(teacher.id, currentUserId, sectionCount, studentCount, scanCount),
      };
    }),
  );
  return summaries;
}

export async function fetchSchoolAdminStats(
  supabase: SupabaseClient,
  schoolName: string,
  currentUserId: string,
): Promise<SchoolAdminStats> {
  const summaries = await fetchSchoolTeacherSummaries(supabase, schoolName, currentUserId);
  const pendingReview = summaries.reduce((sum, t) => sum + t.pendingReviewCount, 0);
  return {
    teacherCount: summaries.length,
    sectionCount: summaries.reduce((sum, t) => sum + t.sectionCount, 0),
    studentCount: summaries.reduce((sum, t) => sum + t.studentCount, 0),
    subjectCount: summaries.reduce((sum, t) => sum + t.subjectCount, 0),
    scanCount: summaries.reduce((sum, t) => sum + t.scanCount, 0),
    pendingReview,
    teachersWithNoScans: summaries.filter((t) => t.scanCount === 0).length,
  };
}

export async function fetchTeacherProfileForAdmin(
  supabase: SupabaseClient,
  teacherId: string,
  adminSchoolName: string | null,
): Promise<DbTeacherProfile | null> {
  const { data, error } = await supabase
    .from("teacher_profiles")
    .select("*")
    .eq("id", teacherId)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  const teacher = data as DbTeacherProfile;
  if (adminSchoolName && teacher.school_name !== adminSchoolName) return null;
  return teacher;
}

export async function fetchTeacherAdminDetail(
  supabase: SupabaseClient,
  teacherId: string,
  adminSchoolName: string | null,
): Promise<TeacherAdminDetail | null> {
  const teacher = await fetchTeacherProfileForAdmin(supabase, teacherId, adminSchoolName);
  if (!teacher) return null;

  const [sectionCount, studentCount, subjectCount, scanCount, pendingReviewCount, lastCloudUpdate] =
    await Promise.all([
      countForTeacher(supabase, "sections", teacherId),
      countForTeacher(supabase, "students", teacherId),
      countForTeacher(supabase, "subjects", teacherId),
      countForTeacher(supabase, "scan_results", teacherId, {
        column: "needs_review",
        value: false,
      }),
      countForTeacher(supabase, "scan_results", teacherId, {
        column: "needs_review",
        value: true,
      }),
      latestUpdateForTeacher(supabase, teacherId),
    ]);

  const { data: sectionRows, error: sectionError } = await supabase
    .from("sections")
    .select("name")
    .eq("owner_teacher_id", teacherId)
    .order("name");
  if (sectionError) throw sectionError;

  const { data: studentRows, error: studentError } = await supabase
    .from("students")
    .select("section_name")
    .eq("owner_teacher_id", teacherId);
  if (studentError) throw studentError;

  const countsBySection = new Map<string, number>();
  for (const row of studentRows ?? []) {
    const section = String(row.section_name ?? "");
    if (!section) continue;
    countsBySection.set(section, (countsBySection.get(section) ?? 0) + 1);
  }

  const sections: TeacherAdminSection[] = (sectionRows ?? []).map((row) => ({
    name: String(row.name),
    studentCount: countsBySection.get(String(row.name)) ?? 0,
  }));

  return {
    teacher,
    sectionCount,
    studentCount,
    subjectCount,
    scanCount,
    pendingReviewCount,
    lastCloudUpdate,
    sections,
  };
}

export async function fetchSectionStudentsForAdmin(
  supabase: SupabaseClient,
  teacherId: string,
  sectionName: string,
  adminSchoolName: string | null,
): Promise<DbStudent[] | null> {
  const teacher = await fetchTeacherProfileForAdmin(supabase, teacherId, adminSchoolName);
  if (!teacher) return null;

  const { data, error } = await supabase
    .from("students")
    .select("*")
    .eq("owner_teacher_id", teacherId)
    .eq("section_name", sectionName)
    .order("name");
  if (error) throw error;
  return (data ?? []) as DbStudent[];
}
