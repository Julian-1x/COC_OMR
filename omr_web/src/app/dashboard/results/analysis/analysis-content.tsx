"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Label, Select } from "@/components/ui/input";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";
import {
  computeItemAnalysis,
  exportItemAnalysisCsv,
  type QuestionAnalysis,
} from "@/lib/pdf/exports";
import { downloadText } from "@/lib/utils";
import { scanPassed } from "@/lib/omr/passing-score";

function difficultyLabel(analysis: QuestionAnalysis): string {
  const rate = analysis.totalAttempts > 0 ? analysis.correctCount / analysis.totalAttempts : 0;
  if (rate >= 0.8) return "Easy";
  if (rate >= 0.5) return "Medium";
  if (rate >= 0.3) return "Hard";
  return "Very hard";
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

  const analyses = useMemo(() => {
    if (!subject) return [];
    return computeItemAnalysis(relevantScans, subject.answer_key, subject.total_questions);
  }, [relevantScans, subject]);

  const classAverage =
    relevantScans.length > 0
      ? Math.round(
          (relevantScans.reduce((sum, s) => sum + s.score / Math.max(s.total_questions, 1), 0) /
            relevantScans.length) *
            100,
        )
      : 0;

  const passRate =
    relevantScans.length > 0 && subject
      ? Math.round(
          (relevantScans.filter((s) =>
            scanPassed(s.score, s.total_questions, subject.passing_score),
          ).length /
            relevantScans.length) *
            100,
        )
      : 0;

  function downloadCsv() {
    if (!subject) return;
    downloadText(exportItemAnalysisCsv(subject.name, analyses), "item_analysis.csv", "text/csv");
  }

  return (
    <>
      <div className="mb-6">
        <Link href="/dashboard/results" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Results
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Item analysis</h1>
        <p className="mt-1 text-sm text-slate-500">See which questions students missed most.</p>
      </div>

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
          <div className="flex items-end">
            <Button type="button" variant="secondary" onClick={downloadCsv} disabled={!subject}>
              Export CSV
            </Button>
          </div>
        </div>
      </Card>

      {subject ? (
        <div className="mb-4 grid gap-4 sm:grid-cols-3">
          <Card>
            <p className="text-xs font-bold uppercase text-slate-500">Scans</p>
            <p className="mt-1 text-2xl font-extrabold text-slate-800">{relevantScans.length}</p>
          </Card>
          <Card>
            <p className="text-xs font-bold uppercase text-slate-500">Class average</p>
            <p className="mt-1 text-2xl font-extrabold text-slate-800">{classAverage}%</p>
          </Card>
          <Card>
            <p className="text-xs font-bold uppercase text-slate-500">Pass rate</p>
            <p className="mt-1 text-2xl font-extrabold text-slate-800">{passRate}%</p>
          </Card>
        </div>
      ) : null}

      {!subject ? (
        <p className="text-sm text-slate-500">Create an answer key first.</p>
      ) : analyses.length === 0 ? (
        <p className="text-sm text-slate-500">No scan data for this subject yet.</p>
      ) : (
        <Card>
          <div className="overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead>
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-2 py-2 text-left">Q#</th>
                  <th className="px-2 py-2 text-left">Key</th>
                  <th className="px-2 py-2 text-left">Correct</th>
                  <th className="px-2 py-2 text-left">Difficulty</th>
                  <th className="px-2 py-2 text-left">Distribution</th>
                </tr>
              </thead>
              <tbody>
                {analyses.map((a) => {
                  const pct = a.totalAttempts > 0 ? Math.round((a.correctCount / a.totalAttempts) * 100) : 0;
                  const dist = Object.entries(a.answerDistribution)
                    .map(([letter, count]) => `${letter}:${count}`)
                    .join(" ");
                  return (
                    <tr key={a.questionNumber} className="border-b border-slate-100">
                      <td className="px-2 py-2 font-bold">{a.questionNumber}</td>
                      <td className="px-2 py-2">{a.correctAnswer}</td>
                      <td className="px-2 py-2">
                        {a.correctCount}/{a.totalAttempts} ({pct}%)
                      </td>
                      <td className="px-2 py-2">{difficultyLabel(a)}</td>
                      <td className="px-2 py-2 text-xs text-slate-500">{dist || "—"}</td>
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
