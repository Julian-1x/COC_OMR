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
      return "Strong";
    case "good":
      return "Good";
    case "fair":
      return "Fair";
    case "weak":
      return "Weak";
    default:
      return "Need more scans";
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
      reasons.push(`Only ${Math.round(rate * 100)}% got it right`);
    }
    if (d !== null && d < 0.2) {
      reasons.push(`Weak discrimination (D ${d.toFixed(2)})`);
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
        `Many chose ${topWrongChoice} (${topWrongCount}/${q.totalAttempts})`,
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
    "Question,Correct Answer,Attempts,Correct,Partial,Percent Correct,Discrimination,D Quality,Difficulty,Attention";
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
    const d = a.discriminationIndex !== null ? a.discriminationIndex.toFixed(2) : "";
    return [
      a.questionNumber,
      `"${a.correctAnswer.replace(/"/g, '""')}"`,
      a.totalAttempts,
      a.correctCount,
      a.partialCount,
      `${pct}%`,
      d,
      discriminationLabel(a.discriminationIndex),
      difficultyLabel(a),
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
  page.drawText(
    `Graded: ${report.gradedStudentCount} students · Pending review: ${report.pendingReviewCount} · ` +
      `Overall correct: ${Math.round(overallDifficulty(report) * 100)}%`,
    { x: 40, y, size: 9, font },
  );
  y -= 24;

  const hardest = [...report.questions]
    .sort((a, b) => questionDifficulty(a) - questionDifficulty(b))
    .slice(0, 5);
  if (hardest.length > 0) {
    page.drawText("Hardest questions:", { x: 40, y, size: 10, font: bold });
    y -= 14;
    for (const q of hardest) {
      newPageIfNeeded();
      const pct = Math.round(questionDifficulty(q) * 100);
      page.drawText(`Q${q.questionNumber} — ${pct}% correct (key ${q.correctAnswer})`, {
        x: 48,
        y,
        size: 9,
        font,
      });
      y -= 12;
    }
    y -= 8;
  }

  if (subject) {
    const attention = questionsNeedingAttention(subject, report).slice(0, 8);
    if (attention.length > 0) {
      page.drawText("Needs attention (reteach or rewrite):", {
        x: 40,
        y,
        size: 10,
        font: bold,
      });
      y -= 14;
      for (const flag of attention) {
        newPageIfNeeded(2);
        page.drawText(`Q${flag.questionNumber} — ${flag.reasons.join("; ").slice(0, 85)}`, {
          x: 48,
          y,
          size: 8,
          font,
        });
        y -= 11;
      }
      y -= 8;
    }
  }

  page.drawText("Q#  Key  Correct  Partial  P%  D   Quality", {
    x: 40,
    y,
    size: 9,
    font: bold,
  });
  y -= 14;

  for (const a of report.questions) {
    newPageIfNeeded(2);
    const pct = a.totalAttempts > 0 ? Math.round((a.correctCount / a.totalAttempts) * 100) : 0;
    const d = a.discriminationIndex !== null ? a.discriminationIndex.toFixed(2) : "—";
    const quality = discriminationLabel(a.discriminationIndex);
    page.drawText(
      `${String(a.questionNumber).padStart(2)}   ${a.correctAnswer.padEnd(4)} ${String(a.correctCount).padStart(3)}/${a.totalAttempts}   ${String(a.partialCount).padStart(3)}   ${String(pct).padStart(3)}%  ${d.padStart(5)}  ${quality}`,
      { x: 40, y, size: 8, font },
    );
    y -= 11;
    const dist = sortedDistributionKeys(a.answerDistribution)
      .map((k) => `${k}:${a.answerDistribution[k]}`)
      .join(" ");
    if (dist) {
      newPageIfNeeded();
      page.drawText(`     ${dist.slice(0, 90)}`, {
        x: 40,
        y,
        size: 7,
        font,
        color: rgb(0.4, 0.4, 0.4),
      });
      y -= 10;
    }
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
