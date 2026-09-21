import { describe, expect, it } from "vitest";
import {
  buildAttentionItems,
  buildClassSnapshots,
  examActionLinks,
  suggestExamTarget,
} from "@/lib/omr/desk-insights";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";

function subject(partial: Partial<DbSubject> & Pick<DbSubject, "local_id" | "name">): DbSubject {
  return {
    id: partial.id ?? partial.local_id,
    owner_teacher_id: "t1",
    local_id: partial.local_id,
    name: partial.name,
    answer_key: partial.answer_key ?? {},
    total_questions: partial.total_questions ?? 50,
    section_names: partial.section_names ?? null,
    section_qr_data: {},
    exam_date: null,
    passing_score: partial.passing_score ?? 30,
    use_partial_credit: false,
    sync_status: "synced",
    created_at: "",
    updated_at: "",
  };
}

function student(partial: Pick<DbStudent, "omr_id" | "name" | "section_name">): DbStudent {
  return {
    id: partial.omr_id,
    owner_teacher_id: "t1",
    school_id: partial.omr_id,
    omr_id: partial.omr_id,
    name: partial.name,
    section_name: partial.section_name,
    score: null,
    answers: null,
    scan_date: null,
    confidence: null,
    local_id: null,
    sync_status: "synced",
    created_at: "",
    updated_at: "",
  };
}

function scan(
  partial: Pick<DbScanResult, "id" | "student_omr_id" | "subject_local_id" | "subject_name" | "score"> &
    Partial<DbScanResult>,
): DbScanResult {
  return {
    id: partial.id,
    owner_teacher_id: "t1",
    local_id: partial.id,
    student_omr_id: partial.student_omr_id,
    subject_id: null,
    subject_local_id: partial.subject_local_id,
    subject_name: partial.subject_name,
    sheet_id: null,
    score: partial.score,
    total_questions: partial.total_questions ?? 50,
    confidence: null,
    needs_review: partial.needs_review ?? false,
    manually_confirmed: false,
    review_reasons: null,
    flagged_questions: null,
    scan_time: partial.scan_time ?? "2026-01-01T00:00:00Z",
    detected_answers: partial.detected_answers ?? {},
    correctness_map: {},
    sync_status: "synced",
    created_at: "",
    updated_at: "",
  };
}

describe("desk insights", () => {
  const sections = [{ name: "BSIT-01" }, { name: "BSIT-02" }];
  const students = [
    student({ omr_id: "1", name: "Ann", section_name: "BSIT-01" }),
    student({ omr_id: "2", name: "Ben", section_name: "BSIT-01" }),
    student({ omr_id: "3", name: "Cara", section_name: "BSIT-02" }),
  ];
  const subjects = [
    subject({ local_id: "math", name: "Math", section_names: ["BSIT-01"] }),
    subject({ local_id: "eng", name: "English", section_names: ["BSIT-01", "BSIT-02"] }),
  ];

  it("builds class snapshots with pass rate", () => {
    const scans = [
      scan({
        id: "a",
        student_omr_id: "1",
        subject_local_id: "math",
        subject_name: "Math",
        score: 40,
      }),
      scan({
        id: "b",
        student_omr_id: "2",
        subject_local_id: "math",
        subject_name: "Math",
        score: 20,
      }),
      scan({
        id: "c",
        student_omr_id: "1",
        subject_local_id: "math",
        subject_name: "Math",
        score: 10,
        needs_review: true,
      }),
    ];
    const snaps = buildClassSnapshots(sections, students, scans, subjects);
    const bit01 = snaps.find((s) => s.sectionName === "BSIT-01");
    expect(bit01?.studentCount).toBe(2);
    expect(bit01?.gradedCount).toBe(2);
    expect(bit01?.pendingCount).toBe(1);
    expect(bit01?.failCount).toBe(1);
    expect(bit01?.passRate).toBe(50);
  });

  it("flags attention items", () => {
    const items = buildAttentionItems({
      pendingReview: 2,
      sections: [{ name: "Empty" }, { name: "BSIT-01" }],
      students: [student({ omr_id: "1", name: "Ann", section_name: "BSIT-01" })],
      subjects: [subject({ local_id: "x", name: "Orphan", section_names: [] })],
    });
    expect(items.some((i) => i.id === "pending")).toBe(true);
    expect(items.some((i) => i.label.includes("Empty"))).toBe(true);
    expect(items.some((i) => i.label.includes("Orphan"))).toBe(true);
  });

  it("suggests the least-graded printable exam", () => {
    const scans = [
      scan({
        id: "a",
        student_omr_id: "1",
        subject_local_id: "math",
        subject_name: "Math",
        score: 40,
      }),
    ];
    const target = suggestExamTarget(subjects, ["BSIT-01", "BSIT-02"], scans, students);
    expect(target).not.toBeNull();
    expect(target?.subjectLocalId).toBe("eng");
  });

  it("builds exam action links", () => {
    const links = examActionLinks({
      subjectLocalId: "math",
      subjectName: "Math",
      sectionName: "BSIT-01",
    });
    expect(links.print).toContain("subject=math");
    expect(links.print).toContain("section=BSIT-01");
    expect(links.results).toContain("subject=math");
    expect(links.omrIds).toContain("section=BSIT-01");
  });
});
