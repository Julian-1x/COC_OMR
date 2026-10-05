"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Archive } from "lucide-react";
import {
  commonTermLabels,
  schoolYearOptions,
} from "@/lib/academic-term";
import {
  archiveSectionAction,
  updateSectionTermAction,
} from "@/lib/actions/sections";

export function SectionTermControls({
  sectionId,
  sectionName,
  schoolYear,
  termLabel,
  archived,
}: {
  sectionId: string;
  sectionName: string;
  schoolYear?: string | null;
  termLabel?: string | null;
  archived: boolean;
}) {
  const router = useRouter();
  const yearOptions = schoolYearOptions();
  const [year, setYear] = useState(schoolYear ?? yearOptions[Math.min(2, yearOptions.length - 1)] ?? "");
  const [term, setTerm] = useState(termLabel ?? "1st Sem");
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function saveTerm() {
    setError(null);
    setMessage(null);
    startTransition(async () => {
      try {
        await updateSectionTermAction({
          sectionId,
          sectionName,
          schoolYear: year,
          termLabel: term,
        });
        setMessage("School year and semester saved.");
        router.refresh();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not save term.");
      }
    });
  }

  function archiveClass() {
    const confirmed = window.confirm(
      `Archive "${sectionName}"?\n\n` +
        `It moves to Classes → Archived. Scores stay on the web.\n` +
        `Restore within 4 months — after that it is permanently deleted.\n` +
        `Phone teachers lose this class after Sync Now until you restore it.`,
    );
    if (!confirmed) return;

    setError(null);
    setMessage(null);
    startTransition(async () => {
      try {
        await archiveSectionAction(sectionName, {
          schoolYear: year || undefined,
          termLabel: term || undefined,
        });
        setMessage("Archived. Restore within 4 months from Classes → Archived.");
        router.refresh();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not archive.");
      }
    });
  }

  return (
    <div className="mb-4 rounded-2xl border border-slate-200 bg-white p-4">
      <p className="text-xs font-extrabold uppercase tracking-wide text-slate-500">
        School year & semester
      </p>
      <p className="mt-1 text-sm text-slate-600">
        Every school year has <strong>1st Sem</strong> and <strong>2nd Sem</strong>. Summer is optional.
      </p>
      <div className="mt-3 flex flex-wrap items-end gap-2">
        <label className="text-sm font-semibold text-slate-700">
          School year
          <select
            value={year}
            onChange={(e) => setYear(e.target.value)}
            disabled={archived || isPending}
            className="mt-1 block rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold"
          >
            {year && !yearOptions.includes(year) ? (
              <option value={year}>{year}</option>
            ) : null}
            {yearOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
        <label className="text-sm font-semibold text-slate-700">
          Semester
          <select
            value={term}
            onChange={(e) => setTerm(e.target.value)}
            disabled={archived || isPending}
            className="mt-1 block rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold"
          >
            {commonTermLabels.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>
        {!archived ? (
          <>
            <button
              type="button"
              onClick={saveTerm}
              disabled={isPending}
              className="rounded-xl bg-emerald-500 px-3 py-2 text-sm font-bold text-white hover:bg-emerald-600 disabled:opacity-60"
            >
              {isPending ? "Saving…" : "Save term"}
            </button>
            <button
              type="button"
              onClick={archiveClass}
              disabled={isPending}
              className="inline-flex items-center gap-1.5 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-sm font-bold text-amber-900 hover:border-amber-300 disabled:opacity-60"
            >
              <Archive className="h-3.5 w-3.5" />
              Archive class
            </button>
          </>
        ) : (
          <p className="text-sm font-semibold text-slate-500">
            This class is archived. Restore it from Classes → Archived.
          </p>
        )}
      </div>
      {message ? <p className="mt-2 text-sm font-semibold text-emerald-700">{message}</p> : null}
      {error ? <p className="mt-2 text-sm font-semibold text-red-600">{error}</p> : null}
    </div>
  );
}
