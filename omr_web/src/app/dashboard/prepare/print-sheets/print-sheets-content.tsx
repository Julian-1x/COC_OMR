"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { AnswerKeyScopeBadge } from "@/components/answer-key-scope-badge";
import { SyncLoopNotice } from "@/components/desk-notices";
import { createBrowserApiClient } from "@/lib/api/laravel-client";
import { fetchSections, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { slowApiLoadingMessage, useSlowApiLoad } from "@/lib/api/use-slow-api-load";
import type { DbSubject, DbStudent } from "@/lib/types/database";
import { generateAnswerSheetsPdf } from "@/lib/pdf/answer-sheet";
import { getQuestionAnswers } from "@/lib/omr/answer-key";
import {
  answerKeyScopeOf,
  filterSubjectsWithLiveSections,
  liveSectionsForSubject,
} from "@/lib/omr/answer-key-scope";
import { canPrintOnWeb, resolvePrintLayout, webPrintBlockedReason } from "@/lib/omr/layout-profile";
import { downloadBlob } from "@/lib/utils";

function formatExamDateLabel(examDate: string | null | undefined): string {
  if (!examDate) return "Exam date not set (optional)";
  const dateOnly = examDate.slice(0, 10);
  return `Exam date set (${dateOnly})`;
}

export default function PrintSheetsPage() {
  const searchParams = useSearchParams();
  const subjectParam = searchParams.get("subject") ?? "";
  const sectionParam = searchParams.get("section") ?? "";
  const [subjects, setSubjects] = useState<DbSubject[]>([]);
  const [sections, setSections] = useState<string[]>([]);
  const [students, setStudents] = useState<DbStudent[]>([]);
  const [subjectId, setSubjectId] = useState("");
  const [sectionName, setSectionName] = useState(searchParams.get("section") ?? "");
  const [copyDialogOpen, setCopyDialogOpen] = useState(false);
  const [copyCount, setCopyCount] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);

  const {
    loading: dataLoading,
    error: dataError,
    attempt: loadAttempt,
    maxAttempts,
    reload: reloadData,
  } = useSlowApiLoad(async () => {
    const api = createBrowserApiClient();
    const [subjectRows, sectionRows, studentRows] = await Promise.all([
      fetchSubjects(api),
      fetchSections(api, { archived: false }),
      fetchStudents(api),
    ]);
    const activeNames = sectionRows.map((s) => s.name);
    // Archived sections stay in cloud history but must not print. Shared keys
    // remain only while at least one linked section is still active.
    const printableSubjects = filterSubjectsWithLiveSections(subjectRows, activeNames);
    setSubjects(printableSubjects);
    setSections(activeNames);
    setStudents(studentRows);
    if (subjectParam && printableSubjects.some((s) => s.local_id === subjectParam)) {
      setSubjectId(subjectParam);
    } else if (printableSubjects[0]) {
      setSubjectId((prev) =>
        printableSubjects.some((s) => s.local_id === prev)
          ? prev
          : printableSubjects[0].local_id,
      );
    } else {
      setSubjectId("");
    }
    if (sectionParam && activeNames.includes(sectionParam)) {
      setSectionName(sectionParam);
    } else {
      setSectionName((prev) =>
        activeNames.includes(prev) ? prev : activeNames[0] || "",
      );
      if (sectionParam && !activeNames.includes(sectionParam)) {
        setError(
          `Section "${sectionParam}" is archived or missing. Choose an active section below.`,
        );
      }
    }
  }, [subjectParam, sectionParam]);

  const subject = subjects.find((s) => s.local_id === subjectId);
  const scope = subject ? answerKeyScopeOf(subject) : null;
  const printableSections = useMemo(
    () => (subject ? liveSectionsForSubject(subject, sections) : sections),
    [subject, sections],
  );

  // Keep section picker on a live linked section when the subject changes.
  useEffect(() => {
    if (printableSections.length === 0) {
      if (sectionName) setSectionName("");
      return;
    }
    if (!printableSections.includes(sectionName)) {
      setSectionName(printableSections[0]);
    }
  }, [subjectId, printableSections, sectionName]);

  const sectionStudents = students.filter((s) => s.section_name === sectionName);
  const sectionValid = Boolean(sectionName && printableSections.includes(sectionName));
  const sectionOnKey = Boolean(subject && scope && scope.allowsSection(sectionName));
  const printReady = Boolean(subject && canPrintOnWeb(subject));
  const printLayoutLabel = (() => {
    if (!subject) return "Select an answer key";
    const fit = resolvePrintLayout(subject);
    if (!fit.ok) return webPrintBlockedReason(subject) ?? "Layout not ready for web print";
    if (fit.profile.isCustom) {
      return `Custom layout (${subject.total_questions} items · ${fit.profile.grid.columns}×${fit.profile.grid.rows}) — web print OK`;
    }
    return `Standard layout (${subject.total_questions} items) — web print OK`;
  })();

  const checklist = useMemo(() => {
    const keyFilled =
      subject &&
      Array.from({ length: subject.total_questions }, (_, i) => i + 1).every((q) => {
        return getQuestionAnswers(subject.answer_key, String(q)).length > 0;
      });

    return [
      {
        ok: Boolean(subject),
        label: "Answer key selected",
        fix: "/dashboard/prepare/answer-keys",
      },
      {
        ok: printReady,
        label: printLayoutLabel,
        fix: subject
          ? `/dashboard/prepare/answer-keys/${subject.local_id}`
          : "/dashboard/prepare/answer-keys",
      },
      {
        ok: Boolean(scope && !scope.isUnassigned),
        label: scope
          ? scope.isUnassigned
            ? "Answer key has no section — link a section before printing"
            : `Key scope: ${scope.badgeLabel}`
          : "Answer key section scope",
        fix: subject
          ? `/dashboard/prepare/answer-keys/${subject.local_id}`
          : "/dashboard/prepare/answer-keys",
      },
      {
        ok: sectionValid && sectionOnKey,
        label:
          sectionValid && sectionOnKey
            ? `Section "${sectionName}" is on this key`
            : sectionValid
              ? `Section "${sectionName}" is not linked to this key — pick a linked section or edit the key`
              : "Active section selected (archived sections are hidden)",
        fix: subject
          ? `/dashboard/prepare/answer-keys/${subject.local_id}`
          : "/dashboard/prepare/import",
      },
      {
        ok: Boolean(keyFilled),
        label: `All ${subject?.total_questions ?? "?"} questions have a correct answer`,
        fix: subject ? `/dashboard/prepare/answer-keys/${subject.local_id}` : "/dashboard/prepare/answer-keys",
      },
      {
        ok: sectionStudents.length > 0,
        label: `Roster: ${sectionStudents.length} student${sectionStudents.length === 1 ? "" : "s"} in this section (sheets stay blank — no names on paper)`,
        fix: "/dashboard/prepare/import",
        optional: sectionStudents.length === 0,
      },
      {
        ok: Boolean(subject?.exam_date),
        label: formatExamDateLabel(subject?.exam_date),
        fix: subject ? `/dashboard/prepare/answer-keys/${subject.local_id}` : undefined,
        optional: !subject?.exam_date,
      },
    ];
  }, [subject, sectionValid, sectionOnKey, sectionStudents, sectionName, scope, printReady, printLayoutLabel]);

  const blockers = checklist.filter((item) => !item.ok && !item.optional);

  const canPreview = Boolean(
    subject && sectionValid && sectionOnKey && printReady && scope && !scope.isUnassigned,
  );

  useEffect(() => {
    if (!canPreview || !subject) {
      setPreviewUrl((prev) => {
        if (prev) URL.revokeObjectURL(prev);
        return null;
      });
      setPreviewError(null);
      return;
    }

    let cancelled = false;
    async function buildPreview() {
      setPreviewLoading(true);
      setPreviewError(null);
      try {
        const bytes = await generateAnswerSheetsPdf(subject!, sectionName, 1);
        if (cancelled) return;
        const blob = new Blob([Uint8Array.from(bytes)], { type: "application/pdf" });
        const url = URL.createObjectURL(blob);
        setPreviewUrl((prev) => {
          if (prev) URL.revokeObjectURL(prev);
          return url;
        });
      } catch (err) {
        if (!cancelled) {
          setPreviewUrl((prev) => {
            if (prev) URL.revokeObjectURL(prev);
            return null;
          });
          setPreviewError(err instanceof Error ? err.message : "Could not build preview.");
        }
      } finally {
        if (!cancelled) setPreviewLoading(false);
      }
    }

    void buildPreview();
    return () => {
      cancelled = true;
    };
  }, [canPreview, subject, sectionName]);

  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  const defaultCopyCount = Math.max(1, sectionStudents.length);

  const generateFullPdf = useCallback(
    async (copies: number) => {
      if (!subject || !sectionValid) {
        throw new Error("Choose a valid subject and section.");
      }
      if (blockers.length > 0) {
        throw new Error("Fix the checklist items below before printing.");
      }
      const count = Math.max(1, Math.min(copies, 200));
      return generateAnswerSheetsPdf(subject, sectionName, count);
    },
    [subject, sectionValid, blockers.length, sectionName],
  );

  function openCopyDialog() {
    if (!subject || blockers.length > 0) {
      setError("Fix the checklist items below before printing.");
      return;
    }
    setError(null);
    setCopyCount(defaultCopyCount);
    setCopyDialogOpen(true);
  }

  async function confirmDownload() {
    if (!subject) return;
    const copies = Math.max(1, Math.min(copyCount, 200));
    setCopyDialogOpen(false);
    setLoading(true);
    setError(null);
    try {
      const bytes = await generateFullPdf(copies);
      downloadBlob(
        new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }),
        `${subject.name}_${sectionName}_${copies}copies.pdf`,
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "PDF failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <div className="mb-4">
        <Link href="/dashboard/prepare" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Prepare
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Print OMR sheets</h1>
        <p className="mt-1 text-sm text-slate-500">
          Students bubble their own OMR ID on exam day.
        </p>
      </div>

      <div className="mb-4 max-w-5xl rounded-2xl border border-emerald-300 bg-emerald-50 px-4 py-3">
        <p className="text-sm font-extrabold text-emerald-950">Print at 100% · Actual size</p>
        <p className="mt-1 text-xs text-emerald-900">
          Do not use Fit to page. Wrong scale breaks scanning.
        </p>
      </div>

      <SyncLoopNotice className="mb-4 max-w-5xl" />

      {dataLoading ? (
        <Card className="mb-4 max-w-5xl border-slate-200 bg-slate-50">
          <p className="text-sm font-semibold text-slate-700">Loading subjects and sections…</p>
          <p className="mt-1 text-xs text-slate-500">{slowApiLoadingMessage(loadAttempt, maxAttempts)}</p>
        </Card>
      ) : null}

      {dataError ? (
        <Card className="mb-4 max-w-5xl border-red-200 bg-red-50">
          <p className="text-sm font-semibold text-red-700">{dataError}</p>
          <p className="mt-1 text-xs text-red-600">
            Automatic retries stopped after {maxAttempts} attempts. Try again when the server is up.
          </p>
          <Button type="button" variant="secondary" className="mt-3" onClick={reloadData}>
            Try again
          </Button>
        </Card>
      ) : null}

      <div className="grid max-w-5xl gap-4 lg:grid-cols-2">
        <div className="space-y-4">
          <Card className="border-slate-200">
            <p className="mb-3 text-sm font-extrabold text-slate-800">Before you print</p>
            <ul className="space-y-2 text-sm">
              {checklist.map((item) => (
                <li key={item.label} className="flex items-start gap-2">
                  <span
                    className={`mt-0.5 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-xs font-bold ${
                      item.ok
                        ? "bg-emerald-100 text-emerald-800"
                        : item.optional
                          ? "bg-slate-100 text-slate-500"
                          : "bg-amber-100 text-amber-900"
                    }`}
                  >
                    {item.ok ? "✓" : item.optional ? "·" : "!"}
                  </span>
                  <span className={item.ok ? "text-slate-700" : item.optional ? "text-slate-500" : "text-amber-950"}>
                    {item.label}
                    {!item.ok && item.fix ? (
                      <>
                        {" "}
                        <Link href={item.fix} className="font-bold text-emerald-700 hover:underline">
                          Fix
                        </Link>
                      </>
                    ) : null}
                  </span>
                </li>
              ))}
            </ul>
          </Card>

          <Card>
            <div className="space-y-3">
              <div>
                <Label htmlFor="subject">Subject</Label>
                <Select
                  id="subject"
                  value={subjectId}
                  disabled={dataLoading}
                  onChange={(e) => setSubjectId(e.target.value)}
                >
                  {dataLoading ? (
                    <option value="">Loading subjects…</option>
                  ) : subjects.length === 0 ? (
                    <option value="">
                      No printable keys — archived sections are hidden until restored
                    </option>
                  ) : (
                    subjects.map((s) => {
                      const sScope = answerKeyScopeOf(s);
                      return (
                        <option key={s.local_id} value={s.local_id}>
                          {s.name} ({sScope.shortBadge})
                        </option>
                      );
                    })
                  )}
                </Select>
                {subject ? <AnswerKeyScopeBadge subject={subject} showSubtitle className="mt-2" /> : null}
              </div>
              <div>
                <Label htmlFor="section">Section</Label>
                <Select
                  id="section"
                  value={sectionName}
                  disabled={dataLoading}
                  onChange={(e) => setSectionName(e.target.value)}
                >
                  {dataLoading ? (
                    <option value="">Loading sections…</option>
                  ) : printableSections.length === 0 ? (
                    <option value="">
                      {sections.length === 0
                        ? "No active sections — import a roster or restore from Classes → Archived"
                        : "No active section still linked to this key (others may be archived)"}
                    </option>
                  ) : (
                    printableSections.map((s) => (
                      <option key={s} value={s}>
                        {s}
                      </option>
                    ))
                  )}
                </Select>
              </div>
              {error ? <p className="text-sm font-semibold text-red-600">{error}</p> : null}
              <Button type="button" disabled={loading || !subject || blockers.length > 0} onClick={openCopyDialog}>
                {loading ? "Generating…" : "Download PDF"}
              </Button>
            </div>
          </Card>

          {sectionName ? (
            <Card title="Also for this class">
              <div className="flex flex-wrap gap-2">
                {subjects
                  .filter(
                    (s) =>
                      s.local_id !== subjectId &&
                      liveSectionsForSubject(s, sections).includes(sectionName),
                  )
                  .map((s) => (
                    <button
                      key={s.local_id}
                      type="button"
                      onClick={() => setSubjectId(s.local_id)}
                      className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-bold text-slate-700 hover:border-emerald-300"
                    >
                      {s.name}
                    </button>
                  ))}
                {subjects.filter(
                  (s) =>
                    s.local_id !== subjectId &&
                    liveSectionsForSubject(s, sections).includes(sectionName),
                ).length === 0 ? (
                  <p className="text-sm text-slate-500">No other printable keys for this class.</p>
                ) : null}
              </div>
              <Link
                href={`/dashboard/prepare/omr-ids?section=${encodeURIComponent(sectionName)}`}
                className="mt-3 inline-block text-sm font-bold text-emerald-700 hover:underline"
              >
                OMR ID handouts for {sectionName} →
              </Link>
            </Card>
          ) : null}
        </div>

        <Card className="flex min-h-[420px] flex-col border-slate-200">
          <p className="mb-1 text-sm font-extrabold text-slate-800">Sheet preview</p>
          <p className="mb-3 text-xs text-slate-500">Sample page — print at 100%</p>
          {previewLoading ? (
            <div className="flex flex-1 items-center justify-center rounded-xl border border-dashed border-slate-200 bg-slate-50 p-8 text-sm text-slate-600">
              Building preview…
            </div>
          ) : previewError ? (
            <div className="flex flex-1 items-center justify-center rounded-xl border border-dashed border-amber-200 bg-amber-50 p-8 text-sm text-amber-900">
              {previewError}
            </div>
          ) : previewUrl ? (
            <iframe
              title="OMR sheet preview"
              src={`${previewUrl}#toolbar=0&navpanes=0`}
              className="min-h-[min(70vh,640px)] w-full flex-1 rounded-xl border border-slate-200 bg-white"
            />
          ) : (
            <div className="flex flex-1 items-center justify-center rounded-xl border border-dashed border-slate-200 bg-slate-50 p-8 text-center text-sm text-slate-500">
              {dataLoading
                ? "Preview will appear after subjects load."
                : canPreview
                  ? "Preview unavailable for this subject."
                  : "Select a subject and section to preview the sheet."}
            </div>
          )}
        </Card>
      </div>

      {copyDialogOpen ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="copy-dialog-title"
        >
          <Card className="w-full max-w-sm border-slate-200 shadow-xl">
            <p id="copy-dialog-title" className="text-base font-extrabold text-slate-800">
              How many copies?
            </p>
            <p className="mt-1 text-sm text-slate-500">
              Each page is one blank OMR sheet. Students bubble their own ID on exam day.
            </p>
            <div className="mt-4">
              <Label htmlFor="copy-count">Number of sheets</Label>
              <Input
                id="copy-count"
                type="number"
                min={1}
                max={200}
                autoFocus
                value={copyCount}
                onChange={(e) => setCopyCount(parseInt(e.target.value, 10) || 1)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") void confirmDownload();
                }}
              />
              {sectionStudents.length > 0 ? (
                <p className="mt-2 text-xs text-slate-500">
                  This section has {sectionStudents.length} roster seat
                  {sectionStudents.length === 1 ? "" : "s"} — default matches roster size.
                </p>
              ) : null}
            </div>
            <div className="mt-5 flex flex-wrap justify-end gap-2">
              <Button type="button" variant="secondary" onClick={() => setCopyDialogOpen(false)}>
                Cancel
              </Button>
              <Button type="button" onClick={() => void confirmDownload()}>
                Download PDF
              </Button>
            </div>
          </Card>
        </div>
      ) : null}
    </>
  );
}
