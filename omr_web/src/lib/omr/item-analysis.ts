import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import type { DbScanResult, DbSubject } from "@/lib/types/database";
import {
  calculateQuestionScore,
  isFullyCorrect,
} from "@/lib/omr/question-score";

export const BLANK_DISTRIBUTION_LABEL = "—";

export type QuestionAnalysis = {
  questionNumber: number;
  correctAnswer: string;
  totalAttempts: number;
  correctCount: number;
  partialCount: number;
  answerDistribution: Record<string, number>;
  discriminationIndex: number | null;
};

export type ItemAnalysisReport = {
  questions: QuestionAnalysis[];
  gradedStudentCount: number;
  pendingReviewCount: number;
  supersededScanCount: number;
};

function formatCorrectAnswerKey(value: string | string[] | undefined): string {
  if (!value) return "?";
  return Array.isArray(value) ? value.join("+") : value;
}

function distributionLabel(storedAnswer: string | null | undefined): string {
  const trimmed = storedAnswer?.trim() ?? "";
  return trimmed.length === 0 ? BLANK_DISTRIBUTION_LABEL : trimmed;
}

function scanPercentage(scan: DbScanResult): number {
  return scan.total_questions > 0 ? scan.score / scan.total_questions : 0;
}

/** Approved scans only; latest scan per student wins (matches Flutter app). */
export function gradedLatestPerStudent(scans: DbScanResult[]): DbScanResult[] {
  const latestByStudent = new Map<string, DbScanResult>();
  for (const scan of scans) {
    if (scan.needs_review) continue;
    const existing = latestByStudent.get(scan.student_omr_id);
    if (!existing || scan.scan_time > existing.scan_time) {
      latestByStudent.set(scan.student_omr_id, scan);
    }
  }
  return [...latestByStudent.values()];
}

function discriminationIndex(
  subject: DbSubject,
  questionNumber: number,
  graded: DbScanResult[],
): number | null {
  if (graded.length < 4) return null;

  const sorted = [...graded].sort((a, b) => scanPercentage(b) - scanPercentage(a));
  const groupSize = Math.max(1, Math.min(Math.ceil(sorted.length * 0.27), Math.floor(sorted.length / 2)));

  const topGroup = sorted.slice(0, groupSize);
  const bottomGroup = sorted.slice(sorted.length - groupSize);

  let topCorrect = 0;
  let bottomCorrect = 0;
  for (const scan of topGroup) {
    if (isFullyCorrect(subject, questionNumber, scan.detected_answers?.[String(questionNumber)])) {
      topCorrect++;
    }
  }
  for (const scan of bottomGroup) {
    if (isFullyCorrect(subject, questionNumber, scan.detected_answers?.[String(questionNumber)])) {
      bottomCorrect++;
    }
  }

  return (topCorrect - bottomCorrect) / groupSize;
}

export function buildItemAnalysisReport(
  subject: DbSubject,
  scans: DbScanResult[],
): ItemAnalysisReport | null {
  const pendingReviewCount = scans.filter((s) => s.needs_review).length;
  const graded = gradedLatestPerStudent(scans);
  if (graded.length === 0) {
    return null;
  }

  const supersededScanCount =
    scans.filter((s) => !s.needs_review).length - graded.length;

  const totalQuestions = subject.total_questions;
  const questions: QuestionAnalysis[] = [];

  for (let qIndex = 0; qIndex < totalQuestions; qIndex++) {
    const qNum = qIndex + 1;
    const key = String(qNum);
    let attempts = 0;
    let correctCount = 0;
    let partialCount = 0;
    const distribution: Record<string, number> = {};

    for (const scan of graded) {
      attempts++;
      const storedAnswer = scan.detected_answers?.[key];
      const label = distributionLabel(storedAnswer);
      distribution[label] = (distribution[label] ?? 0) + 1;

      const score = calculateQuestionScore(subject, qNum, storedAnswer);
      if (score >= 1) {
        correctCount++;
      } else if (score > 0) {
        partialCount++;
      }
    }

    questions.push({
      questionNumber: qNum,
      correctAnswer: formatCorrectAnswerKey(subject.answer_key[key]),
      totalAttempts: attempts,
      correctCount,
      partialCount,
      answerDistribution: distribution,
      discriminationIndex: discriminationIndex(subject, qNum, graded),
    });
  }

  return {
    questions,
    gradedStudentCount: graded.length,
    pendingReviewCount,
    supersededScanCount,
  };
}

export function questionDifficulty(analysis: QuestionAnalysis): number {
  return analysis.totalAttempts > 0 ? analysis.correctCount / analysis.totalAttempts : 0;
}

export function difficultyLabel(analysis: QuestionAnalysis): string {
  const rate = questionDifficulty(analysis);
  if (rate >= 0.8) return "Easy";
  if (rate >= 0.5) return "Medium";
  if (rate >= 0.3) return "Hard";
  return "Very hard";
}

export function difficultyColorClass(analysis: QuestionAnalysis): string {
  const rate = questionDifficulty(analysis);
  if (rate >= 0.8) return "text-emerald-700 bg-emerald-50";
  if (rate >= 0.5) return "text-amber-800 bg-amber-50";
  if (rate >= 0.3) return "text-orange-800 bg-orange-50";
  return "text-red-800 bg-red-50";
}

export function isDistributionChoiceCorrect(
  subject: DbSubject,
  questionNumber: number,
  distributionLabelValue: string,
): boolean {
  if (distributionLabelValue === BLANK_DISTRIBUTION_LABEL) return false;
  return isFullyCorrect(subject, questionNumber, distributionLabelValue);
}

export function sortedDistributionKeys(distribution: Record<string, number>): string[] {
  const preferred = ["A", "B", "C", "D", "E", "F", BLANK_DISTRIBUTION_LABEL];
  const keys = preferred.filter((k) => k in distribution);
  for (const key of Object.keys(distribution)) {
    if (!keys.includes(key)) keys.push(key);
  }
  return keys;
}

export type DiscriminationQuality = "strong" | "good" | "fair" | "weak" | "unknown";

/** Classic classroom bands for upper–lower discrimination (D). */
export function discriminationQuality(d: number | null): DiscriminationQuality {
  if (d === null || Number.isNaN(d)) return "unknown";
  if (d >= 0.4) return "strong";
  if (d >= 0.3) return "good";
  if (d >= 0.2) return "fair";
  return "weak";
}

export function discriminationLabel(d: number | null): string {
  switch (discriminationQuality(d)) {
    case "strong":
    case "good":
      return "Works well";
    case "fair":
      return "Okay";
    case "weak":
      return "Check this question";
    default:
      return "Need more graded sheets";
  }
}

export function discriminationColorClass(d: number | null): string {
  switch (discriminationQuality(d)) {
    case "strong":
      return "text-emerald-800 bg-emerald-50";
    case "good":
      return "text-emerald-700 bg-emerald-50";
    case "fair":
      return "text-amber-800 bg-amber-50";
    case "weak":
      return "text-red-800 bg-red-50";
    default:
      return "text-slate-600 bg-slate-50";
  }
}

export type SortMode = "number" | "hardest" | "easiest" | "weakD";

export function sortQuestions(
  questions: QuestionAnalysis[],
  mode: SortMode,
): QuestionAnalysis[] {
  const next = [...questions];
  switch (mode) {
    case "hardest":
      next.sort((a, b) => questionDifficulty(a) - questionDifficulty(b));
      break;
    case "easiest":
      next.sort((a, b) => questionDifficulty(b) - questionDifficulty(a));
      break;
    case "weakD":
      next.sort((a, b) => {
        const da = a.discriminationIndex ?? -2;
        const db = b.discriminationIndex ?? -2;
        return da - db;
      });
      break;
    default:
      next.sort((a, b) => a.questionNumber - b.questionNumber);
  }
  return next;
}

export function overallDifficulty(report: ItemAnalysisReport): number {
  if (report.questions.length === 0) return 0;
  const sum = report.questions.reduce((acc, q) => acc + questionDifficulty(q), 0);
  return sum / report.questions.length;
}

export type AttentionFlag = {
  questionNumber: number;
  reasons: string[];
  topWrongChoice: string | null;
  topWrongCount: number;
};

/** Items teachers should reteach or rewrite (hard + weak D, or popular wrong choice). */
export function questionsNeedingAttention(
  subject: DbSubject,
  report: ItemAnalysisReport,
): AttentionFlag[] {
  const flags: AttentionFlag[] = [];
  for (const q of report.questions) {
    const reasons: string[] = [];
    const rate = questionDifficulty(q);
    const d = q.discriminationIndex;

    if (rate < 0.3) {
      reasons.push(
        rate <= 0
          ? "Nobody got this right"
          : `Only ${Math.round(rate * 100)}% got this right`,
      );
    }
    if (d !== null && d < 0.2) {
      reasons.push("Strong students missed this too");
    }

    let topWrongChoice: string | null = null;
    let topWrongCount = 0;
    for (const [choice, count] of Object.entries(q.answerDistribution)) {
      if (isDistributionChoiceCorrect(subject, q.questionNumber, choice)) continue;
      if (count > topWrongCount) {
        topWrongChoice = choice;
        topWrongCount = count;
      }
    }
    if (
      topWrongChoice &&
      topWrongCount >= Math.max(2, Math.ceil(q.totalAttempts * 0.25))
    ) {
      reasons.push(
        `${topWrongCount} of ${q.totalAttempts} chose ${topWrongChoice}`,
      );
    }

    if (reasons.length > 0) {
      flags.push({
        questionNumber: q.questionNumber,
        reasons,
        topWrongChoice,
        topWrongCount,
      });
    }
  }

  return flags.sort((a, b) => {
    const qa = report.questions.find((q) => q.questionNumber === a.questionNumber)!;
    const qb = report.questions.find((q) => q.questionNumber === b.questionNumber)!;
    return questionDifficulty(qa) - questionDifficulty(qb);
  });
}

export function exportItemAnalysisCsv(
  subjectName: string,
  report: ItemAnalysisReport,
  subject?: DbSubject,
): string {
  const header =
    "Question,Correct answer,Graded sheets,Got it right,Partly right,Percent correct,How hard,Separates the class,What to look at";
  const attention = subject
    ? new Map(
        questionsNeedingAttention(subject, report).map((f) => [
          f.questionNumber,
          f.reasons.join("; "),
        ]),
      )
    : new Map<number, string>();

  const lines = report.questions.map((a) => {
    const pct = a.totalAttempts > 0 ? Math.round((a.correctCount / a.totalAttempts) * 100) : 0;
    return [
      a.questionNumber,
      `"${a.correctAnswer.replace(/"/g, '""')}"`,
      a.totalAttempts,
      a.correctCount,
      a.partialCount,
      `${pct}%`,
      difficultyLabel(a),
      discriminationLabel(a.discriminationIndex),
      `"${(attention.get(a.questionNumber) ?? "").replace(/"/g, '""')}"`,
    ].join(",");
  });
  return [
    `Subject,${subjectName}`,
    `Graded students,${report.gradedStudentCount}`,
    `Pending review,${report.pendingReviewCount}`,
    `Overall percent correct,${Math.round(overallDifficulty(report) * 100)}%`,
    header,
    ...lines,
  ].join("\n");
}

export async function exportItemAnalysisPdf(
  subjectName: string,
  report: ItemAnalysisReport,
  subject?: DbSubject,
): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);

  let page = pdf.addPage([595, 842]);
  let y = 800;

  function newPageIfNeeded(lines = 1) {
    if (y < 60 + lines * 14) {
      page = pdf.addPage([595, 842]);
      y = 800;
    }
  }

  page.drawText(`Item analysis — ${subjectName}`, {
    x: 40,
    y,
    size: 14,
    font: bold,
    color: rgb(0.06, 0.2, 0.15),
  });
  y -= 20;

  function drawWrapped(text: string, x: number, size: number, usedFont: typeof font) {
    const words = text.split(" ");
    let line = "";
    for (const word of words) {
      const next = line ? `${line} ${word}` : word;
      if (usedFont.widthOfTextAtSize(next, size) > 515 - (x - 40) && line) {
        newPageIfNeeded();
        page.drawText(line, { x, y, size, font: usedFont });
        y -= size + 4;
        line = word;
      } else {
        line = next;
      }
    }
    if (line) {
      newPageIfNeeded();
      page.drawText(line, { x, y, size, font: usedFont });
      y -= size + 4;
    }
  }

  const overall = Math.round(overallDifficulty(report) * 100);
  const pendingLine =
    report.pendingReviewCount > 0
      ? `${report.pendingReviewCount} sheet${report.pendingReviewCount === 1 ? "" : "s"} still need review on the phone.`
      : "No sheets are waiting for review.";
  drawWrapped(
    `${report.gradedStudentCount} graded students. They got ${overall}% of the questions right. ${pendingLine}`,
    40,
    9,
    font,
  );
  y -= 8;

  const hardest = [...report.questions]
    .sort((a, b) => questionDifficulty(a) - questionDifficulty(b))
    .slice(0, 5);
  if (hardest.length > 0) {
    page.drawText("Hardest questions", { x: 40, y, size: 11, font: bold });
    y -= 16;
    for (const q of hardest) {
      const pct = Math.round(questionDifficulty(q) * 100);
      const howHard = pct <= 0 ? "Nobody got this right" : `${pct}% got this right`;
      drawWrapped(
        `Question ${q.questionNumber} — ${howHard}. The answer is ${q.correctAnswer}.`,
        48,
        9,
        font,
      );
    }
    y -= 8;
  }

  if (subject) {
    const attention = questionsNeedingAttention(subject, report);
    if (attention.length > 0) {
      newPageIfNeeded(3);
      page.drawText("Questions to reteach", { x: 40, y, size: 11, font: bold });
      y -= 16;
      for (const flag of attention) {
        drawWrapped(
          `Question ${flag.questionNumber} — ${flag.reasons.join(". ")}.`,
          48,
          9,
          font,
        );
      }
      y -= 8;
    }
  }

  newPageIfNeeded(3);
  page.drawText("Every question", { x: 40, y, size: 11, font: bold });
  y -= 16;

  for (const a of report.questions) {
    const partial =
      a.partialCount > 0 ? ` ${a.partialCount} were partly right.` : "";
    drawWrapped(
      `Question ${a.questionNumber}. Answer ${a.correctAnswer}. ${a.correctCount} of ${a.totalAttempts} got it right. ${difficultyLabel(a)}. ${discriminationLabel(a.discriminationIndex)}.${partial}`,
      48,
      9,
      font,
    );
    const dist = sortedDistributionKeys(a.answerDistribution)
      .map((k) => `${k} ${a.answerDistribution[k]}`)
      .join(", ");
    if (dist) {
      drawWrapped(`Choices: ${dist}`, 60, 8, font);
    }
    y -= 4;
  }

  return pdf.save();
}

/** @deprecated Use buildItemAnalysisReport */
export function computeItemAnalysis(
  scans: DbScanResult[],
  answerKey: Record<string, string | string[]>,
  totalQuestions: number,
): QuestionAnalysis[] {
  const subject = {
    answer_key: answerKey,
    total_questions: totalQuestions,
    use_partial_credit: false,
  } as DbSubject;
  const report = buildItemAnalysisReport(subject, scans);
  return report?.questions ?? [];
}
