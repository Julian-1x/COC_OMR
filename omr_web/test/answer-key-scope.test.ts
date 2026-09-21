import { describe, expect, it } from "vitest";
import {
  answerKeyScopeOf,
  filterSubjectsWithLiveSections,
  isStandardSheetQuestionCount,
  liveSectionsForSubject,
  subjectHasLiveSection,
} from "@/lib/omr/answer-key-scope";

describe("answerKeyScopeOf", () => {
  it("marks unassigned keys", () => {
    const scope = answerKeyScopeOf({ name: "Math", section_names: [] });
    expect(scope.kind).toBe("unassigned");
    expect(scope.printScopeTag).toBe("NO SECTION");
    expect(scope.allowsSection("BSIT-01")).toBe(false);
  });

  it("marks section-only keys", () => {
    const scope = answerKeyScopeOf({
      name: "Math",
      section_names: [" BSIT-01 "],
    });
    expect(scope.kind).toBe("sectionOnly");
    expect(scope.shortBadge).toBe("One section");
    expect(scope.printScopeTag).toBe("THIS SECTION ONLY");
    expect(scope.allowsSection("BSIT-01")).toBe(true);
    expect(scope.allowsSection("BSIT-02")).toBe(false);
  });

  it("marks shared keys", () => {
    const scope = answerKeyScopeOf({
      name: "Math",
      section_names: ["A", "B", "C"],
    });
    expect(scope.kind).toBe("shared");
    expect(scope.printScopeTag).toBe("SHARED KEY");
    expect(scope.badgeLabel).toContain("3 sections");
    expect(scope.allowsSection("b")).toBe(true);
  });
});

describe("isStandardSheetQuestionCount", () => {
  it("allows 30–100 only", () => {
    expect(isStandardSheetQuestionCount(29)).toBe(false);
    expect(isStandardSheetQuestionCount(30)).toBe(true);
    expect(isStandardSheetQuestionCount(100)).toBe(true);
    expect(isStandardSheetQuestionCount(101)).toBe(false);
  });
});

describe("archived section print filtering", () => {
  it("keeps shared keys when any linked section is still active", () => {
    const subject = {
      name: "Test",
      section_names: ["COC-FA-ME2-02", "COC-FA-ME2-03"],
    };
    expect(subjectHasLiveSection(subject, ["COC-FA-ME2-03"])).toBe(true);
    expect(liveSectionsForSubject(subject, ["COC-FA-ME2-03"])).toEqual([
      "COC-FA-ME2-03",
    ]);
  });

  it("hides keys when every linked section is archived", () => {
    const subjects = [
      { name: "Gone", section_names: ["A", "B"] },
      { name: "Live", section_names: ["A", "C"] },
      { name: "Orphan", section_names: [] },
    ];
    expect(filterSubjectsWithLiveSections(subjects, ["C"]).map((s) => s.name)).toEqual([
      "Live",
    ]);
  });
});
