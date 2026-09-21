import { describe, expect, it } from "vitest";
import {
  ALL_CUSTOM_FORMS,
  examReadyScanErrorForSubject,
  profileBubbleCenterX,
  resolvePrintLayout,
  tilingForGeometry,
  tryComputeExplicitGrid,
} from "@/lib/omr/layout-profile";
import {
  answerGridContentHeight,
  denseFullPortraitGeometry,
  geometryForForm,
  layoutScale,
  parseLayoutForm,
  standardPortraitGeometry,
} from "@/lib/omr/sheet-geometry";
import { OMR_PAGE } from "@/lib/omr/constants";
import type { DbSubject } from "@/lib/types/database";

function subject(overrides: Partial<DbSubject> = {}): DbSubject {
  return {
    id: "s1",
    owner_teacher_id: "t1",
    local_id: "L1",
    name: "Custom Quiz",
    answer_key: {},
    total_questions: 12,
    section_names: ["7-A"],
    section_qr_data: {},
    exam_date: null,
    passing_score: 6,
    use_partial_credit: false,
    use_custom_layout: true,
    options_count: 5,
    layout_shape: "lengthwise_full",
    custom_grid_columns: 3,
    custom_grid_rows: 4,
    sync_status: "synced",
    created_at: "2026-01-01",
    updated_at: "2026-01-01",
    ...overrides,
  };
}

describe("custom sheet scan contract (phone parity)", () => {
  it("exposes A–F option labels like the phone", () => {
    expect([...OMR_PAGE.answerOptionLabels]).toEqual(["A", "B", "C", "D", "E", "F"]);
  });

  it("accepts the same three portrait forms the phone still scans", () => {
    expect(ALL_CUSTOM_FORMS.map((f) => f.id)).toEqual([
      "lengthwise_full",
      "lengthwise_half",
      "lengthwise_quarter",
    ]);
  });

  it("full portrait geometry matches frozen 30–100 page", () => {
    const g = geometryForForm(parseLayoutForm("lengthwise_full"));
    const std = standardPortraitGeometry();
    expect(g).toEqual(std);
    expect(g.pageWidth).toBe(595);
    expect(g.pageHeight).toBe(842);
    expect(g.answerGridTop).toBe(262);
    expect(g.answerGridBottom).toBe(800);
    expect(answerGridContentHeight(g)).toBe(494);
  });

  it("half portrait uses half-height content block (full width → layoutScale 1)", () => {
    const g = geometryForForm(parseLayoutForm("lengthwise_half"));
    expect(g.pageWidth).toBe(595);
    expect(g.pageHeight).toBe(842);
    expect(g.contentBlockWidth).toBe(595);
    expect(g.contentBlockHeight).toBe(421);
    // Phone: layoutScale = contentBlockWidth / pageWidth (full-width half sheets stay 1.0).
    expect(layoutScale(g)).toBeCloseTo(1, 5);
    expect(g.qrCodeSize).toBeGreaterThanOrEqual(56);
    expect(g.answerBubbleDiameter).toBeLessThanOrEqual(11.5);
  });

  it("quarter portrait uses quarter content block", () => {
    const g = geometryForForm(parseLayoutForm("lengthwise_quarter"));
    expect(g.contentBlockWidth).toBeCloseTo(297.5, 5);
    expect(g.contentBlockHeight).toBeCloseTo(421, 5);
    expect(tilingForGeometry(g)?.sheetsPerPage).toBe(4);
  });

  it("half portrait tiles 2-up like the phone", () => {
    const g = geometryForForm(parseLayoutForm("lengthwise_half"));
    const tiling = tilingForGeometry(g);
    expect(tiling).toEqual({ columns: 1, rows: 2, sheetsPerPage: 2 });
  });

  it("dense full portrait shrinks bubbles for high question counts", () => {
    const dense = denseFullPortraitGeometry();
    expect(dense.answerBubbleDiameter).toBe(9.5);
    expect(dense.answerGridFooterHeight).toBe(8);
    expect(dense.answerColumnInset).toBeCloseTo(5.75, 5);
  });

  it("packs a scannable 6-choice custom grid", () => {
    const fit = tryComputeExplicitGrid({
      columns: 4,
      rows: 10,
      optionsCount: 6,
      form: parseLayoutForm("lengthwise_full"),
      itemCount: 40,
    });
    expect(fit.ok).toBe(true);
    expect(fit.profile!.optionsCount).toBe(6);
    const left = profileBubbleCenterX(fit.profile!, 0, 0);
    const right = profileBubbleCenterX(fit.profile!, 0, 5);
    expect(right).toBeGreaterThan(left);
  });

  it("rejects landscape forms the phone refuses to scan", () => {
    const err = examReadyScanErrorForSubject(
      subject({ layout_shape: "crosswise_full" }),
    );
    expect(err).toMatch(/landscape|portrait/i);
  });

  it("rejects missing grid the same way the phone does", () => {
    const err = examReadyScanErrorForSubject(
      subject({ custom_grid_columns: null, custom_grid_rows: null }),
    );
    expect(err).toMatch(/missing its layout grid/i);
  });

  it("resolves full / half / quarter synced keys for web print", () => {
    for (const shape of ["lengthwise_full", "lengthwise_half", "lengthwise_quarter"]) {
      const form = parseLayoutForm(shape);
      // Keep grids modest so half/quarter still pass scan floors.
      const cols = shape === "lengthwise_quarter" ? 2 : 3;
      const rows = shape === "lengthwise_quarter" ? 5 : 4;
      const items = cols * rows;
      const fit = resolvePrintLayout(
        subject({
          layout_shape: shape,
          custom_grid_columns: cols,
          custom_grid_rows: rows,
          total_questions: items,
          options_count: 4,
        }),
      );
      expect(fit.ok, shape).toBe(true);
      expect(fit.profile!.form.id).toBe(form.id);
      expect(fit.profile!.isCustom).toBe(true);
      expect(fit.profile!.grid.columns).toBe(cols);
      expect(fit.profile!.grid.rows).toBe(rows);
    }
  });

  it("keeps bubble centers inside their columns (scan spill guard)", () => {
    const fit = tryComputeExplicitGrid({
      columns: 5,
      rows: 20,
      optionsCount: 5,
      form: parseLayoutForm("lengthwise_full"),
      itemCount: 100,
    });
    expect(fit.ok).toBe(true);
    const p = fit.profile!;
    const g = p.geometry;
    for (let col = 0; col < p.grid.columns; col++) {
      const leftEdge = profileBubbleCenterX(p, col, 0) - g.answerBubbleDiameter / 2;
      const rightEdge =
        profileBubbleCenterX(p, col, p.optionsCount - 1) + g.answerBubbleDiameter / 2;
      const columnLeft = g.answerGridLeft + col * p.grid.columnWidth;
      const columnRight = columnLeft + p.grid.columnWidth;
      expect(leftEdge).toBeGreaterThanOrEqual(columnLeft - 0.05);
      expect(rightEdge).toBeLessThanOrEqual(columnRight + 0.05);
    }
  });
});
