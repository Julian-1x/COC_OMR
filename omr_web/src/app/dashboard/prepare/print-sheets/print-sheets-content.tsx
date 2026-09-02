"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { createBrowserApiClient } from "@/lib/api/laravel-client";
import { fetchSections, fetchStudents, fetchSubjects } from "@/lib/api/data";
import { getPublicApiBaseUrl } from "@/lib/api/env";
import { wakeSchoolApi } from "@/lib/api/wake-api";
import type { DbSubject, DbStudent } from "@/lib/types/database";
import { generateAnswerSheetsPdf } from "@/lib/pdf/answer-sheet";
import { getQuestionAnswers } from "@/lib/omr/answer-key";
import { downloadBlob } from "@/lib/utils";

function formatExamDateLabel(examDate: string | null | undefined): string {
  if (!examDate) return "Exam date not set (optional)";
  const dateOnly = examDate.slice(0, 10);
  return `Exam date set (${dateOnly})`;
}

export default function PrintSheetsPage() {
  const searchParams = useSearchParams();
  const [subjects, setSubjects] = useState<DbSubject[]>([]);
  const [sections, setSections] = useState<string[]>([]);
  const [students, setStudents] = useState<DbStudent[]>([]);
  const [subjectId, setSubjectId] = useState("");
  const [sectionName, setSectionName] = useState(searchParams.get("section") ?? "");
  const [copyDialogOpen, setCopyDialogOpen] = useState(false);
  const [copyCount, setCopyCount] = useState(1);
  const [dataLoading, setDataLoading] = useState(true);
  const [dataError, setDataError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [previewError, setPreviewError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      setDataLoading(true);
      setDataError(null);
      try {
        await wakeSchoolApi(getPublicApiBaseUrl(), {
          attempts: 3,
          delayMs: 2000,
          probeTimeoutMs: 30_000,
        });
        const api = createBrowserApiClient();
        const [subjectRows, sectionRows, studentRows] = await Promise.all([
          fetchSubjects(api),
          fetchSections(api),
          fetchStudents(api),
        ]);
        setSubjects(subjectRows);
        const names = sectionRows.map((s) => s.name);
        setSections(names);
        setStudents(studentRows);
        const subjectParam = searchParams.get("subject") ?? "";
        const sectionParam = searchParams.get("section") ?? "";
        if (subjectParam && subjectRows.some((s) => s.local_id === subjectParam)) {
          setSubjectId(subjectParam);
        } else if (subjectRows[0]) {
          setSubjectId((prev) => prev || subjectRows[0].local_id);
        }
        if (sectionParam && names.includes(sectionParam)) {
          setSectionName(sectionParam);
        } else {
          setSectionName((prev) => prev || names[0] || "");
          if (sectionParam && !names.includes(sectionParam)) {
            setError(`Section "${sectionParam}" was not found. Choose a section below.`);
          }
        }
      } catch (err) {
        setDataError(
          err instanceof Error
            ? err.message
            : "Could not load subjects and sections. The server may still be waking up — try Refresh.",
        );
      } finally {
        setDataLoading(false);
      }
    }
    void load();
  }, [searchParams]);

  const subject = subjects.find((s) => s.local_id === subjectId);
  const sectionStudents = students.filter((s) => s.section_name === sectionName);
  const sectionValid = Boolean(sectionName && sections.includes(sectionName));

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
        ok: sectionValid,
        label: "Section selected",
        fix: "/dashboard/prepare/import",
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
  }, [subject, sectionValid, sectionStudents]);

  const blockers = checklist.filter((item) => !item.ok && !item.optional);

  const canPreview = Boolean(subject && sectionValid);

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

  function retryDataLoad() {
    window.location.reload();
  }

  return (
    <>
      <div className="mb-4">
        <Link href="/dashboard/prepare" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Prepare
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Print OMR sheets</h1>
        <p className="mt-1 text-sm text-slate-500">
          Same layout as the phone app (standard 30–100 sheets). Print at 100% scale (Actual size).
          Sheets are blank — students bubble their own OMR ID on exam day. Custom layouts: print from
          the phone only.
        </p>
      </div>

      {dataLoading ? (
        <Card className="mb-4 max-w-5xl border-slate-200 bg-slate-50">
          <p className="text-sm font-semibold text-slate-700">Loading subjects and sections…</p>
          <p className="mt-1 text-xs text-slate-500">
            The school server may take up to a minute to wake up on first visit.
          </p>
        </Card>
      ) : null}

      {dataError ? (
        <Card className="mb-4 max-w-5xl border-red-200 bg-red-50">
          <p className="text-sm font-semibold text-red-700">{dataError}</p>
          <Button type="button" variant="secondary" className="mt-3" onClick={retryDataLoad}>
            Refresh
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
                    <option value="">No subjects yet — create one in Answer keys</option>
                  ) : (
                    subjects.map((s) => (
                      <option key={s.local_id} value={s.local_id}>
                        {s.name}
                      </option>
                    ))
                  )}
                </Select>
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
                  ) : sections.length === 0 ? (
                    <option value="">No sections yet — import a roster</option>
                  ) : (
                    sections.map((s) => (
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
        </div>

        <Card className="flex min-h-[420px] flex-col border-slate-200">
          <p className="mb-1 text-sm font-extrabold text-slate-800">Sheet preview</p>
          <p className="mb-3 text-xs text-slate-500">
            One sample page — same layout as the phone print preview. Print at 100% scale (Actual size).
          </p>
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
