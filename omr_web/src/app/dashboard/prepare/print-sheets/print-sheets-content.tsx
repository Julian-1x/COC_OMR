"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { createBrowserApiClient } from "@/lib/api/laravel-client";
import { fetchSections, fetchStudents, fetchSubjects } from "@/lib/api/data";
import type { DbSubject, DbStudent } from "@/lib/types/database";
import { generateAnswerSheetsPdf } from "@/lib/pdf/answer-sheet";
import { getQuestionAnswers } from "@/lib/omr/answer-key";
import { downloadBlob } from "@/lib/utils";

export default function PrintSheetsPage() {
  const searchParams = useSearchParams();
  const [subjects, setSubjects] = useState<DbSubject[]>([]);
  const [sections, setSections] = useState<string[]>([]);
  const [students, setStudents] = useState<DbStudent[]>([]);
  const [subjectId, setSubjectId] = useState("");
  const [sectionName, setSectionName] = useState(searchParams.get("section") ?? "");
  const [copies, setCopies] = useState(1);
  const [mode, setMode] = useState<"class" | "blank">("class");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
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
    }
    void load();
  }, [searchParams]);

  const subject = subjects.find((s) => s.local_id === subjectId);
  const sectionStudents = students.filter((s) => s.section_name === sectionName);

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
        ok: Boolean(sectionName && sections.includes(sectionName)),
        label: "Section selected",
        fix: "/dashboard/prepare/import",
      },
      {
        ok: Boolean(keyFilled),
        label: `All ${subject?.total_questions ?? "?"} questions have a correct answer`,
        fix: subject ? `/dashboard/prepare/answer-keys/${subject.local_id}` : "/dashboard/prepare/answer-keys",
      },
      {
        ok: mode === "blank" || sectionStudents.length > 0,
        label:
          mode === "blank"
            ? "Extra copies mode (set count below)"
            : `Roster count: ${sectionStudents.length} blank sheet${sectionStudents.length === 1 ? "" : "s"} (no names on paper)`,
        fix: "/dashboard/prepare/import",
      },
      {
        ok: Boolean(subject?.exam_date),
        label: subject?.exam_date ? `Exam date set (${subject.exam_date})` : "Exam date not set (optional)",
        fix: subject ? `/dashboard/prepare/answer-keys/${subject.local_id}` : undefined,
        optional: !subject?.exam_date,
      },
    ];
  }, [subject, sectionName, sections, sectionStudents, mode]);

  const blockers = checklist.filter((item) => !item.ok && !item.optional);

  async function downloadPdf() {
    if (!subject || !sectionName || !sections.includes(sectionName)) {
      setError("Choose a valid subject and section.");
      return;
    }
    if (blockers.length > 0) {
      setError("Fix the checklist items below before printing.");
      return;
    }
    if (mode === "class" && sectionStudents.length === 0) {
      setError("No students in this section. Import a roster or sync from your phone.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const sheetCount = mode === "class" ? sectionStudents.length : copies;
      const bytes = await generateAnswerSheetsPdf(subject, sectionName, sheetCount);
      downloadBlob(
        new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }),
        `${subject.name}_${sectionName}_${mode}.pdf`,
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
          Same layout as the phone app (standard 30–100 sheets). Print at 100% scale (Actual size).
          Sheets are blank — students bubble their own OMR ID on exam day. Custom layouts: print from
          the phone only.
        </p>
      </div>

      <Card className="mb-4 max-w-xl border-slate-200">
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

      <Card className="max-w-xl">
        <div className="space-y-3">
          <div>
            <Label htmlFor="subject">Subject</Label>
            <Select id="subject" value={subjectId} onChange={(e) => setSubjectId(e.target.value)}>
              {subjects.map((s) => (
                <option key={s.local_id} value={s.local_id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label htmlFor="section">Section</Label>
            <Select id="section" value={sectionName} onChange={(e) => setSectionName(e.target.value)}>
              {sections.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label>Mode</Label>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => setMode("class")}
                className={`rounded-xl px-3 py-2 text-sm font-bold ${
                  mode === "class" ? "bg-emerald-500 text-white" : "bg-slate-100 text-slate-600"
                }`}
              >
                One per roster seat ({sectionStudents.length})
              </button>
              <button
                type="button"
                onClick={() => setMode("blank")}
                className={`rounded-xl px-3 py-2 text-sm font-bold ${
                  mode === "blank" ? "bg-emerald-500 text-white" : "bg-slate-100 text-slate-600"
                }`}
              >
                Extra copies
              </button>
            </div>
          </div>
          {mode === "blank" ? (
            <div>
              <Label htmlFor="copies">Copies</Label>
              <Input
                id="copies"
                type="number"
                min={1}
                max={200}
                value={copies}
                onChange={(e) => setCopies(parseInt(e.target.value, 10) || 1)}
              />
            </div>
          ) : null}
          {error ? <p className="text-sm font-semibold text-red-600">{error}</p> : null}
          <Button type="button" disabled={loading || !subject || blockers.length > 0} onClick={downloadPdf}>
            {loading ? "Generating…" : "Download PDF"}
          </Button>
        </div>
      </Card>
    </>
  );
}
