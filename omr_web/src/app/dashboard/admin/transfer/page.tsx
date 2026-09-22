import Link from "next/link";
import { fetchSchoolTeacherSummaries } from "@/lib/api/admin";
import { requireSuperAdminSession } from "@/lib/api/session";
import { Card } from "@/components/ui/card";
import { TransferSuperAdminPanel } from "./transfer-super-admin-panel";

export default async function TransferSuperAdminPage() {
  const { user, profile, api } = await requireSuperAdminSession();
  const schoolName = profile.school_name?.trim() ?? "";

  let teachers: Awaited<ReturnType<typeof fetchSchoolTeacherSummaries>> = [];
  let cloudSlow = false;

  if (schoolName) {
    try {
      teachers = await fetchSchoolTeacherSummaries(api, schoolName, user.id);
    } catch {
      cloudSlow = true;
    }
  }

  return (
    <>
      <div className="mb-6">
        <p className="text-sm font-semibold text-emerald-700">
          <Link href="/dashboard/admin" className="hover:underline">
            ← School overview
          </Link>
        </p>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Transfer super admin</h1>
        <p className="mt-1 text-sm text-slate-500">
          Move school-wide admin control to another approved instructor. Requires password and email verification.
        </p>
      </div>

      {cloudSlow ? (
        <div className="mb-4 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
          School server is busy — refresh in a minute.
        </div>
      ) : null}

      {!schoolName ? (
        <Card className="border-amber-200 bg-amber-50">
          <p className="text-sm text-amber-900">Your profile needs a school name before you can transfer.</p>
        </Card>
      ) : (
        <Card title="Verification required">
          <TransferSuperAdminPanel
            candidates={teachers}
            currentEmail={user.email ?? ""}
          />
        </Card>
      )}
    </>
  );
}
