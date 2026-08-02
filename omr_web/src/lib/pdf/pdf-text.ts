/**
 * pdf-lib StandardFonts only support WinAnsi. Strip/replace characters that break PDF export
 * (e.g. ≥ in passing labels, smart quotes in student names).
 */
export function pdfSafeText(text: string): string {
  return text
    .replace(/≥/g, ">=")
    .replace(/≤/g, "<=")
    .replace(/–/g, "-")
    .replace(/—/g, "-")
    .replace(/…/g, "...")
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\x09\x0A\x0D\x20-\x7E]/g, "?");
}

/** Human-readable passing label safe for PDF body text. */
export function formatPassingLabelPdf(passingScorePoints: number, totalQuestions: number): string {
  if (totalQuestions <= 0) return "Pass score not set";
  const pct = Math.round((passingScorePoints / totalQuestions) * 100);
  return `${pct}% pass (>= ${passingScorePoints} pts)`;
}
