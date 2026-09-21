import { describe, expect, it } from "vitest";
import {
  canPrintOnWeb,
  resolvePrintLayout,
  tryComputeExplicitGrid,
} from "@/lib/omr/layout-profile";
import { parseLayoutForm, standardPortraitGeometry } from "@/lib/omr/sheet-geometry";
import type { DbSubject } from "@/lib/types/database";

function baseSubject(overrides: Partial<DbSubject> = {}): DbSubject {
  return {
    id: "sub-1",
    owner_teacher_id: "t1",
    local_id: "local-1",
    name: "Quiz",
    answer_key: {},
    total_questions: 50,
    section_names: ["7-A"],
    section_qr_data: {},
    exam_date: null,
    passing_score: 25,
    use_partial_credit: false,
    sync_status: "synced",
    created_at: "2026-01-01",
    updated_at: "2026-01-01",
    ...overrides,
  };
}

describe("custom layout profile (phone parity)", () => {
  it("accepts explicit 2×3 full lengthwise grid", () => {
    const fit = tryComputeExplicitGrid({
      columns: 2,
      rows: 3,
      optionsCount: 5,
      form: parseLayoutForm("lengthwise_full"),
    });
    expect(fit.ok).toBe(true);
    expect(fit.profile!.grid.columns).toBe(2);
    expect(fit.profile!.grid.rows).toBe(3);
    expect(fit.profile!.itemCount).toBe(6);
    expect(fit.profile!.geometry.pageWidth).toBe(standardPortraitGeometry().pageWidth);
  });

  it("rejects overcrowded quarter sheet", () => {
    const fit = tryComputeExplicitGrid({
      columns: 5,
      rows: 10,
      optionsCount: 5,
      form: parseLayoutForm("lengthwise_quarter"),
    });
    expect(fit.ok).toBe(false);
  });

  it("prints synced custom subject on web", () => {
    const subject = baseSubject({
      total_questions: 12,
      use_custom_layout: true,
      options_count: 4,
      layout_shape: "lengthwise_full",
      custom_grid_columns: 3,
      custom_grid_rows: 4,
    });
    expect(canPrintOnWeb(subject)).toBe(true);
    const fit = resolvePrintLayout(subject);
    expect(fit.ok).toBe(true);
    expect(fit.profile!.isCustom).toBe(true);
    expect(fit.profile!.optionsCount).toBe(4);
    expect(fit.profile!.grid.columns).toBe(3);
    expect(fit.profile!.grid.rows).toBe(4);
  });

  it("blocks custom subject missing grid after sync gap", () => {
    const subject = baseSubject({
      total_questions: 12,
      use_custom_layout: true,
      custom_grid_columns: null,
      custom_grid_rows: null,
    });
    expect(canPrintOnWeb(subject)).toBe(false);
  });

  it("still prints standard 30–100 without custom flag", () => {
    expect(canPrintOnWeb(baseSubject({ total_questions: 50 }))).toBe(true);
    expect(canPrintOnWeb(baseSubject({ total_questions: 25 }))).toBe(false);
  });
});
