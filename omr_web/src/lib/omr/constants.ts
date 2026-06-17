/** Port of lib/models/omr_template_specs.dart — keep in sync with mobile scanner */

export const PAGE = {
  width: 595,
  height: 842,
  marginLeft: 28,
  marginTop: 34,
  marginRight: 28,
  marginBottom: 28,
  cornerMarkerSize: 20,
  cornerMarkerOffset: 8,
  timingMarkSize: 6,
  timingMarkSpacing: 80,
  timingMarkStartX: 60,
  timingMarkEndX: 535,
  timingMarkStartY: 60,
  timingMarkEndY: 780,
  qrSize: 72,
  qrX: 495,
  qrY: 34,
  headerHeight: 72,
  omrIdTop: 114,
  omrIdHeight: 136,
  omrIdColumns: 4,
  omrIdRows: 10,
  omrIdBubbleDiameter: 11.5,
  omrIdColumnSpacing: 50,
  omrIdRowSpacing: 12,
  omrIdFirstColumnX: 222.5,
  omrIdFirstRowY: 134,
  answerGridTop: 262,
  answerGridBottom: 800,
  answerGridLeft: 28,
  answerGridRight: 567,
  answerOptionIndicatorHeight: 14,
  answerGridFooterHeight: 30,
  answerBubbleDiameter: 11.5,
  answerOptionsCount: 5,
  answerOptionLabels: ["A", "B", "C", "D", "E"],
  answerColumnInset: 6,
  answerNumberBubbleGap: 6,
  questionNumberWidth: 16,
  calibrationY: 810,
  calibrationFilledX: 80,
  calibrationEmptyX: 110,
  calibrationBubbleSize: 10,
} as const;

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
  return PAGE.answerGridTop + PAGE.answerOptionIndicatorHeight;
}

export function answerRowsBottom(template: OmrTemplate) {
  return answerRowsTop() + template.rows * template.rowHeight;
}

export function questionPosition(template: OmrTemplate, questionNumber: number) {
  const idx = questionNumber - 1;
  return { col: Math.floor(idx / template.rows), row: idx % template.rows };
}

export function bubbleCenterX(template: OmrTemplate, colIndex: number, optionIndex: number) {
  const columnLeft = PAGE.answerGridLeft + colIndex * template.columnWidth;
  const bubbleAreaWidth = template.bubbleSpacingX * (PAGE.answerOptionsCount - 1);
  const usableWidth = template.columnWidth - PAGE.answerColumnInset * 2;
  const rowContentWidth = PAGE.questionNumberWidth + PAGE.answerNumberBubbleGap + bubbleAreaWidth;
  const rowContentLeft = columnLeft + PAGE.answerColumnInset + (usableWidth - rowContentWidth) / 2;
  const bubbleAreaLeft = rowContentLeft + PAGE.questionNumberWidth + PAGE.answerNumberBubbleGap;
  return bubbleAreaLeft + optionIndex * template.bubbleSpacingX;
}

export function rowCenterY(template: OmrTemplate, rowIndex: number) {
  return answerRowsTop() + rowIndex * template.rowHeight + template.rowHeight / 2;
}

export function bubblePosition(template: OmrTemplate, questionNumber: number, optionIndex: number) {
  const { col, row } = questionPosition(template, questionNumber);
  return { x: bubbleCenterX(template, col, optionIndex), y: rowCenterY(template, row) };
}

export function buildQrPayload(subject: {
  local_id: string;
  name: string;
  total_questions: number;
  passing_score: number;
  exam_date: string | null;
}, sectionName: string, sheetId: string) {
  const template = templateForCount(subject.total_questions);
  return JSON.stringify({
    version: 2,
    sheetId,
    subjectId: subject.local_id,
    subjectName: subject.name,
    totalQuestions: subject.total_questions,
    passingScore: subject.passing_score,
    sectionName,
    examDateIso: subject.exam_date,
    layout: {
      template: template.templateId,
      cols: template.columns,
      rows: template.rows,
      gridTop: answerRowsTop(),
      gridBottom: answerRowsBottom(template),
      rowHeight: template.rowHeight,
      colWidth: template.columnWidth,
      bubbleSpacingX: template.bubbleSpacingX,
    },
  });
}
