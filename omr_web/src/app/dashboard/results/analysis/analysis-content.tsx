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
  discriminationColorClass,
  discriminationLabel,
  exportItemAnalysisCsv,
  exportItemAnalysisPdf,
  gradedLatestPerStudent,
  isDistributionChoiceCorrect,
  overallDifficulty,
  questionDifficulty,
  questionsNeedingAttention,
  sortedDistributionKeys,
  sortQuestions,
  type QuestionAnalysis,
  type SortMode,
} from "@/lib/omr/item-analysis";
import {
  buildStudentFeedbackRows,
  exportStudentFeedbackPdf,
} from "@/lib/omr/student-feedback";
import { scanPassed } from "@/lib/omr/passing-score";
import { downloadBlob, downloadText } from "@/lib/utils";
import {
  PendingReviewNotice,
  SyncLoopNotice,
} from "@/components/desk-notices";

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
        const isCorrect = isDistributionChoiceCorrect(
          subject,
          analysis.questionNumber,
          answer,
        );
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
  initialSubjectId = "",
  initialSection = "",
}: {
  scans: DbScanResult[];
  students: DbStudent[];
  subjects: DbSubject[];
  initialSubjectId?: string;
  initialSection?: string;
}) {
  const defaultSubject =
    subjects.find((s) => s.local_id === initialSubjectId)?.local_id ??
    subjects[0]?.local_id ??
    "";
  const [subjectId, setSubjectId] = useState(defaultSubject);
  const [sectionFilter, setSectionFilter] = useState(initialSection);
  const [sortMode, setSortMode] = useState<SortMode>("number");
  const [showDistribution, setShowDistribution] = useState(true);
  const [exportingPdf, setExportingPdf] = useState(false);
  const [exportingFeedback, setExportingFeedback] = useState(false);

  const subject = subjects.find((s) => s.local_id === subjectId);
  const sections = [...new Set(students.map((s) => s.section_name))].sort();

  const relevantScans = useMemo(() => {
    if (!subject) return [];
    return scans.filter((scan) => {
      if (scan.subject_local_id !== subject.local_id && scan.subject_name !== subject.name) {
        return false;
      }
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

  const sortedRows = useMemo(() => {
    if (!report) return [];
    return sortQuestions(report.questions, sortMode);
  }, [report, sortMode]);

  const attention = useMemo(() => {
    if (!subject || !report) return [];
    return questionsNeedingAttention(subject, report);
  }, [subject, report]);

  const classAverage =
    report && gradedForStats.length > 0
      ? Math.round(
          (gradedForStats.reduce(
            (sum, s) => sum + s.score / Math.max(s.total_questions, 1),
            0,
          ) /
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

  const avgDifficultyPct = report ? Math.round(overallDifficulty(report) * 100) : 0;

  const hardest = report
    ? [...report.questions]
        .sort((a, b) => questionDifficulty(a) - questionDifficulty(b))
        .slice(0, 5)
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
    downloadText(
      exportItemAnalysisCsv(subject.name, report, subject),
      "item_analysis.csv",
      "text/csv",
    );
  }

  async function downloadPdf() {
    if (!subject || !report) return;
    setExportingPdf(true);
    try {
      const bytes = await exportItemAnalysisPdf(subject.name, report, subject);
      downloadBlob(
        new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }),
        "item_analysis.pdf",
      );
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
        <p className="mt-1 text-sm text-slate-500">Hard items, weak questions, popular wrong answers</p>
      </div>

      <SyncLoopNotice className="mb-3" />
      {report ? (
        <PendingReviewNotice count={report.pendingReviewCount} className="mb-4" />
      ) : null}

      <Card className="mb-4">
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
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
            <Select
              id="section"
              value={sectionFilter}
              onChange={(e) => setSectionFilter(e.target.value)}
            >
              <option value="">All sections</option>
              {sections.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label htmlFor="sort">Sort questions</Label>
            <Select
              id="sort"
              value={sortMode}
              onChange={(e) => setSortMode(e.target.value as SortMode)}
            >
              <option value="number">By question #</option>
              <option value="hardest">Hardest first</option>
              <option value="easiest">Easiest first</option>
              <option value="weakD">Weakest discrimination first</option>
            </Select>
          </div>
          <div className="flex flex-col justify-end gap-2">
            <label className="flex items-center gap-2 text-sm font-semibold text-slate-700">
              <input
                type="checkbox"
                checked={showDistribution}
                onChange={(e) => setShowDistribution(e.target.checked)}
              />
              Show answer distribution
            </label>
            <div className="flex flex-wrap gap-2">
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
                {exportingFeedback ? "Feedback…" : "Student feedback"}
              </Button>
            </div>
          </div>
        </div>
      </Card>

      {subject && report ? (
        <>
          <div className="mb-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
            <Card>
              <p className="text-xs font-bold uppercase text-slate-500">Graded students</p>
              <p className="mt-1 text-2xl font-extrabold text-slate-800">
                {report.gradedStudentCount}
              </p>
            </Card>
            <Card>
              <p className="text-xs font-bold uppercase text-slate-500">Class average</p>
              <p className="mt-1 text-2xl font-extrabold text-slate-800">{classAverage}%</p>
            </Card>
            <Card>
              <p className="text-xs font-bold uppercase text-slate-500">Pass rate</p>
              <p className="mt-1 text-2xl font-extrabold text-slate-800">{passRate}%</p>
            </Card>
            <Card>
              <p className="text-xs font-bold uppercase text-slate-500">Avg. item correct</p>
              <p className="mt-1 text-2xl font-extrabold text-slate-800">{avgDifficultyPct}%</p>
            </Card>
            {report.supersededScanCount > 0 ? (
              <Card>
                <p className="text-xs font-bold uppercase text-slate-500">Older rescans ignored</p>
                <p className="mt-1 text-2xl font-extrabold text-slate-800">
                  {report.supersededScanCount}
                </p>
              </Card>
            ) : (
              <Card>
                <p className="text-xs font-bold uppercase text-slate-500">Questions</p>
                <p className="mt-1 text-2xl font-extrabold text-slate-800">
                  {subject.total_questions}
                </p>
              </Card>
            )}
          </div>

          {attention.length > 0 ? (
            <Card className="mb-4 border-red-200 bg-red-50">
              <p className="text-sm font-extrabold text-red-900">Needs attention</p>
              <p className="mt-1 text-xs text-red-800">
                Reteach these items, or rewrite if many strong students also miss them (weak D).
              </p>
              <ul className="mt-3 space-y-2">
                {attention.slice(0, 8).map((flag) => (
                  <li key={flag.questionNumber} className="text-sm text-red-950">
                    <button
                      type="button"
                      className="font-extrabold text-emerald-800 hover:underline"
                      onClick={() => {
                        setSortMode("number");
                        document
                          .getElementById(`item-q-${flag.questionNumber}`)
                          ?.scrollIntoView({ behavior: "smooth", block: "center" });
                      }}
                    >
                      Q{flag.questionNumber}
                    </button>
                    <span className="text-red-900"> — {flag.reasons.join(" · ")}</span>
                  </li>
                ))}
              </ul>
              {attention.length > 8 ? (
                <p className="mt-2 text-xs text-red-800">
                  +{attention.length - 8} more — sort by hardest or weak discrimination below.
                </p>
              ) : null}
            </Card>
          ) : null}

          {hardest.length > 0 ? (
            <Card className="mb-4">
              <p className="mb-2 text-sm font-extrabold text-slate-800">Hardest questions</p>
              <div className="flex flex-wrap gap-2">
                {hardest.map((q) => {
                  const pct = Math.round(questionDifficulty(q) * 100);
                  return (
                    <button
                      key={q.questionNumber}
                      type="button"
                      onClick={() => {
                        document
                          .getElementById(`item-q-${q.questionNumber}`)
                          ?.scrollIntoView({ behavior: "smooth", block: "center" });
                      }}
                      className={`rounded-full px-3 py-1 text-xs font-bold ${difficultyColorClass(q)}`}
                    >
                      Q{q.questionNumber} · {pct}% correct
                    </button>
                  );
                })}
              </div>
            </Card>
          ) : null}

          <Card>
            <p className="mb-3 text-xs text-slate-500">
              <strong>D</strong> compares top vs bottom scorers. Strong (≥0.30) separates who knows the topic.
            </p>
            <div className="overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead>
                  <tr className="border-b text-xs font-bold uppercase text-slate-500">
                    <th className="sticky left-0 bg-white px-2 py-2 text-left">Q#</th>
                    <th className="px-2 py-2 text-left">Key</th>
                    <th className="px-2 py-2 text-left">Correct</th>
                    <th className="px-2 py-2 text-left">Partial</th>
                    <th className="px-2 py-2 text-left">Difficulty</th>
                    <th className="px-2 py-2 text-left">Discrimination</th>
                    {showDistribution ? (
                      <th className="px-2 py-2 text-left">Distribution</th>
                    ) : null}
                  </tr>
                </thead>
                <tbody>
                  {sortedRows.map((a) => {
                    const pct =
                      a.totalAttempts > 0
                        ? Math.round((a.correctCount / a.totalAttempts) * 100)
                        : 0;
                    const flagged = attention.some(
                      (f) => f.questionNumber === a.questionNumber,
                    );
                    return (
                      <tr
                        key={a.questionNumber}
                        id={`item-q-${a.questionNumber}`}
                        className={`border-b border-slate-100 ${flagged ? "bg-red-50/40" : ""}`}
                      >
                        <td className="sticky left-0 bg-inherit px-2 py-2 font-bold">
                          {a.questionNumber}
                          {flagged ? (
                            <span className="ml-1 text-[10px] font-bold uppercase text-red-700">
                              review
                            </span>
                          ) : null}
                        </td>
                        <td className="px-2 py-2 font-mono text-xs">{a.correctAnswer}</td>
                        <td className="px-2 py-2">
                          {a.correctCount}/{a.totalAttempts} ({pct}%)
                        </td>
                        <td className="px-2 py-2">
                          {a.partialCount > 0 ? a.partialCount : "—"}
                        </td>
                        <td className="px-2 py-2">
                          <span
                            className={`rounded-full px-2 py-0.5 text-xs font-bold ${difficultyColorClass(a)}`}
                          >
                            {difficultyLabel(a)}
                          </span>
                        </td>
                        <td className="px-2 py-2">
                          {a.discriminationIndex !== null ? (
                            <span
                              className={`inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-bold ${discriminationColorClass(a.discriminationIndex)}`}
                            >
                              {a.discriminationIndex.toFixed(2)}
                              <span className="font-semibold opacity-80">
                                {discriminationLabel(a.discriminationIndex)}
                              </span>
                            </span>
                          ) : (
                            <span className="text-xs text-slate-500">Need ≥4 graded</span>
                          )}
                        </td>
                        {showDistribution ? (
                          <td className="px-2 py-2">
                            <DistributionBars subject={subject} analysis={a} />
                          </td>
                        ) : null}
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
          No approved scan data for this subject yet. Scan on your phone, approve in the review
          queue, then sync.
        </p>
      )}
    </>
  );
}
