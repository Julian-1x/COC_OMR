import { describe, expect, it } from "vitest";
import {
  discriminationLabel,
  discriminationQuality,
  overallDifficulty,
  questionsNeedingAttention,
  sortQuestions,
  buildItemAnalysisReport,
  type QuestionAnalysis,
} from "@/lib/omr/item-analysis";
import type { DbScanResult, DbSubject } from "@/lib/types/database";

function subject(overrides: Partial<DbSubject> = {}): DbSubject {
  return {
    id: "1",
    owner_teacher_id: "t",
    local_id: "SUB-1",
    name: "Math",
    answer_key: {
      "1": "A",
      "2": "B",
      "3": "C",
      "4": "D",
    },
    total_questions: 4,
    section_names: ["7-A"],
    section_qr_data: {},
    exam_date: null,
    passing_score: 2,
    use_partial_credit: false,
    sync_status: "synced",
    created_at: "2026-01-01",
    updated_at: "2026-01-01",
    ...overrides,
  };
}

function scan(
  omrId: string,
  answers: Record<string, string>,
  score: number,
  opts: Partial<DbScanResult> = {},
): DbScanResult {
  return {
    id: `scan-${omrId}`,
    owner_teacher_id: "t",
    student_omr_id: omrId,
    subject_id: "1",
    subject_local_id: "SUB-1",
    subject_name: "Math",
    sheet_id: null,
    detected_answers: answers,
    correctness_map: {},
    score,
    total_questions: 4,
    confidence: 1,
    scan_time: "2026-01-02T10:00:00.000Z",
    review_reasons: null,
    flagged_questions: null,
    manually_confirmed: true,
    needs_review: false,
    local_id: `local-${omrId}`,
    sync_status: "synced",
    created_at: "2026-01-02",
    updated_at: "2026-01-02",
    ...opts,
  };
}

describe("web item analysis helpers", () => {
  it("labels discrimination bands for teachers", () => {
    expect(discriminationQuality(0.45)).toBe("strong");
    expect(discriminationLabel(0.32)).toBe("Good");
    expect(discriminationLabel(0.21)).toBe("Fair");
    expect(discriminationLabel(0.1)).toBe("Weak");
    expect(discriminationLabel(null)).toBe("Need more scans");
  });

  it("sorts hardest and weakest D", () => {
    const rows: QuestionAnalysis[] = [
      {
        questionNumber: 1,
        correctAnswer: "A",
        totalAttempts: 10,
        correctCount: 9,
        partialCount: 0,
        answerDistribution: { A: 9, B: 1 },
        discriminationIndex: 0.5,
      },
      {
        questionNumber: 2,
        correctAnswer: "B",
        totalAttempts: 10,
        correctCount: 2,
        partialCount: 0,
        answerDistribution: { B: 2, C: 8 },
        discriminationIndex: 0.05,
      },
    ];
    expect(sortQuestions(rows, "hardest")[0].questionNumber).toBe(2);
    expect(sortQuestions(rows, "easiest")[0].questionNumber).toBe(1);
    expect(sortQuestions(rows, "weakD")[0].questionNumber).toBe(2);
  });

  it("flags hard items with popular wrong choices", () => {
    const sub = subject();
    // 6 students: mix of high/low so D can compute; Q2 often wrong with C
    const scans = [
      scan("01", { "1": "A", "2": "C", "3": "C", "4": "D" }, 3),
      scan("02", { "1": "A", "2": "C", "3": "C", "4": "D" }, 3),
      scan("03", { "1": "A", "2": "C", "3": "C", "4": "D" }, 3),
      scan("04", { "1": "A", "2": "B", "3": "C", "4": "D" }, 4),
      scan("05", { "1": "B", "2": "C", "3": "A", "4": "A" }, 0),
      scan("06", { "1": "B", "2": "C", "3": "A", "4": "A" }, 0),
    ];
    const report = buildItemAnalysisReport(sub, scans);
    expect(report).not.toBeNull();
    expect(overallDifficulty(report!)).toBeGreaterThan(0);
    const flags = questionsNeedingAttention(sub, report!);
    const q2 = flags.find((f) => f.questionNumber === 2);
    expect(q2).toBeTruthy();
    expect(q2!.topWrongChoice).toBe("C");
  });
});
