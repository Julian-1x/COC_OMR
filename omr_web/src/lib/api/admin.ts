import { ApiError, type ApiClient, type ApiUser } from "@/lib/api/laravel-client";
import type { DbStudent, DbTeacherProfile } from "@/lib/types/database";

export function normalizeRole(role: string | null | undefined): string {
  return role?.trim().toLowerCase() ?? "";
}

export function isAccessApproved(
  profile: DbTeacherProfile | null | undefined,
): boolean {
  if (!profile) return false;
  if (profile.is_active === false) return false;
  const status = (profile.access_status ?? "approved").toLowerCase();
  return status === "approved";
}

/** Super admin or legacy school_admin/admin aliases. */
export function isSuperAdminRole(role: string | null | undefined): boolean {
  const r = normalizeRole(role);
  return r === "super_admin" || r === "admin" || r === "school_admin";
}

export function isDeptAdminRole(role: string | null | undefined): boolean {
  return normalizeRole(role) === "dept_admin";
}

/** Anyone who can open Admin desk (super or department admin). */
export function isAccessAdminRole(role: string | null | undefined): boolean {
  return isSuperAdminRole(role) || isDeptAdminRole(role);
}

export function isSuperAdmin(
  profile: DbTeacherProfile | null,
  _user?: Pick<ApiUser, "id"> | null,
): boolean {
  return isAccessApproved(profile) && isSuperAdminRole(profile?.role);
}

export function isDeptAdmin(
  profile: DbTeacherProfile | null,
  _user?: Pick<ApiUser, "id"> | null,
): boolean {
  return isAccessApproved(profile) && isDeptAdminRole(profile?.role);
}

/** @deprecated Prefer isSuperAdmin / isDeptAdmin / isAccessAdminRole. */
export function isSchoolAdmin(
  profile: DbTeacherProfile | null,
  _user?: Pick<ApiUser, "id"> | null,
): boolean {
  if (!isAccessApproved(profile)) return false;
  return isAccessAdminRole(profile?.role);
}

export function roleDisplayLabel(role: string | null | undefined): string {
  const r = normalizeRole(role);
  if (isSuperAdminRole(r)) return "Super admin";
  if (isDeptAdminRole(r)) return "Dept admin";
  return "Instructor";
}

export type TeacherMonitorStatus =
  | "you"
  | "active"
  | "no_sync"
  | "pending"
  | "revoked";

export type AccessStatus = "pending" | "approved" | "revoked";

export type SchoolTeacherSummary = {
  id: string;
  full_name: string;
  email: string | null;
  role: string;
  accessStatus: AccessStatus | string;
  department?: string | null;
  sectionCount: number;
  studentCount: number;
  subjectCount: number;
  scanCount: number;
  pendingReviewCount: number;
  lastCloudUpdate: string | null;
  status: TeacherMonitorStatus;
};

export type AccessRequestTeacher = {
  id: string;
  full_name: string;
  email: string | null;
  role: string;
  access_status: AccessStatus | string;
  school_name: string | null;
  department?: string | null;
  created_at: string | null;
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
  access_status?: string;
  department?: string | null;
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
    accessStatus: row.access_status ?? "approved",
    department: row.department,
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
    case "pending":
      return "Pending approval";
    case "revoked":
      return "Revoked";
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

export async function fetchAccessRequests(
  api: ApiClient,
): Promise<AccessRequestTeacher[]> {
  const { teachers } = await api.get<{ teachers: AccessRequestTeacher[] }>(
    "/admin/access-requests",
  );
  return teachers ?? [];
}

export async function approveTeacherAccess(
  api: ApiClient,
  teacherId: string,
): Promise<void> {
  await api.post(`/admin/teachers/${teacherId}/approve`);
}

export async function revokeTeacherAccess(
  api: ApiClient,
  teacherId: string,
): Promise<void> {
  await api.post(`/admin/teachers/${teacherId}/revoke`);
}

export async function deleteTeacherAccount(
  api: ApiClient,
  teacherId: string,
): Promise<void> {
  await api.delete(`/admin/teachers/${teacherId}`);
}

export type DepartmentAdminRow = {
  id: string;
  full_name: string;
  email: string | null;
  department: string | null;
  access_status: AccessStatus | string;
  role: string;
};

export async function fetchDepartmentAdmins(api: ApiClient): Promise<{
  departments: string[];
  admins: DepartmentAdminRow[];
}> {
  const payload = await api.get<{
    departments: string[];
    admins: DepartmentAdminRow[];
  }>("/admin/department-admins");
  return {
    departments: payload.departments ?? [],
    admins: payload.admins ?? [],
  };
}

export async function makeDepartmentAdmin(
  api: ApiClient,
  teacherId: string,
  department: string,
): Promise<void> {
  await api.post(`/admin/teachers/${teacherId}/make-dept-admin`, { department });
}

export async function revokeDepartmentAdmin(
  api: ApiClient,
  teacherId: string,
): Promise<void> {
  await api.post(`/admin/teachers/${teacherId}/revoke-dept-admin`);
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

export type AuthEventRow = {
  id: string;
  user_id: string | null;
  email: string;
  event: string;
  ip_address: string | null;
  user_agent: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
};

export async function fetchAuthEvents(
  api: ApiClient,
  filters?: { email?: string; event?: string; limit?: number },
): Promise<AuthEventRow[]> {
  const { events } = await api.get<{ events: AuthEventRow[] }>("/admin/auth-events", {
    params: {
      email: filters?.email,
      event: filters?.event,
      limit: filters?.limit ?? 100,
    },
  });
  return events ?? [];
}
