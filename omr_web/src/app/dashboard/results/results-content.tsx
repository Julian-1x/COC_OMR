"use client";

import Link from "next/link";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Label, Select } from "@/components/ui/input";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";
import { exportResultsCsv, exportResultsPdf } from "@/lib/pdf/exports";
import { scanPassed } from "@/lib/omr/passing-score";
import { downloadBlob, downloadText } from "@/lib/utils";
import { formatSectionTerm } from "@/lib/academic-term";

function resultsHref(view?: "archived", year?: string) {
  const params = new URLSearchParams();
  if (view === "archived") params.set("view", "archived");
  if (year) params.set("year", year);
  const query = params.toString();
  return query ? `/dashboard/results?${query}` : "/dashboard/results";
}

export function ResultsContent({
  scans,
  students,
  subjects,
  sections,
  showArchived = false,
  schoolYear,
  yearOptions = [],
}: {
  scans: DbScanResult[];
  students: DbStudent[];
  subjects: DbSubject[];
  sections: { name: string; school_year?: string | null; term_label?: string | null }[];
  showArchived?: boolean;
  schoolYear?: string;
  yearOptions?: string[];
}) {
  const [sectionFilter, setSectionFilter] = useState("");
  const [subjectFilter, setSubjectFilter] = useState("");
  const [pdfNote, setPdfNote] = useState<string | null>(null);

  const studentMap = new Map(students.map((s) => [s.omr_id, s]));
  const sectionOptions = [...sections].sort((a, b) => a.name.localeCompare(b.name));

  const filtered = scans.filter((scan) => {
    const student = studentMap.get(scan.student_omr_id);
    if (sectionFilter && student?.section_name !== sectionFilter) return false;
    if (subjectFilter && scan.subject_local_id !== subjectFilter && scan.subject_name !== subjectFilter) {
      return false;
    }
    return true;
  });

  async function downloadPdf() {
    const { bytes, truncated, total } = await exportResultsPdf(
      filtered,
      students,
      subjects,
      "OMR Results",
    );
    downloadBlob(new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }), "omr_results.pdf");
    setPdfNote(
      truncated ? `PDF shows first ${Math.min(total, 45)} of ${total} rows. Use CSV for the full list.` : null,
    );
  }

  function downloadCsv() {
    downloadText(
      exportResultsCsv(filtered, students, subjects, sectionFilter || undefined, subjectFilter || undefined),
      "omr_results.csv",
      "text/csv",
    );
  }

  return (
    <>
      <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-slate-800">Results</h1>
          <p className="mt-1 text-sm text-slate-500">
            {showArchived
              ? "Archived term results — read-only history."
              : "Active term scores — export when you need them."}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link
            href={resultsHref(undefined, schoolYear)}
            className={`rounded-xl px-3 py-2 text-sm font-bold ${
              !showArchived
                ? "bg-emerald-500 text-white"
                : "border border-slate-200 bg-white text-slate-600"
            }`}
          >
            Active
          </Link>
          <Link
            href={resultsHref("archived", schoolYear)}
            className={`rounded-xl px-3 py-2 text-sm font-bold ${
              showArchived
                ? "bg-emerald-500 text-white"
                : "border border-slate-200 bg-white text-slate-600"
            }`}
          >
            Archived
          </Link>
          <form className="flex items-center gap-2" method="get">
            {showArchived ? <input type="hidden" name="view" value="archived" /> : null}
            <select
              name="year"
              defaultValue={schoolYear ?? ""}
              className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700"
              aria-label="School year"
            >
              <option value="">All years</option>
              {yearOptions.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
            <button
              type="submit"
              className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700 hover:border-emerald-300"
            >
              Filter
            </button>
          </form>
          <Link
            href="/dashboard/results/analysis"
            className="rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-2.5 text-sm font-extrabold text-emerald-800 hover:bg-emerald-100"
          >
            Item analysis
          </Link>
        </div>
      </div>

      <Card className="mb-4">
        <div className="grid gap-3 md:grid-cols-3">
          <div>
            <Label htmlFor="section">Section</Label>
            <Select id="section" value={sectionFilter} onChange={(e) => setSectionFilter(e.target.value)}>
              <option value="">All sections</option>
              {sectionOptions.map((section) => {
                const term = formatSectionTerm(section);
                return (
                  <option key={section.name} value={section.name}>
                    {term ? `${section.name} (${term})` : section.name}
                  </option>
                );
              })}
            </Select>
          </div>
          <div>
            <Label htmlFor="subject">Subject</Label>
            <Select id="subject" value={subjectFilter} onChange={(e) => setSubjectFilter(e.target.value)}>
              <option value="">All subjects</option>
              {subjects.map((s) => (
                <option key={s.local_id} value={s.local_id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </div>
          <div className="flex items-end gap-2">
            <Button type="button" variant="secondary" onClick={downloadCsv}>
              CSV
            </Button>
            <Button type="button" onClick={() => void downloadPdf()}>
              PDF
            </Button>
          </div>
        </div>
        {pdfNote ? <p className="mt-3 text-xs font-semibold text-amber-700">{pdfNote}</p> : null}
      </Card>

      {filtered.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-slate-300 bg-white p-8 text-center">
          <h3 className="text-base font-extrabold text-slate-800">No results yet</h3>
          <p className="mt-2 text-sm text-slate-500">
            After exam day, scan on your phone then open Settings → Sync Now on Wi‑Fi.
          </p>
        </div>
      ) : (
        <Card>
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">Student</th>
                  <th className="px-2 py-2 text-left">Section</th>
                  <th className="px-2 py-2 text-left">Subject</th>
                  <th className="px-2 py-2 text-left">Score</th>
                  <th className="px-2 py-2 text-left">Status</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((scan) => {
                  const student = studentMap.get(scan.student_omr_id);
                  const subject = subjects.find(
                    (s) => s.local_id === scan.subject_local_id || s.name === scan.subject_name,
                  );
                  const pct =
                    scan.total_questions > 0
                      ? Math.round((scan.score / scan.total_questions) * 100)
                      : 0;
                  const passed = scanPassed(
                    scan.score,
                    scan.total_questions,
                    subject?.passing_score ?? Math.round(scan.total_questions * 0.6),
                  );
                  return (
                    <tr key={scan.id} className="border-b border-slate-100">
                      <td className="px-2 py-2">
                        <div className="font-semibold text-slate-800">{student?.name ?? scan.student_omr_id}</div>
                        <div className="text-xs text-slate-400">OMR {scan.student_omr_id}</div>
                      </td>
                      <td className="px-2 py-2">{student?.section_name ?? "—"}</td>
                      <td className="px-2 py-2">{scan.subject_name}</td>
                      <td className="px-2 py-2 font-mono font-bold">
                        {scan.score}/{scan.total_questions} ({pct}%)
                      </td>
                      <td className="px-2 py-2">
                        {scan.needs_review ? (
                          <span
                            className="rounded-full bg-amber-100 px-2 py-0.5 text-xs font-bold text-amber-800"
                            title="Open the mobile app to review and confirm this scan"
                          >
                            Review on phone
                          </span>
                        ) : (
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-bold ${
                              passed ? "bg-emerald-100 text-emerald-800" : "bg-red-100 text-red-800"
                            }`}
                          >
                            {passed ? "Passed" : "Failed"}
                          </span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </>
  );
}
