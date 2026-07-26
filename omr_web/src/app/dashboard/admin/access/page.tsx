import Link from "next/link";
import {
  fetchAccessRequests,
  fetchSchoolTeacherSummaries,
} from "@/lib/api/admin";
import { requireAdminSession } from "@/lib/api/session";
import { AccessControlPanel } from "./access-control-panel";

export default async function AdminAccessPage() {
  const { user, profile, api } = await requireAdminSession();
  const schoolName = profile.school_name?.trim() ?? "";

  const [pending, teachers] = schoolName
    ? await Promise.all([
        fetchAccessRequests(api),
        fetchSchoolTeacherSummaries(api, schoolName, user.id),
      ])
    : [[], []];

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
          Decide which COC teachers may use the phone app and this web portal.
        </p>
      </div>

      {!schoolName ? (
        <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Your admin profile needs school name <strong>Cagayan de Oro College</strong>. Run{" "}
          <code className="rounded bg-white px-1">php artisan omr:promote-admin your@email</code> on
          the API host.
        </div>
      ) : (
        <AccessControlPanel pending={pending} approved={approved} revoked={revoked} />
      )}
    </>
  );
}
