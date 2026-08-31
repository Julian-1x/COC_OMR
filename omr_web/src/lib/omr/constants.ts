/**
 * Mirror of lib/models/omr_template_specs.dart (OmrPageConstants + templates).
 * Web PDF must match lib/pages/answer_sheet_generator.dart — not a separate design.
 * When Dart changes, update this file and run test/answer-sheet-parity.test.ts.
 */

export const OMR_PAGE = {
  pageWidth: 595,
  pageHeight: 842,
  marginLeft: 28,
  marginTop: 34,
  marginRight: 28,
  marginBottom: 28,
  contentWidth: 539,
  cornerMarkerSize: 20,
  cornerMarkerOffset: 8,
  timingMarkSize: 6,
  timingMarkSpacing: 80,
  timingMarkEdgeOffset: 8,
  timingMarkStartX: 60,
  timingMarkEndX: 535,
  timingMarkStartY: 60,
  timingMarkEndY: 780,
  qrCodeSize: 80,
  qrCodeX: 487,
  qrCodeY: 34,
  headerTop: 34,
  headerHeight: 80,
  omrIdTop: 114,
  omrIdHeight: 136,
  omrIdColumns: 4,
  omrIdRows: 10,
  omrIdBubbleDiameter: 11.5,
  omrIdBubbleBorder: 1.2,
  omrIdColumnSpacing: 50,
  omrIdRowSpacing: 12,
  omrIdFirstColumnX: 222.5,
  omrIdFirstRowY: 134,
  answerGridTop: 262,
  answerGridBottom: 800,
  answerGridLeft: 28,
  answerGridRight: 567,
  answerGridWidth: 539,
  answerGridHeight: 538,
  answerOptionIndicatorHeight: 14,
  answerGridFooterHeight: 30,
  answerBubbleDiameter: 11.5,
  answerBubbleBorder: 1.2,
  answerOptionsCount: 5,
  answerOptionLabels: ["A", "B", "C", "D", "E"] as const,
  answerColumnInset: 6,
  answerNumberBubbleGap: 6,
  questionNumberWidth: 16,
  calibrationY: 810,
  calibrationFilledX: 80,
  calibrationEmptyX: 110,
  calibrationBubbleSize: 10,
  rowMarkX: 18,
  rowMarkSize: 4,
  /** Full-page standard portrait block (corners + timing hug this). */
  contentBlockWidth: 595,
  contentBlockHeight: 842,
} as const;

/** @deprecated Use OMR_PAGE — kept for imports during migration. */
export const PAGE = OMR_PAGE;

export type OmrTemplate = {
  templateId: string;
  maxItems: number;
  columns: number;
  rows: number;
  rowHeight: number;
  columnWidth: number;
  bubbleSpacingX: number;
};

export const TEMPLATES: Record<string, OmrTemplate> = {
  "30": { templateId: "30", maxItems: 30, columns: 3, rows: 10, rowHeight: 49.4, columnWidth: 179.6666666667, bubbleSpacingX: 26 },
  "40": { templateId: "40", maxItems: 40, columns: 4, rows: 10, rowHeight: 49.4, columnWidth: 134.75, bubbleSpacingX: 22 },
  "50": { templateId: "50", maxItems: 50, columns: 5, rows: 10, rowHeight: 49.4, columnWidth: 107.8, bubbleSpacingX: 17 },
  "60": { templateId: "60", maxItems: 60, columns: 5, rows: 12, rowHeight: 41.1666666667, columnWidth: 107.8, bubbleSpacingX: 17 },
  "70": { templateId: "70", maxItems: 70, columns: 5, rows: 14, rowHeight: 35.2857142857, columnWidth: 107.8, bubbleSpacingX: 17 },
  "80": { templateId: "80", maxItems: 80, columns: 5, rows: 16, rowHeight: 30.875, columnWidth: 107.8, bubbleSpacingX: 17 },
  "90": { templateId: "90", maxItems: 90, columns: 5, rows: 18, rowHeight: 27.4444444444, columnWidth: 107.8, bubbleSpacingX: 17 },
  "100": { templateId: "100", maxItems: 100, columns: 5, rows: 20, rowHeight: 24.7, columnWidth: 107.8, bubbleSpacingX: 17 },
};

/** Same tiering as OmrItemCount.forQuestionCount in Dart. */
export function templateForCount(questions: number): OmrTemplate {
  if (questions <= 30) return TEMPLATES["30"];
  if (questions <= 40) return TEMPLATES["40"];
  if (questions <= 50) return TEMPLATES["50"];
  if (questions <= 60) return TEMPLATES["60"];
  if (questions <= 70) return TEMPLATES["70"];
  if (questions <= 80) return TEMPLATES["80"];
  if (questions <= 90) return TEMPLATES["90"];
  return TEMPLATES["100"];
}

export function answerRowsTop() {
  return OMR_PAGE.answerGridTop + OMR_PAGE.answerOptionIndicatorHeight;
}

export function answerRowsBottom() {
  return OMR_PAGE.answerGridBottom - OMR_PAGE.answerGridFooterHeight;
}

export function answerGridContentHeight() {
  return answerRowsBottom() - answerRowsTop();
}

export function rowCenterY(template: OmrTemplate, rowIndex: number) {
  return answerRowsTop() + rowIndex * template.rowHeight + template.rowHeight / 2;
}

export function questionPosition(template: OmrTemplate, questionNumber: number) {
  const idx = questionNumber - 1;
  return { col: Math.floor(idx / template.rows), row: idx % template.rows };
}

export function bubbleCenterX(template: OmrTemplate, colIndex: number, optionIndex: number) {
  const columnLeft = OMR_PAGE.answerGridLeft + colIndex * template.columnWidth;
  const bubbleAreaWidth = template.bubbleSpacingX * (OMR_PAGE.answerOptionsCount - 1);
  const usableWidth = template.columnWidth - OMR_PAGE.answerColumnInset * 2;
  const rowContentWidth =
    OMR_PAGE.questionNumberWidth + OMR_PAGE.answerNumberBubbleGap + bubbleAreaWidth;
  const rowContentLeft =
    columnLeft + OMR_PAGE.answerColumnInset + (usableWidth - rowContentWidth) / 2;
  const bubbleAreaLeft = rowContentLeft + OMR_PAGE.questionNumberWidth + OMR_PAGE.answerNumberBubbleGap;
  return bubbleAreaLeft + optionIndex * template.bubbleSpacingX;
}

/** Column-local bubble layout (inside one answer column). */
export function columnBubbleLayout(template: OmrTemplate) {
  const opts = OMR_PAGE.answerOptionsCount;
  const bubbleAreaWidth = template.bubbleSpacingX * (opts - 1);
  const usableWidth = template.columnWidth - OMR_PAGE.answerColumnInset * 2;
  const rowContentWidth =
    OMR_PAGE.questionNumberWidth + OMR_PAGE.answerNumberBubbleGap + bubbleAreaWidth;
  const rowContentLeft = OMR_PAGE.answerColumnInset + (usableWidth - rowContentWidth) / 2;
  const bubbleAreaLeft = rowContentLeft + OMR_PAGE.questionNumberWidth + OMR_PAGE.answerNumberBubbleGap;
  return { rowContentLeft, bubbleAreaLeft, bubbleAreaWidth };
}

export function buildQrPayload(
  subject: {
    local_id: string;
    id?: string;
    name: string;
    total_questions: number;
    owner_teacher_id?: string;
    owner_teacher_email?: string | null;
  },
  sectionName: string,
  sheetId: string,
) {
  return JSON.stringify({
    a: "coc-omr",
    v: 2,
    id: sheetId,
    si: subject.local_id,
    sn: subject.name,
    q: subject.total_questions,
    sc: sectionName,
    ...(subject.owner_teacher_id ? { ot: subject.owner_teacher_id } : {}),
    ...(subject.owner_teacher_email ? { oe: subject.owner_teacher_email } : {}),
    ...(subject.id ? { ci: subject.id } : {}),
  });
}
