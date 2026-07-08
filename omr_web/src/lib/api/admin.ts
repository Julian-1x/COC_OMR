import { ApiError, type ApiClient, type ApiUser } from "@/lib/api/laravel-client";
import type { DbStudent, DbTeacherProfile } from "@/lib/types/database";

export function normalizeRole(role: string | null | undefined): string {
  return role?.trim().toLowerCase() ?? "";
}

export function isSchoolAdmin(
  profile: DbTeacherProfile | null,
  _user?: Pick<ApiUser, "id"> | null,
): boolean {
  if (profile?.is_active === false) return false;

  const profileRole = normalizeRole(profile?.role);
  return profileRole === "admin" || profileRole === "school_admin";
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

type LaravelTeacherSummary = {
  id: string;
  full_name: string;
  email: string | null;
  role: string;
  section_count: number;
  student_count: number;
  subject_count: number;
  scan_count: number;
  pending_review_count: number;
  last_cloud_update: string | null;
  status: TeacherMonitorStatus;
};

function mapTeacherSummary(row: LaravelTeacherSummary): SchoolTeacherSummary {
  return {
    id: row.id,
    full_name: row.full_name,
    email: row.email,
    role: row.role,
    sectionCount: row.section_count,
    studentCount: row.student_count,
    subjectCount: row.subject_count,
    scanCount: row.scan_count,
    pendingReviewCount: row.pending_review_count,
    lastCloudUpdate: row.last_cloud_update,
    status: row.status,
  };
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

export async function fetchSchoolTeacherSummaries(
  api: ApiClient,
  _schoolName: string,
  _currentUserId: string,
): Promise<SchoolTeacherSummary[]> {
  const { teachers } = await api.get<{ teachers: LaravelTeacherSummary[] }>("/admin/teachers");
  return (teachers ?? []).map(mapTeacherSummary);
}

export async function fetchSchoolAdminStats(
  api: ApiClient,
  _schoolName: string,
  _currentUserId: string,
): Promise<SchoolAdminStats> {
  const stats = await api.get<{
    teacher_count: number;
    section_count: number;
    student_count: number;
    subject_count: number;
    scan_count: number;
    pending_review: number;
    teachers_with_no_scans: number;
  }>("/admin/stats");

  return {
    teacherCount: stats.teacher_count,
    sectionCount: stats.section_count,
    studentCount: stats.student_count,
    subjectCount: stats.subject_count,
    scanCount: stats.scan_count,
    pendingReview: stats.pending_review,
    teachersWithNoScans: stats.teachers_with_no_scans,
  };
}

export async function fetchTeacherProfileForAdmin(
  api: ApiClient,
  teacherId: string,
  _adminSchoolName: string | null,
): Promise<DbTeacherProfile | null> {
  try {
    const detail = await fetchTeacherAdminDetail(api, teacherId, _adminSchoolName);
    return detail?.teacher ?? null;
  } catch {
    return null;
  }
}

export async function fetchTeacherAdminDetail(
  api: ApiClient,
  teacherId: string,
  _adminSchoolName: string | null,
): Promise<TeacherAdminDetail | null> {
  try {
    const payload = await api.get<{
      teacher: DbTeacherProfile;
      section_count: number;
      student_count: number;
      subject_count: number;
      scan_count: number;
      pending_review_count: number;
      last_cloud_update: string | null;
      sections: Array<{ name: string; student_count: number }>;
    }>(`/admin/teachers/${teacherId}`);

    return {
      teacher: payload.teacher,
      sectionCount: payload.section_count,
      studentCount: payload.student_count,
      subjectCount: payload.subject_count,
      scanCount: payload.scan_count,
      pendingReviewCount: payload.pending_review_count,
      lastCloudUpdate: payload.last_cloud_update,
      sections: (payload.sections ?? []).map((section) => ({
        name: section.name,
        studentCount: section.student_count,
      })),
    };
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) {
      return null;
    }
    throw error;
  }
}

export async function fetchSectionStudentsForAdmin(
  api: ApiClient,
  teacherId: string,
  sectionName: string,
  _adminSchoolName: string | null,
): Promise<DbStudent[] | null> {
  try {
    const { students } = await api.get<{ students: DbStudent[] }>(
      `/admin/teachers/${teacherId}/sections/${encodeURIComponent(sectionName)}/students`,
    );
    return students ?? [];
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) {
      return null;
    }
    throw error;
  }
}
