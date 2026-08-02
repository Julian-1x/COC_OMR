"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";
import { exportResultsCsv, exportResultsPdf } from "@/lib/pdf/exports";
import { scanPassed } from "@/lib/omr/passing-score";
import { downloadBlob, downloadText } from "@/lib/utils";
import { formatSectionTerm } from "@/lib/academic-term";

type ReviewFilter = "" | "pending" | "passed" | "failed";

function resultsHref(view?: "archived", year?: string, review?: ReviewFilter) {
  const params = new URLSearchParams();
  if (view === "archived") params.set("view", "archived");
  if (year) params.set("year", year);
  if (review) params.set("review", review);
  const query = params.toString();
  return query ? `/dashboard/results?${query}` : "/dashboard/results";
}

function passingPoints(scan: DbScanResult, subjects: DbSubject[]): number {
  const subject = subjects.find(
    (s) => s.local_id === scan.subject_local_id || s.name === scan.subject_name,
  );
  return subject?.passing_score ?? Math.round(scan.total_questions * 0.6);
}

export function ResultsContent({
  scans,
  students,
  subjects,
  sections,
  allowedSectionNames,
  showArchived = false,
  schoolYear,
  yearOptions = [],
  initialReviewFilter = "",
}: {
  scans: DbScanResult[];
  students: DbStudent[];
  subjects: DbSubject[];
  sections: { name: string; school_year?: string | null; term_label?: string | null }[];
  /** Sections in the current Active/Archived + year filter — used for the dropdown only. */
  allowedSectionNames?: Set<string>;
  showArchived?: boolean;
  schoolYear?: string;
  yearOptions?: string[];
  initialReviewFilter?: ReviewFilter;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [sectionFilter, setSectionFilter] = useState("");
  const [subjectFilter, setSubjectFilter] = useState("");
  const [nameSearch, setNameSearch] = useState("");
  const [reviewFilter, setReviewFilter] = useState<ReviewFilter>(initialReviewFilter);
  const [pdfNote, setPdfNote] = useState<string | null>(null);

  const studentMap = new Map(students.map((s) => [s.omr_id, s]));
  const sectionOptions = [...sections].sort((a, b) => a.name.localeCompare(b.name));
  const pendingCount = scans.filter((s) => s.needs_review).length;

  const filtered = useMemo(() => {
    const needle = nameSearch.trim().toLowerCase();
    return scans.filter((scan) => {
      const student = studentMap.get(scan.student_omr_id);
      if (sectionFilter) {
        if (student?.section_name !== sectionFilter) return false;
      } else if (allowedSectionNames && allowedSectionNames.size > 0 && student?.section_name) {
        // Default view: hide scans from sections outside the current term filter unless searching.
        if (!needle && !allowedSectionNames.has(student.section_name)) return false;
      }
      if (subjectFilter && scan.subject_local_id !== subjectFilter && scan.subject_name !== subjectFilter) {
        return false;
      }
      if (needle) {
        const haystack = `${student?.name ?? ""} ${student?.school_id ?? ""} ${scan.student_omr_id}`.toLowerCase();
        if (!haystack.includes(needle)) return false;
      }
      if (reviewFilter === "pending" && !scan.needs_review) return false;
      if (reviewFilter === "passed" || reviewFilter === "failed") {
        if (scan.needs_review) return false;
        const passed = scanPassed(scan.score, scan.total_questions, passingPoints(scan, subjects));
        if (reviewFilter === "passed" && !passed) return false;
        if (reviewFilter === "failed" && passed) return false;
      }
      return true;
    });
  }, [scans, studentMap, sectionFilter, subjectFilter, nameSearch, reviewFilter, subjects, allowedSectionNames]);

  function setReviewFilterAndUrl(next: ReviewFilter) {
    setReviewFilter(next);
    const params = new URLSearchParams(searchParams.toString());
    if (next) {
      params.set("review", next);
    } else {
      params.delete("review");
    }
    const q = params.toString();
    router.replace(q ? `/dashboard/results?${q}` : "/dashboard/results");
  }

  async function downloadPdf() {
    const { bytes, truncated, total } = await exportResultsPdf(
      filtered,
      students,
      subjects,
      "OMR Results",
    );
    downloadBlob(new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }), "omr_results.pdf");
    setPdfNote(
      truncated
        ? `PDF includes only the first 45 of ${total} rows. Download CSV for the full list.`
        : null,
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
          <p className="w-full text-xs text-slate-500 sm:w-auto">
            Per-student missed-question handouts:{" "}
            <Link href="/dashboard/results/analysis" className="font-bold text-emerald-700 hover:underline">
              Item analysis → Student feedback PDF
            </Link>
          </p>
        </div>
      </div>

      {pendingCount > 0 && !showArchived ? (
        <Card className="mb-4 border-amber-200 bg-amber-50">
          <p className="text-sm text-amber-950">
            <strong>{pendingCount}</strong> scan{pendingCount === 1 ? "" : "s"} need review on your phone
            before they count in exports and item analysis.{" "}
            <button
              type="button"
              onClick={() => setReviewFilterAndUrl("pending")}
              className="font-bold text-emerald-800 underline"
            >
              Show pending only
            </button>
          </p>
        </Card>
      ) : null}

      <Card className="mb-4">
        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-5">
          <div className="lg:col-span-2">
            <Label htmlFor="search">Search student</Label>
            <Input
              id="search"
              placeholder="Name, school ID, or OMR ID"
              value={nameSearch}
              onChange={(e) => setNameSearch(e.target.value)}
            />
          </div>
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
          <div>
            <Label htmlFor="status">Status</Label>
            <Select
              id="status"
              value={reviewFilter}
              onChange={(e) => setReviewFilterAndUrl(e.target.value as ReviewFilter)}
            >
              <option value="">All</option>
              <option value="pending">Review on phone</option>
              <option value="passed">Passed</option>
              <option value="failed">Failed</option>
            </Select>
          </div>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
          <p className="text-xs font-semibold text-slate-500">
            Showing {filtered.length} of {scans.length} scans
          </p>
          <div className="flex gap-2">
            <Button type="button" variant="secondary" onClick={downloadCsv} disabled={filtered.length === 0}>
              CSV
            </Button>
            <Button type="button" onClick={() => void downloadPdf()} disabled={filtered.length === 0}>
              PDF
            </Button>
          </div>
        </div>
        {pdfNote ? (
          <p className="mt-3 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">{pdfNote}</p>
        ) : null}
      </Card>

      {filtered.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-slate-300 bg-white p-8 text-center">
          <h3 className="text-base font-extrabold text-slate-800">No results match</h3>
          <p className="mt-2 text-sm text-slate-500">
            {scans.length === 0
              ? "After exam day, scan on your phone then open Settings → Sync Now on Wi‑Fi."
              : "Try clearing filters or search with a different name."}
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
                  const pct =
                    scan.total_questions > 0
                      ? Math.round((scan.score / scan.total_questions) * 100)
                      : 0;
                  const passed = scanPassed(
                    scan.score,
                    scan.total_questions,
                    passingPoints(scan, subjects),
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
