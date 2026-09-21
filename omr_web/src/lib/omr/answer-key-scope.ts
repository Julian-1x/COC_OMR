/**
 * Mirrors lib/utils/answer_key_scope.dart — shared vs section-only vs unassigned.
 * Teachers must never confuse which sections a key grades.
 */

export type AnswerKeyScopeKind = "unassigned" | "sectionOnly" | "shared";

export type AnswerKeyScopeInput = {
  section_names?: string[] | null;
  name?: string | null;
};

export type AnswerKeyScope = {
  kind: AnswerKeyScopeKind;
  sections: string[];
  isShared: boolean;
  isSectionOnly: boolean;
  isUnassigned: boolean;
  shortBadge: string;
  badgeLabel: string;
  listSubtitle: string;
  gradingContextLabel: string;
  printScopeTag: string;
  describeSubject: string;
  allowsSection: (sectionName: string) => boolean;
};

function normalizeSections(sectionNames: string[] | null | undefined): string[] {
  return (sectionNames ?? [])
    .map((name) => name.trim())
    .filter((name) => name.length > 0);
}

export function answerKeyScopeOf(subject: AnswerKeyScopeInput): AnswerKeyScope {
  const sections = normalizeSections(subject.section_names);
  const kind: AnswerKeyScopeKind =
    sections.length === 0 ? "unassigned" : sections.length === 1 ? "sectionOnly" : "shared";

  const shortBadge =
    kind === "unassigned" ? "No section" : kind === "sectionOnly" ? "One section" : "Shared";

  const badgeLabel =
    kind === "unassigned"
      ? "No section"
      : kind === "sectionOnly"
        ? `One section · ${sections[0]}`
        : `Shared · ${sections.length} sections`;

  const listSubtitle =
    kind === "unassigned"
      ? "Add a section before print or scan"
      : kind === "sectionOnly"
        ? `Grades ${sections[0]} only`
        : `Same answers for ${sections.join(", ")}`;

  const gradingContextLabel =
    kind === "unassigned"
      ? "No section on this key"
      : kind === "sectionOnly"
        ? `Grading ${sections[0]} only`
        : `Shared key · ${sections.join(", ")}`;

  const printScopeTag =
    kind === "unassigned" ? "NO SECTION" : kind === "sectionOnly" ? "THIS SECTION ONLY" : "SHARED KEY";

  const displayName = (subject.name ?? "").trim() || "Answer key";
  const describeSubject =
    kind === "unassigned"
      ? `${displayName} · no section`
      : kind === "sectionOnly"
        ? `${displayName} · ${sections[0]} only`
        : sections.length <= 2
          ? `${displayName} · Shared (${sections.join(", ")})`
          : `${displayName} · Shared (${sections.length} sections)`;

  return {
    kind,
    sections,
    isShared: kind === "shared",
    isSectionOnly: kind === "sectionOnly",
    isUnassigned: kind === "unassigned",
    shortBadge,
    badgeLabel,
    listSubtitle,
    gradingContextLabel,
    printScopeTag,
    describeSubject,
    allowsSection(sectionName: string) {
      const needle = sectionName.trim().toLowerCase();
      if (!needle) return false;
      return sections.some((s) => s.toLowerCase() === needle);
    },
  };
}

export function isStandardSheetQuestionCount(totalQuestions: number): boolean {
  return totalQuestions >= 30 && totalQuestions <= 100;
}

export function normalizeSectionKey(name: string): string {
  return name.trim().toLowerCase();
}

/** Active (non-archived) section names as a lookup set. */
export function activeSectionKeySet(activeSectionNames: string[]): Set<string> {
  return new Set(
    activeSectionNames.map(normalizeSectionKey).filter((name) => name.length > 0),
  );
}

/**
 * True when the answer key is still bound to at least one non-archived section.
 * Shared keys stay printable if any linked section is still active.
 */
export function subjectHasLiveSection(
  subject: AnswerKeyScopeInput,
  activeSections: Set<string> | string[],
): boolean {
  const active =
    activeSections instanceof Set
      ? activeSections
      : activeSectionKeySet(activeSections);
  const scope = answerKeyScopeOf(subject);
  if (scope.isUnassigned) return false;
  return scope.sections.some((name) => active.has(normalizeSectionKey(name)));
}

/** Drop answer keys whose every bound section has been archived. */
export function filterSubjectsWithLiveSections<T extends AnswerKeyScopeInput>(
  subjects: T[],
  activeSectionNames: string[],
): T[] {
  const active = activeSectionKeySet(activeSectionNames);
  return subjects.filter((subject) => subjectHasLiveSection(subject, active));
}

/** Linked sections that are still active (for print section pickers). */
export function liveSectionsForSubject(
  subject: AnswerKeyScopeInput,
  activeSectionNames: string[],
): string[] {
  const active = activeSectionKeySet(activeSectionNames);
  return answerKeyScopeOf(subject).sections.filter((name) =>
    active.has(normalizeSectionKey(name)),
  );
}
