import Link from "next/link";
import { isSuperAdmin } from "@/lib/api/admin";
import { requireAdminSession } from "@/lib/api/session";
import { AccessControlContent } from "./access-control-content";

export default async function AdminAccessPage() {
  const { user, profile, api: _api } = await requireAdminSession();
  const schoolName = profile.school_name?.trim() ?? "";
  const viewerIsSuperAdmin = isSuperAdmin(profile, user);

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
        <p className="mt-2 text-xs text-slate-500">
          Pending requests never expire — teachers can wait until an admin approves them.
        </p>
      </div>

      {!schoolName ? (
        <div className="rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          Your admin profile needs school name <strong>Cagayan de Oro College</strong>. Run{" "}
          <code className="rounded bg-white px-1">php artisan omr:promote-admin your@email</code> on
          the API host.
        </div>
      ) : (
        <AccessControlContent schoolName={schoolName} profile={profile} user={user} />
      )}
    </>
  );
}
