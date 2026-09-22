"use client";

import { useMemo, useState, useTransition } from "react";
import type { SchoolTeacherSummary } from "@/lib/api/admin";
import { isSuperAdminRole } from "@/lib/api/admin";
import { resignSuperAdminAction, transferSuperAdminAction } from "./actions";

export function TransferSuperAdminPanel({
  candidates,
  currentEmail,
}: {
  candidates: SchoolTeacherSummary[];
  currentEmail: string;
}) {
  const [pending, startTransition] = useTransition();
  const [targetId, setTargetId] = useState("");
  const [targetEmail, setTargetEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [resignPassword, setResignPassword] = useState("");
  const [resignConfirm, setResignConfirm] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [resignError, setResignError] = useState<string | null>(null);

  const otherSuperAdmins = useMemo(
    () =>
      candidates.filter(
        (t) =>
          t.email &&
          t.accessStatus === "approved" &&
          isSuperAdminRole(t.role) &&
          t.email.toLowerCase() !== currentEmail.toLowerCase(),
      ),
    [candidates, currentEmail],
  );

  const eligible = useMemo(
    () =>
      candidates.filter(
        (t) =>
          t.email &&
          t.accessStatus === "approved" &&
          t.email.toLowerCase() !== currentEmail.toLowerCase() &&
          (!isSuperAdminRole(t.role) || otherSuperAdmins.some((s) => s.id === t.id)),
      ),
    [candidates, currentEmail, otherSuperAdmins],
  );

  const selected = eligible.find((t) => t.id === targetId) ?? null;
  const keepName = otherSuperAdmins[0]?.full_name ?? "the other super admin";

  function onTransfer(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!targetId || !selected?.email) {
      setError("Select the teacher who will become super admin.");
      return;
    }
    if (targetEmail.trim().toLowerCase() !== selected.email.toLowerCase()) {
      setError("Type the recipient email exactly to verify.");
      return;
    }
    if (!password) {
      setError("Enter your current password.");
      return;
    }
    if (confirmation.trim().toUpperCase() !== "TRANSFER") {
      setError("Type TRANSFER in capital letters to confirm.");
      return;
    }

    startTransition(async () => {
      const result = await transferSuperAdminAction({
        targetTeacherId: targetId,
        targetEmail: targetEmail.trim(),
        currentPassword: password,
        confirmation: confirmation.trim(),
      });
      if (!result.ok) {
        setError(result.error);
        return;
      }
      window.location.replace("/login?notice=super-admin-transferred");
    });
  }

  function onResign(e: React.FormEvent) {
    e.preventDefault();
    setResignError(null);

    if (!resignPassword) {
      setResignError("Enter your current password.");
      return;
    }
    if (resignConfirm.trim().toUpperCase() !== "RESIGN") {
      setResignError("Type RESIGN in capital letters to confirm.");
      return;
    }

    startTransition(async () => {
      const result = await resignSuperAdminAction({
        currentPassword: resignPassword,
        confirmation: resignConfirm.trim(),
      });
      if (!result.ok) {
        setResignError(result.error);
        return;
      }
      // Cookie already cleared in the server action — go straight to login
      // so a parallel 401 cannot overwrite the success notice with error=session.
      window.location.replace("/login?notice=super-admin-transferred");
    });
  }

  return (
    <div className="space-y-8">
      {otherSuperAdmins.length > 0 ? (
        <form
          onSubmit={onResign}
          className="space-y-4 rounded-xl border-2 border-emerald-300 bg-emerald-50/60 p-4"
        >
          <div>
            <p className="text-sm font-extrabold text-emerald-950">
              Fix dual super admin — resign now
            </p>
            <p className="mt-1 text-sm text-emerald-900">
              {keepName} already has super admin. Use this to step down immediately.
              Logout alone cannot change your role.
            </p>
          </div>

          <label className="block text-sm font-bold text-slate-700">
            Your current password
            <input
              type="password"
              autoComplete="current-password"
              className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-sm"
              value={resignPassword}
              onChange={(e) => setResignPassword(e.target.value)}
              disabled={pending}
              required
            />
          </label>

          <label className="block text-sm font-bold text-slate-700">
            Type RESIGN to confirm
            <input
              type="text"
              autoComplete="off"
              className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-sm font-mono tracking-wide"
              placeholder="RESIGN"
              value={resignConfirm}
              onChange={(e) => setResignConfirm(e.target.value)}
              disabled={pending}
              required
            />
          </label>

          {resignError ? (
            <p className="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
              {resignError}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={pending}
            className="rounded-xl bg-emerald-800 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-emerald-900 disabled:opacity-60"
          >
            {pending ? "Resigning…" : "Resign super admin"}
          </button>
        </form>
      ) : null}

      <form onSubmit={onTransfer} className="space-y-4">
        <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">
          <p className="font-bold">Or transfer to someone else</p>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            <li>You become a regular approved instructor.</li>
            <li>The recipient becomes the only school super admin.</li>
            <li>You are signed out right away so the new role applies.</li>
          </ul>
        </div>

        {eligible.length === 0 ? (
          <p className="text-sm text-slate-600">
            No eligible recipients yet. Approve another instructor first, then return here.
          </p>
        ) : (
          <>
            <label className="block text-sm font-bold text-slate-700">
              New super admin
              <select
                className="mt-1 w-full rounded-xl border border-slate-300 bg-white px-3 py-2.5 text-sm font-semibold text-slate-800"
                value={targetId}
                onChange={(e) => {
                  const next = e.target.value;
                  setTargetId(next);
                  setTargetEmail("");
                  if (eligible.find((t) => t.id === next)) setError(null);
                }}
                disabled={pending}
              >
                <option value="">Select teacher…</option>
                {eligible.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.full_name}
                    {t.email ? ` · ${t.email}` : ""}
                    {isSuperAdminRole(t.role) ? " (already super admin)" : ""}
                  </option>
                ))}
              </select>
            </label>

            <label className="block text-sm font-bold text-slate-700">
              Type their email to verify
              <input
                type="email"
                autoComplete="off"
                className="mt-1 w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm"
                placeholder={selected?.email ?? "name@phinmaed.com"}
                value={targetEmail}
                onChange={(e) => setTargetEmail(e.target.value)}
                disabled={pending || !targetId}
                required
              />
            </label>

            <label className="block text-sm font-bold text-slate-700">
              Your current password
              <input
                type="password"
                autoComplete="current-password"
                className="mt-1 w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={pending}
                required
              />
            </label>

            <label className="block text-sm font-bold text-slate-700">
              Type TRANSFER to confirm
              <input
                type="text"
                autoComplete="off"
                className="mt-1 w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm font-mono tracking-wide"
                placeholder="TRANSFER"
                value={confirmation}
                onChange={(e) => setConfirmation(e.target.value)}
                disabled={pending}
                required
              />
            </label>

            {error ? (
              <p className="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
                {error}
              </p>
            ) : null}

            <button
              type="submit"
              disabled={pending || eligible.length === 0}
              className="rounded-xl bg-red-700 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-red-800 disabled:opacity-60"
            >
              {pending ? "Transferring…" : "Transfer super admin"}
            </button>
          </>
        )}
      </form>
    </div>
  );
}
