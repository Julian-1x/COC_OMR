import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import { formatCorrectAnswer } from "@/lib/omr/answer-key";
import { BLANK_DISTRIBUTION_LABEL, gradedLatestPerStudent } from "@/lib/omr/item-analysis";
import { scanPassed } from "@/lib/omr/passing-score";
import {
  calculateQuestionScore,
  parseStoredAnswerSelections,
} from "@/lib/omr/question-score";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";

export type MissedQuestion = {
  questionNumber: number;
  studentAnswer: string;
  correctAnswer: string;
  partial: boolean;
};

export type StudentFeedbackRow = {
  omrId: string;
  name: string;
  sectionName: string;
  subjectName: string;
  score: number;
  totalQuestions: number;
  percentage: number;
  passed: boolean;
  scanDate: string;
  missed: MissedQuestion[];
};

function formatStudentAnswer(raw: string | null | undefined): string {
  const selections = parseStoredAnswerSelections(raw);
  if (selections.length === 0) {
    return BLANK_DISTRIBUTION_LABEL;
  }
  return selections.join("+");
}

/** Latest approved scan per student → missed-question rows for student handouts. */
export function buildStudentFeedbackRows(
  subject: DbSubject,
  scans: DbScanResult[],
  students: DbStudent[],
): StudentFeedbackRow[] {
  const studentMap = new Map(students.map((s) => [s.omr_id, s]));
  const graded = gradedLatestPerStudent(scans);
  const rows: StudentFeedbackRow[] = [];

  for (const scan of graded) {
    const student = studentMap.get(scan.student_omr_id);
    const missed: MissedQuestion[] = [];

    for (let q = 1; q <= subject.total_questions; q++) {
      const key = String(q);
      const storedAnswer = scan.detected_answers?.[key];
      const score = calculateQuestionScore(subject, q, storedAnswer);
      if (score < 1) {
        missed.push({
          questionNumber: q,
          studentAnswer: formatStudentAnswer(storedAnswer),
          correctAnswer: formatCorrectAnswer(subject.answer_key[key]),
          partial: score > 0,
        });
      }
    }

    rows.push({
      omrId: scan.student_omr_id,
      name: student?.name ?? scan.student_omr_id,
      sectionName: student?.section_name ?? "",
      subjectName: subject.name,
      score: scan.score,
      totalQuestions: scan.total_questions,
      percentage:
        scan.total_questions > 0
          ? Math.round((scan.score / scan.total_questions) * 100)
          : 0,
      passed: scanPassed(scan.score, scan.total_questions, subject.passing_score),
      scanDate: scan.scan_time?.slice(0, 10) ?? "",
      missed,
    });
  }

  return rows.sort((a, b) => {
    const bySection = a.sectionName.localeCompare(b.sectionName);
    if (bySection !== 0) return bySection;
    return a.name.localeCompare(b.name);
  });
}

export async function exportStudentFeedbackPdf(
  subject: DbSubject,
  rows: StudentFeedbackRow[],
  options?: { sectionLabel?: string },
): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const sectionLabel = options?.sectionLabel?.trim();

  for (const row of rows) {
    const page = pdf.addPage([595, 842]);
    let y = 800;

    page.drawText("Exam feedback", {
      x: 40,
      y,
      size: 11,
      font,
      color: rgb(0.35, 0.4, 0.45),
    });
    y -= 18;

    page.drawText(row.subjectName, {
      x: 40,
      y,
      size: 16,
      font: bold,
      color: rgb(0.06, 0.2, 0.15),
    });
    y -= 18;

    const headerMeta = [
      row.sectionName || null,
      sectionLabel && sectionLabel !== row.sectionName ? sectionLabel : null,
      row.scanDate ? `Date: ${row.scanDate}` : null,
    ]
      .filter(Boolean)
      .join(" · ");
    if (headerMeta) {
      page.drawText(headerMeta, { x: 40, y, size: 9, font, color: rgb(0.4, 0.4, 0.4) });
      y -= 20;
    } else {
      y -= 6;
    }

    page.drawText(row.name, { x: 40, y, size: 14, font: bold });
    y -= 16;
    page.drawText(`OMR ID ${row.omrId}`, { x: 40, y, size: 10, font });
    y -= 22;

    const passLabel = row.passed ? "Passed" : "Did not pass";
    page.drawText(
      `Score: ${row.score}/${row.totalQuestions} (${row.percentage}%) · ${passLabel}`,
      { x: 40, y, size: 11, font: bold, color: rgb(0.1, 0.25, 0.2) },
    );
    y -= 28;

    page.drawText("Questions to review", { x: 40, y, size: 11, font: bold });
    y -= 16;

    if (row.missed.length === 0) {
      page.drawText("All answers correct — great work!", {
        x: 40,
        y,
        size: 11,
        font,
        color: rgb(0.05, 0.45, 0.25),
      });
    } else {
      page.drawText("Q#", { x: 40, y, size: 9, font: bold });
      page.drawText("Your answer", { x: 80, y, size: 9, font: bold });
      page.drawText("Correct answer", { x: 200, y, size: 9, font: bold });
      page.drawText("Note", { x: 340, y, size: 9, font: bold });
      y -= 14;

      for (const missed of row.missed) {
        if (y < 70) break;
        page.drawText(String(missed.questionNumber), { x: 40, y, size: 10, font: bold });
        page.drawText(missed.studentAnswer, { x: 80, y, size: 10, font });
        page.drawText(missed.correctAnswer, { x: 200, y, size: 10, font });
        page.drawText(missed.partial ? "Partial" : "Incorrect", {
          x: 340,
          y,
          size: 9,
          font,
          color: missed.partial ? rgb(0.6, 0.45, 0.05) : rgb(0.55, 0.15, 0.15),
        });
        y -= 14;
      }

      if (row.missed.length > 0 && y < 70) {
        page.drawText("(Additional missed questions omitted — ask your teacher.)", {
          x: 40,
          y: 56,
          size: 8,
          font,
          color: rgb(0.5, 0.5, 0.5),
        });
      }
    }

    page.drawText("Generated by COC OMR — for your review only.", {
      x: 40,
      y: 32,
      size: 8,
      font,
      color: rgb(0.55, 0.55, 0.55),
    });
  }

  if (rows.length === 0) {
    const page = pdf.addPage([595, 842]);
    page.drawText("No approved scans to export", {
      x: 40,
      y: 800,
      size: 14,
      font: bold,
    });
    page.drawText(
      "Approve scans on your phone and sync before exporting student feedback.",
      { x: 40, y: 776, size: 10, font },
    );
  }

  return pdf.save();
}
