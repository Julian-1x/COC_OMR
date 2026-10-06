import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from "pdf-lib";
import { formatCorrectAnswer } from "@/lib/omr/answer-key";
import { BLANK_DISTRIBUTION_LABEL, gradedLatestPerStudent } from "@/lib/omr/item-analysis";
import { scanPassed } from "@/lib/omr/passing-score";
import {
  calculateQuestionScore,
  parseStoredAnswerSelections,
} from "@/lib/omr/question-score";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";

export type FeedbackQuestionStatus = "correct" | "incorrect" | "partial";

export type FeedbackQuestion = {
  questionNumber: number;
  studentAnswer: string;
  correctAnswer: string;
  status: FeedbackQuestionStatus;
};

/** @deprecated Use FeedbackQuestion — kept for older imports. */
export type MissedQuestion = FeedbackQuestion;

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
  /** Every question the system graded for this scan (correct + incorrect). */
  questions: FeedbackQuestion[];
};

function formatStudentAnswer(raw: string | null | undefined): string {
  const selections = parseStoredAnswerSelections(raw);
  if (selections.length === 0) {
    return BLANK_DISTRIBUTION_LABEL;
  }
  return selections.join("+");
}

function statusForScore(score: number): FeedbackQuestionStatus {
  if (score >= 1) return "correct";
  if (score > 0) return "partial";
  return "incorrect";
}

/** Latest approved scan per student → full answer list for student handouts. */
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
    const questions: FeedbackQuestion[] = [];

    for (let q = 1; q <= subject.total_questions; q++) {
      const key = String(q);
      const storedAnswer = scan.detected_answers?.[key];
      const score = calculateQuestionScore(subject, q, storedAnswer);
      questions.push({
        questionNumber: q,
        studentAnswer: formatStudentAnswer(storedAnswer),
        correctAnswer: formatCorrectAnswer(subject.answer_key[key]),
        status: statusForScore(score),
      });
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
      questions,
    });
  }

  return rows.sort((a, b) => {
    const bySection = a.sectionName.localeCompare(b.sectionName);
    if (bySection !== 0) return bySection;
    return a.name.localeCompare(b.name);
  });
}

function noteLabel(status: FeedbackQuestionStatus): string {
  if (status === "correct") return "Correct";
  if (status === "partial") return "Partial";
  return "Incorrect";
}

function noteColor(status: FeedbackQuestionStatus) {
  if (status === "correct") return rgb(0.05, 0.45, 0.25);
  if (status === "partial") return rgb(0.6, 0.45, 0.05);
  return rgb(0.55, 0.15, 0.15);
}

function drawTableHeader(page: PDFPage, y: number, bold: PDFFont) {
  page.drawText("Q#", { x: 40, y, size: 9, font: bold });
  page.drawText("Your answer", { x: 80, y, size: 9, font: bold });
  page.drawText("Correct answer", { x: 200, y, size: 9, font: bold });
  page.drawText("Note", { x: 340, y, size: 9, font: bold });
}

function drawStudentHeader(
  page: PDFPage,
  row: StudentFeedbackRow,
  font: PDFFont,
  bold: PDFFont,
  options: { sectionLabel?: string; continued: boolean },
): number {
  let y = 800;

  page.drawText(options.continued ? "Exam feedback (continued)" : "Exam feedback", {
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
    options.sectionLabel && options.sectionLabel !== row.sectionName
      ? options.sectionLabel
      : null,
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

  if (!options.continued) {
    const passLabel = row.passed ? "Passed" : "Did not pass";
    page.drawText(
      `Score: ${row.score}/${row.totalQuestions} (${row.percentage}%) · ${passLabel}`,
      { x: 40, y, size: 11, font: bold, color: rgb(0.1, 0.25, 0.2) },
    );
    y -= 28;

    page.drawText("What the system recorded", { x: 40, y, size: 11, font: bold });
    y -= 14;
    page.drawText("Every question — correct and incorrect — for teacher / student review.", {
      x: 40,
      y,
      size: 8,
      font,
      color: rgb(0.45, 0.45, 0.45),
    });
    y -= 16;
  } else {
    y -= 8;
  }

  return y;
}

function drawFooter(page: PDFPage, font: PDFFont) {
  page.drawText("Generated by COC OMR — for your review only.", {
    x: 40,
    y: 32,
    size: 8,
    font,
    color: rgb(0.55, 0.55, 0.55),
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
    let page = pdf.addPage([595, 842]);
    let y = drawStudentHeader(page, row, font, bold, {
      sectionLabel,
      continued: false,
    });
    drawTableHeader(page, y, bold);
    y -= 14;

    for (const question of row.questions) {
      if (y < 56) {
        drawFooter(page, font);
        page = pdf.addPage([595, 842]);
        y = drawStudentHeader(page, row, font, bold, {
          sectionLabel,
          continued: true,
        });
        drawTableHeader(page, y, bold);
        y -= 14;
      }

      page.drawText(String(question.questionNumber), { x: 40, y, size: 10, font: bold });
      page.drawText(question.studentAnswer, { x: 80, y, size: 10, font });
      page.drawText(question.correctAnswer, { x: 200, y, size: 10, font });
      page.drawText(noteLabel(question.status), {
        x: 340,
        y,
        size: 9,
        font,
        color: noteColor(question.status),
      });
      y -= 14;
    }

    drawFooter(page, font);
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
