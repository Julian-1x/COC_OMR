import { unstable_noStore as noStore } from "next/cache";
import { ApiError, type ApiClient } from "@/lib/api/laravel-client";
import type { DbSection, DbStudent, DbSubject, DbScanResult, DbTeacherProfile } from "@/lib/types/database";

export async function fetchProfile(
  api: ApiClient,
  _userId?: string,
): Promise<DbTeacherProfile | null> {
  noStore();
  const { user } = await api.get<{ user: { profile: DbTeacherProfile | null } }>("/me");
  return user.profile;
}

export type SectionListFilter = {
  archived?: boolean;
  schoolYear?: string;
};

export async function fetchSections(
  api: ApiClient,
  filter: SectionListFilter = {},
): Promise<DbSection[]> {
  const { sections } = await api.get<{ sections: DbSection[] }>("/sections", {
    params: {
      archived: filter.archived,
      school_year: filter.schoolYear,
    },
  });
  return sections ?? [];
}

export async function fetchStudents(api: ApiClient, sectionName?: string): Promise<DbStudent[]> {
  const { students } = await api.get<{ students: DbStudent[] }>("/students", {
    params: { section_name: sectionName },
  });
  return students ?? [];
}

export async function fetchSectionStudentCounts(api: ApiClient): Promise<Map<string, number>> {
  const students = await fetchStudents(api);
  const counts = new Map<string, number>();
  for (const row of students) {
    const section = String(row.section_name ?? "");
    if (!section) continue;
    counts.set(section, (counts.get(section) ?? 0) + 1);
  }
  return counts;
}

export async function fetchSubjects(api: ApiClient): Promise<DbSubject[]> {
  const { subjects } = await api.get<{ subjects: DbSubject[] }>("/subjects");
  return subjects ?? [];
}

export async function fetchSubject(api: ApiClient, localId: string): Promise<DbSubject | null> {
  try {
    const { subject } = await api.get<{ subject: DbSubject }>(
      `/subjects/by-local/${encodeURIComponent(localId)}`,
    );
    return subject ?? null;
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) {
      return null;
    }
    throw error;
  }
}

export async function fetchScanResults(api: ApiClient): Promise<DbScanResult[]> {
  const { scan_results } = await api.get<{ scan_results: DbScanResult[] }>("/scan-results");
  return scan_results ?? [];
}

export async function upsertSection(
  api: ApiClient,
  _ownerId: string,
  name: string,
  studentCount?: number,
  meta?: { schoolYear?: string; termLabel?: string },
) {
  const { section } = await api.post<{ section: DbSection }>("/sections", {
    name,
    student_count: studentCount ?? null,
    school_year: meta?.schoolYear,
    term_label: meta?.termLabel,
  });
  return section;
}

export async function unarchiveSection(api: ApiClient, name: string) {
  const { section } = await api.patch<{ section: DbSection }>(
    "/sync/sections/unarchive",
    { name },
  );
  return section;
}

export async function upsertStudent(
  api: ApiClient,
  _ownerId: string,
  student: Pick<DbStudent, "school_id" | "omr_id" | "name" | "section_name">,
) {
  const { student: row } = await api.post<{ student: DbStudent }>("/students", {
    school_id: student.school_id,
    omr_id: student.omr_id,
    name: student.name,
    section_name: student.section_name,
  });
  return row;
}

export async function upsertSubject(
  api: ApiClient,
  _ownerId: string,
  subject: Omit<DbSubject, "id" | "owner_teacher_id" | "created_at" | "updated_at" | "sync_status"> & {
    sync_status?: string;
  },
) {
  const { subject: row } = await api.post<{ subject: DbSubject }>("/subjects", {
    local_id: subject.local_id,
    name: subject.name,
    answer_key: subject.answer_key,
    total_questions: subject.total_questions,
    section_names: subject.section_names,
    section_qr_data: subject.section_qr_data ?? {},
    exam_date: subject.exam_date,
    passing_score: subject.passing_score,
    use_partial_credit: subject.use_partial_credit,
  });
  return row;
}

export async function deleteSubject(api: ApiClient, localId: string) {
  const subject = await fetchSubject(api, localId);
  if (!subject) return;
  await api.delete(`/subjects/${subject.id}`);
}

export async function deleteStudent(api: ApiClient, omrId: string) {
  const students = await fetchStudents(api);
  const student = students.find((row) => row.omr_id === omrId);
  if (!student) return;
  await api.delete(`/students/${student.id}`);
}

export type DashboardStats = {
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
  pendingReview: number;
};

export async function fetchDashboardStats(api: ApiClient): Promise<DashboardStats> {
  const stats = await api.get<{
    section_count: number;
    student_count: number;
    subject_count: number;
    scan_count: number;
    pending_review: number;
  }>("/dashboard/stats");

  return {
    sectionCount: stats.section_count,
    studentCount: stats.student_count,
    subjectCount: stats.subject_count,
    scanCount: stats.scan_count,
    pendingReview: stats.pending_review,
  };
}

export async function fetchCloudLastUpdated(api: ApiClient): Promise<string | null> {
  const { last_updated } = await api.get<{ last_updated: string | null }>("/dashboard/last-updated");
  return last_updated;
}

export async function upsertStudentsBatch(
  api: ApiClient,
  _ownerId: string,
  students: Pick<DbStudent, "school_id" | "omr_id" | "name" | "section_name">[],
) {
  for (const student of students) {
    await upsertStudent(api, _ownerId, student);
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
