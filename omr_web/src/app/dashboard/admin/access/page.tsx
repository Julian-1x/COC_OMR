import Link from "next/link";
import {
  fetchAccessRequests,
  fetchSchoolTeacherSummaries,
  isSuperAdmin,
} from "@/lib/api/admin";
import { requireAdminSession } from "@/lib/api/session";
import { AccessControlPanel } from "./access-control-panel";

export default async function AdminAccessPage() {
  const { user, profile, api } = await requireAdminSession();
  const schoolName = profile.school_name?.trim() ?? "";
  const viewerIsSuperAdmin = isSuperAdmin(profile, user);

  let pending: Awaited<ReturnType<typeof fetchAccessRequests>> = [];
  let teachers: Awaited<ReturnType<typeof fetchSchoolTeacherSummaries>> = [];
  let cloudSlow = false;

  if (schoolName) {
    try {
      [pending, teachers] = await Promise.all([
        fetchAccessRequests(api),
        fetchSchoolTeacherSummaries(api, schoolName, user.id),
      ]);
    } catch {
      cloudSlow = true;
    }
  }

  const approved = teachers.filter(
    (teacher) =>
      teacher.accessStatus === "approved" ||
      (!teacher.accessStatus && teacher.status !== "pending" && teacher.status !== "revoked"),
  );
  const revoked = teachers.filter((teacher) => teacher.accessStatus === "revoked");

  return (
    <>
      <div className="mb-6">
        <p className="text-sm font-semibold text-emerald-700">
          <Link href="/dashboard/admin" className="hover:underline">
            ← School overview
          </Link>
        </p>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Access control</h1>
        <p className="mt-1 text-sm text-slate-500">
          {viewerIsSuperAdmin
            ? "Approve or revoke any COC instructor."
            : `Approve or revoke instructors in ${profile.department ?? "your department"}.`}
        </p>
      </div>

      {cloudSlow ? (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          School server is slow or waking up. Open{" "}
          <a
            className="font-semibold underline"
            href="https://coc-omr-api.onrender.com/up"
            target="_blank"
            rel="noreferrer"
          >
            API status
          </a>
          , wait for Application up, then tap Try again / refresh this page.
        </div>
      ) : null}

      {!schoolName ? (
        <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Your admin profile needs school name <strong>Cagayan de Oro College</strong>. Run{" "}
          <code className="rounded bg-white px-1">php artisan omr:promote-admin your@email</code> on
          the API host.
        </div>
      ) : (
        <AccessControlPanel
          pending={pending}
          approved={approved}
          revoked={revoked}
          viewerIsSuperAdmin={viewerIsSuperAdmin}
          viewerDepartment={profile.department}
        />
      )}
    </>
  );
}
