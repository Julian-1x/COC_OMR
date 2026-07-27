"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import {
  isAccessAdminRole,
  isDeptAdminRole,
  isSuperAdminRole,
  roleDisplayLabel,
  type AccessRequestTeacher,
  type SchoolTeacherSummary,
} from "@/lib/api/admin";
import { approveTeacherAction, revokeTeacherAction } from "./actions";

export function AccessControlPanel({
  pending,
  approved,
  revoked,
  viewerIsSuperAdmin = false,
  viewerDepartment = null,
}: {
  pending: AccessRequestTeacher[];
  approved: SchoolTeacherSummary[];
  revoked: SchoolTeacherSummary[];
  viewerIsSuperAdmin?: boolean;
  viewerDepartment?: string | null;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function run(
    teacherId: string,
    action: (id: string) => Promise<{ ok: true } | { ok: false; error: string }>,
  ) {
    setError(null);
    setPendingId(teacherId);
    startTransition(async () => {
      const result = await action(teacherId);
      setPendingId(null);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      router.refresh();
    });
  }

  const scopeHint = viewerIsSuperAdmin
    ? "All COC departments."
    : viewerDepartment
      ? `Your department: ${viewerDepartment}.`
      : "Your department only.";

  return (
    <div className="space-y-6">
      {error ? (
        <p className="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm font-semibold text-red-700">
          {error}
        </p>
      ) : null}

      <section className="rounded-2xl border border-amber-200 bg-amber-50/60 p-4">
        <h2 className="text-lg font-extrabold text-slate-800">Pending approval</h2>
        <p className="mt-1 text-sm text-slate-600">
          These teachers registered and confirmed email. Approve them to unlock the app and web
          dashboard. {scopeHint}
        </p>
        {pending.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">No pending requests.</p>
        ) : (
          <ul className="mt-4 space-y-3">
            {pending.map((teacher) => (
              <li
                key={teacher.id}
                className="flex flex-col gap-3 rounded-xl border border-amber-200 bg-white px-3 py-3 sm:flex-row sm:items-center sm:justify-between"
              >
                <div>
                  <p className="font-bold text-slate-800">{teacher.full_name}</p>
                  <p className="text-sm text-slate-500">
                    {teacher.email ?? "No email"}
                    {teacher.department ? ` · ${teacher.department}` : ""}
                  </p>
                </div>
                <Button
                  type="button"
                  disabled={isPending && pendingId === teacher.id}
                  onClick={() => run(teacher.id, approveTeacherAction)}
                >
                  {isPending && pendingId === teacher.id ? "Approving…" : "Approve"}
                </Button>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="rounded-2xl border border-slate-200 bg-white p-4">
        <h2 className="text-lg font-extrabold text-slate-800">Approved teachers</h2>
        <p className="mt-1 text-sm text-slate-600">
          Revoke to cut off app and web access immediately. Admin accounts are managed separately.
        </p>
        {approved.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">No approved teachers yet.</p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">Teacher</th>
                  <th className="px-2 py-2 text-left">Email</th>
                  <th className="px-2 py-2 text-left">Dept</th>
                  <th className="px-2 py-2 text-left">Role</th>
                  <th className="px-2 py-2 text-left" />
                </tr>
              </thead>
              <tbody>
                {approved.map((teacher) => {
                  const protectedAdmin = isAccessAdminRole(teacher.role);
                  const blockHint = isSuperAdminRole(teacher.role)
                    ? "Super admin"
                    : isDeptAdminRole(teacher.role)
                      ? "Dept admin"
                      : "Admin";
                  return (
                    <tr key={teacher.id} className="border-b border-slate-100">
                      <td className="px-2 py-2 font-semibold text-slate-800">
                        {teacher.full_name}
                      </td>
                      <td className="px-2 py-2 text-slate-600">{teacher.email ?? "—"}</td>
                      <td className="px-2 py-2 text-slate-600">{teacher.department ?? "—"}</td>
                      <td className="px-2 py-2 text-slate-600">
                        {roleDisplayLabel(teacher.role)}
                      </td>
                      <td className="px-2 py-2 text-right">
                        {teacher.status === "you" || protectedAdmin ? (
                          <span className="text-xs font-semibold text-slate-400">
                            {teacher.status === "you" ? "You" : blockHint}
                          </span>
                        ) : (
                          <Button
                            type="button"
                            variant="secondary"
                            disabled={isPending && pendingId === teacher.id}
                            onClick={() => run(teacher.id, revokeTeacherAction)}
                          >
                            {isPending && pendingId === teacher.id ? "Revoking…" : "Revoke"}
                          </Button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {revoked.length > 0 ? (
        <section className="rounded-2xl border border-slate-200 bg-white p-4">
          <h2 className="text-lg font-extrabold text-slate-800">Revoked</h2>
          <p className="mt-1 text-sm text-slate-600">You can approve again to restore access.</p>
          <ul className="mt-4 space-y-3">
            {revoked.map((teacher) => (
              <li
                key={teacher.id}
                className="flex flex-col gap-3 rounded-xl border border-slate-200 px-3 py-3 sm:flex-row sm:items-center sm:justify-between"
              >
                <div>
                  <p className="font-bold text-slate-800">{teacher.full_name}</p>
                  <p className="text-sm text-slate-500">
                    {teacher.email ?? "No email"}
                    {teacher.department ? ` · ${teacher.department}` : ""}
                  </p>
                </div>
                <Button
                  type="button"
                  disabled={isPending && pendingId === teacher.id}
                  onClick={() => run(teacher.id, approveTeacherAction)}
                >
                  {isPending && pendingId === teacher.id ? "Restoring…" : "Approve again"}
                </Button>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
