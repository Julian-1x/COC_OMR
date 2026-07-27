"use client";

import { useRouter } from "next/navigation";
import { useMemo, useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import type { DepartmentAdminRow, SchoolTeacherSummary } from "@/lib/api/admin";
import { COC_DEPARTMENTS } from "@/lib/coc-school";
import { makeDeptAdminAction, revokeDeptAdminAction } from "./actions";

export function DepartmentAdminsPanel({
  admins,
  candidates,
  departments = [...COC_DEPARTMENTS],
}: {
  admins: DepartmentAdminRow[];
  candidates: SchoolTeacherSummary[];
  departments?: string[];
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [teacherId, setTeacherId] = useState("");
  const [department, setDepartment] = useState(departments[0] ?? "COE");
  const [isPending, startTransition] = useTransition();

  const assignable = useMemo(() => {
    const adminIds = new Set(admins.map((row) => row.id));
    return candidates.filter(
      (teacher) =>
        teacher.status !== "you" &&
        teacher.accessStatus === "approved" &&
        !adminIds.has(teacher.id) &&
        teacher.role !== "super_admin" &&
        teacher.role !== "admin" &&
        teacher.role !== "school_admin" &&
        teacher.role !== "dept_admin",
    );
  }, [admins, candidates]);

  function run(
    id: string,
    action: () => Promise<{ ok: true } | { ok: false; error: string }>,
  ) {
    setError(null);
    setPendingId(id);
    startTransition(async () => {
      const result = await action();
      setPendingId(null);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setTeacherId("");
      router.refresh();
    });
  }

  return (
    <div className="space-y-6">
      {error ? (
        <p className="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm font-semibold text-red-700">
          {error}
        </p>
      ) : null}

      <section className="rounded-2xl border border-emerald-200 bg-emerald-50/50 p-4">
        <h2 className="text-lg font-extrabold text-slate-800">Assign department admin</h2>
        <p className="mt-1 text-sm text-slate-600">
          Pick an approved instructor. They can approve and revoke teachers in that department only.
        </p>
        {assignable.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No eligible instructors. Approve teachers first on Access control.
          </p>
        ) : (
          <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end">
            <label className="block flex-1 text-sm font-semibold text-slate-700">
              Instructor
              <select
                className="mt-1 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                value={teacherId}
                onChange={(event) => setTeacherId(event.target.value)}
              >
                <option value="">Select…</option>
                {assignable.map((teacher) => (
                  <option key={teacher.id} value={teacher.id}>
                    {teacher.full_name}
                    {teacher.email ? ` (${teacher.email})` : ""}
                    {teacher.department ? ` · ${teacher.department}` : ""}
                  </option>
                ))}
              </select>
            </label>
            <label className="block w-full text-sm font-semibold text-slate-700 sm:w-36">
              Department
              <select
                className="mt-1 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-800"
                value={department}
                onChange={(event) => setDepartment(event.target.value)}
              >
                {departments.map((code) => (
                  <option key={code} value={code}>
                    {code}
                  </option>
                ))}
              </select>
            </label>
            <Button
              type="button"
              disabled={!teacherId || (isPending && pendingId === teacherId)}
              onClick={() =>
                run(teacherId, () => makeDeptAdminAction(teacherId, department))
              }
            >
              {isPending && pendingId === teacherId ? "Assigning…" : "Assign"}
            </Button>
          </div>
        )}
      </section>

      <section className="rounded-2xl border border-slate-200 bg-white p-4">
        <h2 className="text-lg font-extrabold text-slate-800">Current department admins</h2>
        <p className="mt-1 text-sm text-slate-600">
          Remove power to return them to a normal approved instructor.
        </p>
        {admins.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">No department admins yet.</p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">Name</th>
                  <th className="px-2 py-2 text-left">Email</th>
                  <th className="px-2 py-2 text-left">Department</th>
                  <th className="px-2 py-2 text-left" />
                </tr>
              </thead>
              <tbody>
                {admins.map((admin) => (
                  <tr key={admin.id} className="border-b border-slate-100">
                    <td className="px-2 py-2 font-semibold text-slate-800">{admin.full_name}</td>
                    <td className="px-2 py-2 text-slate-600">{admin.email ?? "—"}</td>
                    <td className="px-2 py-2 text-slate-600">{admin.department ?? "—"}</td>
                    <td className="px-2 py-2 text-right">
                      <Button
                        type="button"
                        variant="secondary"
                        disabled={isPending && pendingId === admin.id}
                        onClick={() => run(admin.id, () => revokeDeptAdminAction(admin.id))}
                      >
                        {isPending && pendingId === admin.id ? "Removing…" : "Remove power"}
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
