import { unstable_noStore as noStore } from "next/cache";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { DbSection, DbStudent, DbSubject, DbScanResult, DbTeacherProfile } from "@/lib/types/database";

const now = () => new Date().toISOString();

const PROFILE_COLUMNS =
  "id, full_name, role, is_active, school_name, created_at, updated_at";

async function fetchProfileFromTable(
  supabase: SupabaseClient,
  id: string,
): Promise<DbTeacherProfile | null> {
  const { data, error } = await supabase
    .from("teacher_profiles")
    .select(PROFILE_COLUMNS)
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return data as DbTeacherProfile | null;
}

async function fetchProfileViaRpc(
  supabase: SupabaseClient,
): Promise<DbTeacherProfile | null> {
  const { data, error } = await supabase.rpc("get_my_teacher_profile").maybeSingle();
  if (error) {
    // RPC not installed yet — fall back to table read.
    if (error.code === "PGRST202" || error.message.includes("get_my_teacher_profile")) {
      return null;
    }
    throw error;
  }
  return data as DbTeacherProfile | null;
}

export async function fetchProfile(
  supabase: SupabaseClient,
  userId?: string,
): Promise<DbTeacherProfile | null> {
  noStore();
  let id = userId;
  if (!id) {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return null;
    id = user.id;
  }

  const rpcProfile = await fetchProfileViaRpc(supabase);
  if (rpcProfile) return rpcProfile;

  return fetchProfileFromTable(supabase, id);
}

export async function fetchSections(supabase: SupabaseClient): Promise<DbSection[]> {
  const { data, error } = await supabase.from("sections").select("*").order("name");
  if (error) throw error;
  return (data ?? []) as DbSection[];
}

export async function fetchStudents(supabase: SupabaseClient, sectionName?: string): Promise<DbStudent[]> {
  let query = supabase.from("students").select("*").order("name");
  if (sectionName) query = query.eq("section_name", sectionName);
  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as DbStudent[];
}

export async function fetchSectionStudentCounts(
  supabase: SupabaseClient,
): Promise<Map<string, number>> {
  const { data, error } = await supabase.from("students").select("section_name");
  if (error) throw error;
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    const section = String(row.section_name ?? "");
    if (!section) continue;
    counts.set(section, (counts.get(section) ?? 0) + 1);
  }
  return counts;
}

export async function fetchSubjects(supabase: SupabaseClient): Promise<DbSubject[]> {
  const { data, error } = await supabase.from("subjects").select("*").order("name");
  if (error) throw error;
  return (data ?? []) as DbSubject[];
}

export async function fetchSubject(supabase: SupabaseClient, localId: string): Promise<DbSubject | null> {
  const { data, error } = await supabase
    .from("subjects")
    .select("*")
    .eq("local_id", localId)
    .maybeSingle();
  if (error) throw error;
  return data as DbSubject | null;
}

export async function fetchScanResults(supabase: SupabaseClient): Promise<DbScanResult[]> {
  const { data, error } = await supabase
    .from("scan_results")
    .select("*")
    .order("scan_time", { ascending: false });
  if (error) throw error;
  return (data ?? []) as DbScanResult[];
}

export async function upsertSection(
  supabase: SupabaseClient,
  ownerId: string,
  name: string,
  studentCount?: number,
) {
  const row = {
    owner_teacher_id: ownerId,
    name,
    student_count: studentCount ?? null,
    local_id: name,
    sync_status: "synced",
    updated_at: now(),
  };
  const { data, error } = await supabase
    .from("sections")
    .upsert(row, { onConflict: "owner_teacher_id,name" })
    .select()
    .single();
  if (error) throw error;
  return data as DbSection;
}

export async function upsertStudent(
  supabase: SupabaseClient,
  ownerId: string,
  student: Pick<DbStudent, "school_id" | "omr_id" | "name" | "section_name">,
) {
  const row = {
    owner_teacher_id: ownerId,
    school_id: student.school_id,
    omr_id: student.omr_id,
    name: student.name,
    section_name: student.section_name,
    local_id: student.omr_id,
    sync_status: "synced",
    updated_at: now(),
  };
  const { data, error } = await supabase
    .from("students")
    .upsert(row, { onConflict: "owner_teacher_id,omr_id" })
    .select()
    .single();
  if (error) throw error;
  return data as DbStudent;
}

export async function upsertSubject(
  supabase: SupabaseClient,
  ownerId: string,
  subject: Omit<DbSubject, "id" | "owner_teacher_id" | "created_at" | "sync_status"> & { sync_status?: string },
) {
  const row = {
    owner_teacher_id: ownerId,
    local_id: subject.local_id,
    name: subject.name,
    answer_key: subject.answer_key,
    total_questions: subject.total_questions,
    section_names: subject.section_names,
    section_qr_data: subject.section_qr_data ?? {},
    exam_date: subject.exam_date,
    passing_score: subject.passing_score,
    use_partial_credit: subject.use_partial_credit,
    sync_status: "synced",
    updated_at: now(),
  };
  const { data, error } = await supabase
    .from("subjects")
    .upsert(row, { onConflict: "owner_teacher_id,local_id" })
    .select()
    .single();
  if (error) throw error;
  return data as DbSubject;
}

export async function deleteSubject(supabase: SupabaseClient, localId: string) {
  const { error } = await supabase.from("subjects").delete().eq("local_id", localId);
  if (error) throw error;
}

export async function deleteStudent(supabase: SupabaseClient, omrId: string) {
  const { error } = await supabase.from("students").delete().eq("omr_id", omrId);
  if (error) throw error;
}

export type DashboardStats = {
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
  pendingReview: number;
};

async function countRows(
  supabase: SupabaseClient,
  table: "sections" | "students" | "subjects" | "scan_results",
  filter?: { column: string; value: boolean },
): Promise<number> {
  let query = supabase.from(table).select("*", { count: "exact", head: true });
  if (filter) query = query.eq(filter.column, filter.value);
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

export async function fetchDashboardStats(supabase: SupabaseClient): Promise<DashboardStats> {
  const [sectionCount, studentCount, subjectCount, scanCount, pendingReview] = await Promise.all([
    countRows(supabase, "sections"),
    countRows(supabase, "students"),
    countRows(supabase, "subjects"),
    countRows(supabase, "scan_results", { column: "needs_review", value: false }),
    countRows(supabase, "scan_results", { column: "needs_review", value: true }),
  ]);
  return {
    sectionCount,
    studentCount,
    subjectCount,
    scanCount,
    pendingReview,
  };
}

export async function fetchCloudLastUpdated(supabase: SupabaseClient): Promise<string | null> {
  const tables = ["sections", "students", "subjects", "scan_results"] as const;
  const timestamps: string[] = [];
  await Promise.all(
    tables.map(async (table) => {
      const { data, error } = await supabase
        .from(table)
        .select("updated_at")
        .order("updated_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (!error && data?.updated_at) timestamps.push(String(data.updated_at));
    }),
  );
  if (timestamps.length === 0) return null;
  return timestamps.sort().at(-1) ?? null;
}

export async function upsertStudentsBatch(
  supabase: SupabaseClient,
  ownerId: string,
  students: Pick<DbStudent, "school_id" | "omr_id" | "name" | "section_name">[],
) {
  if (students.length === 0) return;
  const ts = now();
  const rows = students.map((student) => ({
    owner_teacher_id: ownerId,
    school_id: student.school_id,
    omr_id: student.omr_id,
    name: student.name,
    section_name: student.section_name,
    local_id: student.omr_id,
    sync_status: "synced",
    updated_at: ts,
  }));
  const chunkSize = 100;
  for (let i = 0; i < rows.length; i += chunkSize) {
    const chunk = rows.slice(i, i + chunkSize);
    const { error } = await supabase
      .from("students")
      .upsert(chunk, { onConflict: "owner_teacher_id,omr_id" });
    if (error) throw error;
  }
}

export function displaySectionStudentCount(
  liveCount: number | undefined,
  cachedCount: number | null | undefined,
): { count: number; rosterPending: boolean } {
  const live = liveCount ?? 0;
  const cached = cachedCount ?? 0;
  if (live === 0 && cached > 0) {
    return { count: cached, rosterPending: true };
  }
  return { count: live > 0 ? live : cached, rosterPending: false };
}
