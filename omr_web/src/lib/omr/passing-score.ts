/** Matches Flutter Subject.passingScore — raw points needed to pass, not percent. */

export function defaultPassingPoints(totalQuestions: number): number {
  return Math.max(1, Math.round(totalQuestions * 0.6));
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
