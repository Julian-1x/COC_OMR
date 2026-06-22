/** School year / term helpers (aligned with mobile AcademicTerm). */
export function schoolYearForDate(date = new Date()): string {
  const month = date.getMonth() + 1;
  const startYear = month >= 6 ? date.getFullYear() : date.getFullYear() - 1;
  return `${startYear}-${startYear + 1}`;
}

export const commonTermLabels = ["1st Sem", "2nd Sem", "Summer"] as const;

export function defaultTermLabel(date = new Date()): string {
  const month = date.getMonth() + 1;
  if (month >= 6 && month <= 10) return "1st Sem";
  if (month >= 11 || month <= 3) return "2nd Sem";
  return "Summer";
}

export function schoolYearOptions(past = 2, future = 1): string[] {
  const currentStart = Number.parseInt(schoolYearForDate().split("-")[0] ?? "0", 10);
  return Array.from({ length: past + 1 + future }, (_, index) => {
    const start = currentStart - past + index;
    return `${start}-${start + 1}`;
  });
}

export function formatSectionTerm(section: {
  school_year?: string | null;
  term_label?: string | null;
}): string | null {
  const parts = [section.term_label, section.school_year].filter(Boolean);
  return parts.length > 0 ? parts.join(" · ") : null;
}
