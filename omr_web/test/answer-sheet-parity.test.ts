import { describe, expect, it } from "vitest";
import {
  OMR_PAGE,
  TEMPLATES,
  answerGridContentHeight,
  answerRowsBottom,
  answerRowsTop,
  bubbleCenterX,
  rowCenterY,
  templateForCount,
} from "@/lib/omr/constants";

/**
 * Expected values from lib/models/omr_template_specs.dart (OmrPageConstants).
 * If Flutter changes, update OMR_PAGE and this test together.
 */
describe("web OMR constants match phone scan contract", () => {
  it("page and registration marks match OmrPageConstants", () => {
    expect(OMR_PAGE.pageWidth).toBe(595);
    expect(OMR_PAGE.pageHeight).toBe(842);
    expect(OMR_PAGE.qrCodeSize).toBe(80);
    expect(OMR_PAGE.qrCodeX).toBe(487);
    expect(OMR_PAGE.headerHeight).toBe(80);
    expect(OMR_PAGE.omrIdTop).toBe(114);
    expect(OMR_PAGE.answerGridTop).toBe(262);
    expect(OMR_PAGE.answerGridBottom).toBe(800);
    expect(OMR_PAGE.rowMarkX).toBe(18);
    expect(answerRowsTop()).toBe(276);
    expect(answerRowsBottom()).toBe(770);
    expect(answerGridContentHeight()).toBe(494);
  });

  it("templates match OmrTemplateSpec production values", () => {
    expect(TEMPLATES["30"].rowHeight).toBe(49.4);
    expect(TEMPLATES["30"].columns).toBe(3);
    expect(TEMPLATES["100"].rows).toBe(20);
    expect(templateForCount(25).templateId).toBe("30");
    expect(templateForCount(45).templateId).toBe("50");
    expect(templateForCount(100).templateId).toBe("100");
  });

  it("row and bubble positions match template math", () => {
    const t = TEMPLATES["50"];
    expect(rowCenterY(t, 0)).toBeCloseTo(276 + t.rowHeight / 2, 5);
    expect(bubbleCenterX(t, 0, 0)).toBeGreaterThan(OMR_PAGE.answerGridLeft);
  });
});
