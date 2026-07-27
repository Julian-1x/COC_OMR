import Link from "next/link";
import {
  fetchDepartmentAdmins,
  fetchSchoolTeacherSummaries,
} from "@/lib/api/admin";
import { requireSuperAdminSession } from "@/lib/api/session";
import { DepartmentAdminsPanel } from "./department-admins-panel";

export default async function DepartmentAdminsPage() {
  const { user, profile, api } = await requireSuperAdminSession();
  const schoolName = profile.school_name?.trim() ?? "";

  const [{ admins, departments }, teachers] = schoolName
    ? await Promise.all([
        fetchDepartmentAdmins(api),
        fetchSchoolTeacherSummaries(api, schoolName, user.id),
      ])
    : [{ admins: [], departments: [] as string[] }, []];

  return (
    <>
      <div className="mb-6">
        <p className="text-sm font-semibold text-emerald-700">
          <Link href="/dashboard/admin" className="hover:underline">
            ← School overview
          </Link>
        </p>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Department admins</h1>
        <p className="mt-1 text-sm text-slate-500">
          Assign instructors who can approve teachers in one department. Only super admins see this
          page.
        </p>
      </div>

      {!schoolName ? (
        <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Your profile needs school name <strong>Cagayan de Oro College</strong>.
        </div>
      ) : (
        <DepartmentAdminsPanel
          admins={admins}
          candidates={teachers}
          departments={departments.length > 0 ? departments : undefined}
        />
      )}
    </>
  );
}
