/** Matches Flutter Subject.passingScore — raw points needed to pass, not percent. */

/** Fixed school policy: 60% of items required to pass. */
export const PASS_RATE = 0.6;

export function defaultPassingPoints(totalQuestions: number): number {
  return Math.max(1, Math.round(totalQuestions * PASS_RATE));
}

export function passingPercent(passingScorePoints: number, totalQuestions: number): number {
  if (totalQuestions <= 0) return 0;
  return Math.round((passingScorePoints / totalQuestions) * 100);
}

export function scanPassed(
  score: number,
  totalQuestions: number,
  passingScorePoints: number,
): boolean {
  if (totalQuestions <= 0) return false;
  return score >= passingScorePoints;
}

export function formatPassingLabel(passingScorePoints: number, totalQuestions: number): string {
  const pct = passingPercent(passingScorePoints, totalQuestions);
  return `${pct}% pass (≥${passingScorePoints} pts)`;
}

/** Today as YYYY-MM-DD for exam_date stamped at print time. */
export function todayExamDateIso(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}
