import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";
import { formatCorrectAnswer } from "@/lib/omr/answer-key";

const ROWS_PER_PAGE = 45;

function passingScoreForScan(scan: DbScanResult, subjects: DbSubject[]): number {
  const subject = subjects.find(
    (s) => s.local_id === scan.subject_local_id || s.name === scan.subject_name,
  );
  return subject?.passing_score ?? 75;
}

export function exportResultsCsv(
  scans: DbScanResult[],
  students: DbStudent[],
  subjects: DbSubject[],
  sectionFilter?: string,
  subjectFilter?: string,
): string {
  const studentMap = new Map(students.map((s) => [s.omr_id, s]));
  const filtered = scans.filter((scan) => {
    if (subjectFilter && scan.subject_local_id !== subjectFilter && scan.subject_name !== subjectFilter) return false;
    const student = studentMap.get(scan.student_omr_id);
    if (sectionFilter && student?.section_name !== sectionFilter) return false;
    return true;
  });

  const header = "Student ID,OMR ID,Name,Section,Subject,Score,Total,Percentage,Status,Needs Review,Scan Date";
  const lines = filtered.map((scan) => {
    const student = studentMap.get(scan.student_omr_id);
    const pct = scan.total_questions > 0 ? Math.round((scan.score / scan.total_questions) * 100) : 0;
    const passed = pct >= passingScoreForScan(scan, subjects);
    return [
      student?.school_id ?? "",
      scan.student_omr_id,
      `"${(student?.name ?? "").replace(/"/g, '""')}"`,
      student?.section_name ?? "",
      scan.subject_name,
      scan.score,
      scan.total_questions,
      `${pct}%`,
      passed ? "Passed" : "Failed",
      scan.needs_review ? "Review on phone" : "OK",
      scan.scan_time?.slice(0, 10) ?? "",
    ].join(",");
  });
  return [header, ...lines].join("\n");
}

export async function exportResultsPdf(
  scans: DbScanResult[],
  students: DbStudent[],
  subjects: DbSubject[],
  title: string,
): Promise<{ bytes: Uint8Array; truncated: boolean; total: number }> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const studentMap = new Map(students.map((s) => [s.omr_id, s]));
  const rows = scans;
  const truncated = rows.length > ROWS_PER_PAGE;

  let page = pdf.addPage([595, 842]);
  let y = 800;
  let rowIndex = 0;

  function drawHeader() {
    y = 800;
    page.drawText(title, { x: 40, y, size: 16, font: bold, color: rgb(0.06, 0.2, 0.15) });
    y -= 24;
    page.drawText(`Showing ${Math.min(rows.length, ROWS_PER_PAGE)} of ${rows.length} scans`, {
      x: 40,
      y,
      size: 10,
      font,
    });
    if (truncated) {
      y -= 14;
      page.drawText("Download CSV for the full list.", { x: 40, y, size: 9, font, color: rgb(0.5, 0.3, 0) });
    }
    y -= 30;
    page.drawText("OMR ID", { x: 40, y, size: 9, font: bold });
    page.drawText("Name", { x: 100, y, size: 9, font: bold });
    page.drawText("Subject", { x: 280, y, size: 9, font: bold });
    page.drawText("Score", { x: 420, y, size: 9, font: bold });
    y -= 14;
  }

  drawHeader();

  for (const scan of rows.slice(0, ROWS_PER_PAGE)) {
    const student = studentMap.get(scan.student_omr_id);
    page.drawText(scan.student_omr_id, { x: 40, y, size: 8, font });
    page.drawText((student?.name ?? "").slice(0, 28), { x: 100, y, size: 8, font });
    page.drawText(scan.subject_name.slice(0, 20), { x: 280, y, size: 8, font });
    const review = scan.needs_review ? " (review)" : "";
    page.drawText(`${scan.score}/${scan.total_questions}${review}`, { x: 420, y, size: 8, font });
    y -= 12;
    rowIndex++;
    if (y < 60 && rowIndex < rows.length) {
      page = pdf.addPage([595, 842]);
      drawHeader();
    }
  }

  return { bytes: await pdf.save(), truncated, total: rows.length };
}

export function exportOmrIdsCsv(students: DbStudent[], sectionName: string): string {
  const filtered = students
    .filter((s) => s.section_name === sectionName)
    .sort((a, b) => a.omr_id.localeCompare(b.omr_id));
  const header = "Student ID,OMR ID,Name,Section";
  const lines = filtered.map((s) =>
    [s.school_id, s.omr_id, `"${s.name.replace(/"/g, '""')}"`, s.section_name].join(","),
  );
  return [header, ...lines].join("\n");
}

export async function exportOmrIdsPdf(
  students: DbStudent[],
  sectionName: string,
): Promise<{ bytes: Uint8Array; truncated: boolean; total: number }> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const filtered = students
    .filter((s) => s.section_name === sectionName)
    .sort((a, b) => a.omr_id.localeCompare(b.omr_id));
  const truncated = filtered.length > 50;

  let page = pdf.addPage([595, 842]);
  let y = 800;

  page.drawText(`OMR IDs — ${sectionName}`, { x: 40, y, size: 16, font: bold, color: rgb(0.06, 0.2, 0.15) });
  y -= 28;
  page.drawText("Give each student their OMR ID before the exam.", { x: 40, y, size: 10, font, color: rgb(0.4, 0.4, 0.4) });
  y -= 14;
  page.drawText(`Showing ${Math.min(filtered.length, 50)} of ${filtered.length} students`, {
    x: 40,
    y,
    size: 9,
    font,
  });
  y -= 24;

  for (const s of filtered.slice(0, 50)) {
    if (y < 50) {
      page = pdf.addPage([595, 842]);
      y = 800;
    }
    page.drawText(s.omr_id, { x: 40, y, size: 11, font: bold });
    page.drawText(s.name, { x: 100, y, size: 10, font });
    page.drawText(s.school_id, { x: 380, y, size: 9, font, color: rgb(0.5, 0.5, 0.5) });
    y -= 14;
  }

  return { bytes: await pdf.save(), truncated, total: filtered.length };
}

export function exportSectionRosterCsv(students: DbStudent[], sectionName: string): string {
  const filtered = students
    .filter((s) => s.section_name === sectionName)
    .sort((a, b) => a.name.localeCompare(b.name));
  const header = "Student ID,OMR ID,Name,Section";
  const lines = filtered.map((s) =>
    [s.school_id, s.omr_id, `"${s.name.replace(/"/g, '""')}"`, s.section_name].join(","),
  );
  return [header, ...lines].join("\n");
}

export type QuestionAnalysis = {
  questionNumber: number;
  correctAnswer: string;
  totalAttempts: number;
  correctCount: number;
  answerDistribution: Record<string, number>;
};

export function computeItemAnalysis(
  scans: DbScanResult[],
  answerKey: Record<string, string | string[]>,
  totalQuestions: number,
): QuestionAnalysis[] {
  const analyses: QuestionAnalysis[] = Array.from({ length: totalQuestions }, (_, i) => {
    const qNum = i + 1;
    const key = String(qNum);
    return {
      questionNumber: qNum,
      correctAnswer: formatCorrectAnswer(answerKey[key]),
      totalAttempts: 0,
      correctCount: 0,
      answerDistribution: {},
    };
  });

  for (const scan of scans.filter((s) => !s.needs_review)) {
    for (let q = 1; q <= totalQuestions; q++) {
      const analysis = analyses[q - 1];
      const studentAnswer = scan.detected_answers?.[String(q)] ?? "";
      if (!studentAnswer) continue;
      analysis.totalAttempts++;
      analysis.answerDistribution[studentAnswer] =
        (analysis.answerDistribution[studentAnswer] ?? 0) + 1;
      const correct = answerKey[String(q)];
      const acceptable = Array.isArray(correct) ? correct : correct ? [correct] : [];
      if (acceptable.includes(studentAnswer)) analysis.correctCount++;
    }
  }

  return analyses;
}

export function exportItemAnalysisCsv(
  subjectName: string,
  analyses: QuestionAnalysis[],
): string {
  const header = "Question,Correct Answer,Attempts,Correct,Percent Correct";
  const lines = analyses.map((a) => {
    const pct = a.totalAttempts > 0 ? Math.round((a.correctCount / a.totalAttempts) * 100) : 0;
    return [a.questionNumber, a.correctAnswer, a.totalAttempts, a.correctCount, `${pct}%`].join(",");
  });
  return [`Subject,${subjectName}`, header, ...lines].join("\n");
}
