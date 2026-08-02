"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Label, Select } from "@/components/ui/input";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";
import {
  buildItemAnalysisReport,
  difficultyColorClass,
  difficultyLabel,
  exportItemAnalysisCsv,
  exportItemAnalysisPdf,
  gradedLatestPerStudent,
  isDistributionChoiceCorrect,
  questionDifficulty,
  sortedDistributionKeys,
  type QuestionAnalysis,
} from "@/lib/omr/item-analysis";
import {
  buildStudentFeedbackRows,
  exportStudentFeedbackPdf,
} from "@/lib/omr/student-feedback";
import { scanPassed } from "@/lib/omr/passing-score";
import { downloadBlob, downloadText } from "@/lib/utils";

function DistributionBars({
  subject,
  analysis,
}: {
  subject: DbSubject;
  analysis: QuestionAnalysis;
}) {
  const keys = sortedDistributionKeys(analysis.answerDistribution);
  if (keys.length === 0) {
    return <span className="text-xs text-slate-400">—</span>;
  }

  return (
    <div className="flex min-w-[200px] gap-1">
      {keys.map((answer) => {
        const count = analysis.answerDistribution[answer] ?? 0;
        const pct = analysis.totalAttempts > 0 ? count / analysis.totalAttempts : 0;
        const isCorrect = isDistributionChoiceCorrect(subject, analysis.questionNumber, answer);
        return (
          <div key={answer} className="flex flex-1 flex-col items-center gap-1">
            <div
              className={`flex h-10 w-full items-end overflow-hidden rounded border ${
                isCorrect ? "border-emerald-300 bg-emerald-50" : "border-slate-200 bg-slate-50"
              }`}
            >
              <div
                className={`w-full rounded-sm ${isCorrect ? "bg-emerald-500" : "bg-slate-400"}`}
                style={{ height: `${Math.max(pct * 100, pct > 0 ? 8 : 0)}%` }}
              />
            </div>
            <span
              className={`text-[10px] font-bold ${isCorrect ? "text-emerald-700" : "text-slate-500"}`}
            >
              {answer}
              <span className="font-normal text-slate-400"> {count}</span>
            </span>
          </div>
        );
      })}
    </div>
  );
}

export function AnalysisContent({
  scans,
  students,
  subjects,
}: {
  scans: DbScanResult[];
  students: DbStudent[];
  subjects: DbSubject[];
}) {
  const [subjectId, setSubjectId] = useState(subjects[0]?.local_id ?? "");
  const [sectionFilter, setSectionFilter] = useState("");
  const [exportingPdf, setExportingPdf] = useState(false);
  const [exportingFeedback, setExportingFeedback] = useState(false);

  const subject = subjects.find((s) => s.local_id === subjectId);
  const sections = [...new Set(students.map((s) => s.section_name))].sort();

  const relevantScans = useMemo(() => {
    if (!subject) return [];
    return scans.filter((scan) => {
      if (scan.subject_local_id !== subject.local_id && scan.subject_name !== subject.name) return false;
      if (sectionFilter) {
        const student = students.find((s) => s.omr_id === scan.student_omr_id);
        if (student?.section_name !== sectionFilter) return false;
      }
      return true;
    });
  }, [scans, students, subject, sectionFilter]);

  const report = useMemo(() => {
    if (!subject) return null;
    return buildItemAnalysisReport(subject, relevantScans);
  }, [relevantScans, subject]);

  const gradedForStats = useMemo(
    () => gradedLatestPerStudent(relevantScans),
    [relevantScans],
  );

  const classAverage =
    report && gradedForStats.length > 0
      ? Math.round(
          (gradedForStats.reduce((sum, s) => sum + s.score / Math.max(s.total_questions, 1), 0) /
            gradedForStats.length) *
            100,
        )
      : 0;

  const passRate =
    report && subject && gradedForStats.length > 0
      ? Math.round(
          (gradedForStats.filter((s) =>
            scanPassed(s.score, s.total_questions, subject.passing_score),
          ).length /
            gradedForStats.length) *
            100,
        )
      : 0;

  const hardest = report
    ? [...report.questions].sort((a, b) => questionDifficulty(a) - questionDifficulty(b)).slice(0, 5)
    : [];

  const feedbackRows = useMemo(() => {
    if (!subject) return [];
    return buildStudentFeedbackRows(subject, relevantScans, students);
  }, [relevantScans, students, subject]);

  async function downloadStudentFeedbackPdf() {
    if (!subject || feedbackRows.length === 0) return;
    const sectionLabel = sectionFilter || undefined;
    const confirmed = window.confirm(
      `Export student feedback PDF?\n\n` +
        `${feedbackRows.length} student${feedbackRows.length === 1 ? "" : "s"} in ${subject.name}` +
        (sectionLabel ? ` — ${sectionLabel}` : "") +
        `.\n\nEach student gets one page with missed questions and correct answers.`,
    );
    if (!confirmed) return;

    setExportingFeedback(true);
    try {
      const bytes = await exportStudentFeedbackPdf(subject, feedbackRows, { sectionLabel });
      const suffix = sectionLabel ? sectionLabel.replace(/\s+/g, "_") : "all_sections";
      downloadBlob(
        new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }),
        `student_feedback_${subject.name.replace(/\s+/g, "_")}_${suffix}.pdf`,
      );
    } finally {
      setExportingFeedback(false);
    }
  }

  function downloadCsv() {
    if (!subject || !report) return;
    downloadText(exportItemAnalysisCsv(subject.name, report), "item_analysis.csv", "text/csv");
  }

  async function downloadPdf() {
    if (!subject || !report) return;
    setExportingPdf(true);
    try {
      const bytes = await exportItemAnalysisPdf(subject.name, report);
      downloadBlob(new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }), "item_analysis.pdf");
    } finally {
      setExportingPdf(false);
    }
  }

  return (
    <>
      <div className="mb-6">
        <Link href="/dashboard/results" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Results
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Item analysis</h1>
        <p className="mt-1 text-sm text-slate-500">
          Uses the latest approved scan per student (same rules as the phone app).
        </p>
      </div>

      {report && report.pendingReviewCount > 0 ? (
        <Card className="mb-4 border-amber-200 bg-amber-50">
          <p className="text-sm font-bold text-amber-950">Scans waiting for review on your phone</p>
          <p className="mt-1 text-sm text-amber-900">
            <strong>{report.pendingReviewCount}</strong> scan
            {report.pendingReviewCount === 1 ? "" : "s"} still need approval in the app review queue.
            Item analysis only includes approved scans. Approve them on your phone, sync, then refresh this
            page.
          </p>
          <Link
            href="/dashboard/results?review=pending"
            className="mt-2 inline-block text-sm font-bold text-emerald-800 hover:underline"
          >
            View pending scans in Results →
          </Link>
        </Card>
      ) : null}

      <Card className="mb-4">
        <div className="grid gap-3 md:grid-cols-3">
          <div>
            <Label htmlFor="subject">Subject</Label>
            <Select id="subject" value={subjectId} onChange={(e) => setSubjectId(e.target.value)}>
              {subjects.length === 0 ? <option value="">No subjects</option> : null}
              {subjects.map((s) => (
                <option key={s.local_id} value={s.local_id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label htmlFor="section">Section</Label>
            <Select id="section" value={sectionFilter} onChange={(e) => setSectionFilter(e.target.value)}>
              <option value="">All sections</option>
              {sections.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          </div>
          <div className="flex flex-col gap-2 md:items-end">
            <div className="flex flex-wrap items-center gap-2">
              <Button type="button" variant="secondary" onClick={downloadCsv} disabled={!report}>
                CSV
              </Button>
              <Button type="button" onClick={() => void downloadPdf()} disabled={!report || exportingPdf}>
                {exportingPdf ? "PDF…" : "PDF"}
              </Button>
              <Button
                type="button"
                variant="secondary"
                onClick={() => void downloadStudentFeedbackPdf()}
                disabled={!report || feedbackRows.length === 0 || exportingFeedback}
              >
                {exportingFeedback ? "Feedback…" : "Student feedback PDF"}
              </Button>
            </div>
            <p className="text-xs text-slate-500 md:text-right">
              Student feedback: one page per student — missed questions and correct answers only.
            </p>
          </div>
        </div>
      </Card>

      {subject && report ? (
        <>
          <div className="mb-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Card>
              <p className="text-xs font-bold uppercase text-slate-500">Graded students</p>
              <p className="mt-1 text-2xl font-extrabold text-slate-800">{report.gradedStudentCount}</p>
            </Card>
            <Card>
              <p className="text-xs font-bold uppercase text-slate-500">Class average</p>
              <p className="mt-1 text-2xl font-extrabold text-slate-800">{classAverage}%</p>
            </Card>
            <Card>
              <p className="text-xs font-bold uppercase text-slate-500">Pass rate</p>
              <p className="mt-1 text-2xl font-extrabold text-slate-800">{passRate}%</p>
            </Card>
            {report.supersededScanCount > 0 ? (
              <Card>
                <p className="text-xs font-bold uppercase text-slate-500">Older rescans ignored</p>
                <p className="mt-1 text-2xl font-extrabold text-slate-800">{report.supersededScanCount}</p>
              </Card>
            ) : null}
          </div>

          {hardest.length > 0 ? (
            <Card className="mb-4">
              <p className="mb-2 text-sm font-extrabold text-slate-800">Hardest questions</p>
              <div className="flex flex-wrap gap-2">
                {hardest.map((q) => {
                  const pct = Math.round(questionDifficulty(q) * 100);
                  return (
                    <span
                      key={q.questionNumber}
                      className={`rounded-full px-3 py-1 text-xs font-bold ${difficultyColorClass(q)}`}
                    >
                      Q{q.questionNumber} · {pct}% correct
                    </span>
                  );
                })}
              </div>
            </Card>
          ) : null}

          <Card>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b text-xs font-bold uppercase text-slate-500">
                    <th className="sticky left-0 bg-white px-2 py-2 text-left">Q#</th>
                    <th className="px-2 py-2 text-left">Key</th>
                    <th className="px-2 py-2 text-left">Correct</th>
                    <th className="px-2 py-2 text-left">Partial</th>
                    <th className="px-2 py-2 text-left">Difficulty</th>
                    <th className="px-2 py-2 text-left">D</th>
                    <th className="px-2 py-2 text-left">Distribution</th>
                  </tr>
                </thead>
                <tbody>
                  {report.questions.map((a) => {
                    const pct =
                      a.totalAttempts > 0 ? Math.round((a.correctCount / a.totalAttempts) * 100) : 0;
                    return (
                      <tr key={a.questionNumber} className="border-b border-slate-100">
                        <td className="sticky left-0 bg-white px-2 py-2 font-bold">{a.questionNumber}</td>
                        <td className="px-2 py-2 font-mono text-xs">{a.correctAnswer}</td>
                        <td className="px-2 py-2">
                          {a.correctCount}/{a.totalAttempts} ({pct}%)
                        </td>
                        <td className="px-2 py-2">{a.partialCount > 0 ? a.partialCount : "—"}</td>
                        <td className="px-2 py-2">
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-bold ${difficultyColorClass(a)}`}
                          >
                            {difficultyLabel(a)}
                          </span>
                        </td>
                        <td className="px-2 py-2 font-mono text-xs">
                          {a.discriminationIndex !== null ? (
                            <span
                              className={
                                a.discriminationIndex >= 0.3 ? "font-bold text-emerald-700" : "text-slate-600"
                              }
                            >
                              {a.discriminationIndex.toFixed(2)}
                            </span>
                          ) : (
                            "—"
                          )}
                        </td>
                        <td className="px-2 py-2">
                          <DistributionBars subject={subject} analysis={a} />
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </Card>
        </>
      ) : !subject ? (
        <p className="text-sm text-slate-500">Create an answer key first.</p>
      ) : (
        <p className="text-sm text-slate-500">
          No approved scan data for this subject yet. Scan on your phone, approve in the review queue, then
          sync.
        </p>
      )}
    </>
  );
}
