"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import type { SchoolTeacherSummary } from "@/lib/api/admin";
import { isSuperAdminRole } from "@/lib/api/admin";
import { transferSuperAdminAction } from "./actions";

export function TransferSuperAdminPanel({
  candidates,
  currentEmail,
}: {
  candidates: SchoolTeacherSummary[];
  currentEmail: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [targetId, setTargetId] = useState("");
  const [targetEmail, setTargetEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [doneMessage, setDoneMessage] = useState<string | null>(null);

  const eligible = useMemo(
    () =>
      candidates.filter(
        (t) =>
          t.email &&
          t.accessStatus === "approved" &&
          !isSuperAdminRole(t.role) &&
          t.email.toLowerCase() !== currentEmail.toLowerCase(),
      ),
    [candidates, currentEmail],
  );

  const selected = eligible.find((t) => t.id === targetId) ?? null;

  function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setDoneMessage(null);

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
      setError('Type TRANSFER in capital letters to confirm.');
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
      setDoneMessage(result.message);
      setPassword("");
      setConfirmation("");
      // Tokens were revoked — force a clean sign-in.
      await fetch("/auth/signout", { method: "POST" });
      router.push("/login?notice=super-admin-transferred");
      router.refresh();
    });
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <div className="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-950">
        <p className="font-bold">This permanently moves school-wide super admin power.</p>
        <ul className="mt-2 list-disc space-y-1 pl-5">
          <li>You become a regular approved instructor.</li>
          <li>The recipient becomes the only super admin from this transfer.</li>
          <li>Both of you must sign in again afterward.</li>
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
                const match = eligible.find((t) => t.id === next);
                setTargetEmail("");
                if (match) setError(null);
              }}
              disabled={pending}
            >
              <option value="">Select teacher…</option>
              {eligible.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.full_name}
                  {t.email ? ` · ${t.email}` : ""}
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
          {doneMessage ? (
            <p className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-900">
              {doneMessage}
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
  );
}
