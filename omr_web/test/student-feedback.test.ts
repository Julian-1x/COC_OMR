import { describe, expect, it } from "vitest";
import { buildStudentFeedbackRows } from "@/lib/omr/student-feedback";
import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";

const subject: DbSubject = {
  id: "sub-1",
  owner_teacher_id: "t1",
  local_id: "SUB-0001",
  name: "Math",
  answer_key: {
    "1": "A",
    "2": "B",
    "3": ["A", "B"],
  },
  total_questions: 3,
  section_names: ["BSIT-1A"],
  section_qr_data: {},
  exam_date: "2026-04-08",
  passing_score: 2,
  use_partial_credit: true,
  sync_status: "synced",
  created_at: "",
  updated_at: "",
};

const students: DbStudent[] = [
  {
    id: "stu-1",
    owner_teacher_id: "t1",
    school_id: "2024-001",
    omr_id: "0001",
    name: "Ana Cruz",
    section_name: "BSIT-1A",
    score: null,
    answers: null,
    scan_date: null,
    confidence: null,
    local_id: null,
    sync_status: "synced",
    created_at: "",
    updated_at: "",
  },
];

function scan(partial: Partial<DbScanResult> & Pick<DbScanResult, "student_omr_id">): DbScanResult {
  return {
    id: `scan-${partial.student_omr_id}-${partial.scan_time ?? "a"}`,
    owner_teacher_id: "t1",
    student_omr_id: partial.student_omr_id,
    subject_id: subject.id,
    subject_local_id: subject.local_id,
    subject_name: subject.name,
    sheet_id: null,
    detected_answers: partial.detected_answers ?? {},
    correctness_map: partial.correctness_map ?? {},
    score: partial.score ?? 0,
    total_questions: partial.total_questions ?? 3,
    confidence: partial.confidence ?? 0.9,
    scan_time: partial.scan_time ?? "2026-04-08T10:00:00Z",
    review_reasons: null,
    flagged_questions: null,
    manually_confirmed: true,
    needs_review: partial.needs_review ?? false,
    local_id: null,
    sync_status: "synced",
    created_at: "",
    updated_at: "",
  };
}

describe("buildStudentFeedbackRows", () => {
  it("returns empty missed list when all answers are correct", () => {
    const rows = buildStudentFeedbackRows(
      subject,
      [
        scan({
          student_omr_id: "0001",
          score: 3,
          detected_answers: { "1": "A", "2": "B", "3": "A+B" },
        }),
      ],
      students,
    );

    expect(rows).toHaveLength(1);
    expect(rows[0].missed).toEqual([]);
    expect(rows[0].name).toBe("Ana Cruz");
  });

  it("lists wrong answers with correct key on missed questions", () => {
    const rows = buildStudentFeedbackRows(
      subject,
      [
        scan({
          student_omr_id: "0001",
          score: 1,
          detected_answers: { "1": "B", "2": "B", "3": "A" },
        }),
      ],
      students,
    );

    expect(rows[0].missed).toHaveLength(2);
    expect(rows[0].missed[0]).toMatchObject({
      questionNumber: 1,
      studentAnswer: "B",
      correctAnswer: "A",
      partial: false,
    });
    expect(rows[0].missed[1]).toMatchObject({
      questionNumber: 3,
      studentAnswer: "A",
      correctAnswer: "A or B",
      partial: true,
    });
  });

  it("shows blank student answer as em dash", () => {
    const rows = buildStudentFeedbackRows(
      subject,
      [
        scan({
          student_omr_id: "0001",
          score: 0,
          detected_answers: { "2": "B" },
        }),
      ],
      students,
    );

    const q1 = rows[0].missed.find((m) => m.questionNumber === 1);
    expect(q1?.studentAnswer).toBe("—");
  });

  it("uses latest approved scan per student", () => {
    const rows = buildStudentFeedbackRows(
      subject,
      [
        scan({
          student_omr_id: "0001",
          score: 0,
          scan_time: "2026-04-08T09:00:00Z",
          detected_answers: { "1": "B", "2": "B", "3": "A" },
        }),
        scan({
          student_omr_id: "0001",
          score: 2,
          scan_time: "2026-04-08T11:00:00Z",
          detected_answers: { "1": "A", "2": "B", "3": "A" },
        }),
      ],
      students,
    );

    expect(rows).toHaveLength(1);
    expect(rows[0].missed).toHaveLength(1);
    expect(rows[0].missed[0].questionNumber).toBe(3);
  });

  it("excludes scans that still need review", () => {
    const rows = buildStudentFeedbackRows(
      subject,
      [
        scan({
          student_omr_id: "0001",
          needs_review: true,
          detected_answers: { "1": "B" },
        }),
      ],
      students,
    );

    expect(rows).toHaveLength(0);
  });
});
