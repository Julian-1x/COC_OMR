/**
 * Standard portrait OMR PDF — pixel-aligned with lib/pages/answer_sheet_generator.dart.
 * Do not invent layout here; mirror the phone generator so the scanner reads web prints.
 */
import { PDFDocument, rgb, StandardFonts, type PDFPage, type PDFFont } from "pdf-lib";
import QRCode from "qrcode";
import type { DbSubject } from "@/lib/types/database";
import {
  OMR_PAGE,
  templateForCount,
  buildQrPayload,
  answerRowsBottom,
  rowCenterY,
  columnBubbleLayout,
  type OmrTemplate,
} from "@/lib/omr/constants";
import { generateSheetId } from "@/lib/import/roster";
import { pdfSafeText } from "@/lib/pdf/pdf-text";

const PANEL_BORDER = rgb(0.75, 0.75, 0.75);
const PANEL_BORDER_WIDTH = 0.55;
const MUTED_INK = rgb(0.4, 0.4, 0.4);
const BODY_INK = rgb(0.1, 0.1, 0.1);

type Page = PDFPage;

function pdfYFromTop(top: number, height: number) {
  return OMR_PAGE.pageHeight - top - height;
}

function drawFilledRect(page: Page, left: number, top: number, width: number, height: number, color = rgb(0, 0, 0)) {
  page.drawRectangle({ x: left, y: pdfYFromTop(top, height), width, height, color });
}

function drawOutlineRect(
  page: Page,
  left: number,
  top: number,
  width: number,
  height: number,
  borderWidth = PANEL_BORDER_WIDTH,
  borderColor = PANEL_BORDER,
) {
  page.drawRectangle({
    x: left,
    y: pdfYFromTop(top, height),
    width,
    height,
    borderColor,
    borderWidth,
  });
}

function drawTextTopDown(
  page: Page,
  text: string,
  left: number,
  baselineFromTop: number,
  size: number,
  font: PDFFont,
  color = BODY_INK,
  bold = false,
) {
  page.drawText(pdfSafeText(text), {
    x: left,
    y: OMR_PAGE.pageHeight - baselineFromTop,
    size,
    font,
    color,
  });
}

function fitHeaderText(value: string, maxChars: number): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length <= maxChars) return normalized;
  return `${normalized.slice(0, maxChars - 3)}...`;
}

function formatExamDate(examDate: string | null): string {
  if (!examDate) return "";
  const d = examDate.slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(d) ? `   DATE: ${d}` : "";
}

/** _cornerBox */
function drawCornerBox(page: Page, left: number, top: number, size: number) {
  drawFilledRect(page, left, top, size, size);
  const inset = size * 0.25;
  drawFilledRect(page, left + inset, top + inset, size * 0.5, size * 0.5, rgb(1, 1, 1));
}

/** _cornerMarkers + _buildTimingMarks for standard full page. */
function drawRegistrationMarks(page: Page, template: OmrTemplate) {
  const g = OMR_PAGE;
  const usedLeft = 0;
  const usedTop = 0;
  const usedRight = g.contentBlockWidth;
  const usedBottom = g.contentBlockHeight;

  drawCornerBox(page, usedLeft + g.cornerMarkerOffset, usedTop + g.cornerMarkerOffset, g.cornerMarkerSize);
  drawCornerBox(
    page,
    usedRight - g.cornerMarkerOffset - g.cornerMarkerSize,
    usedTop + g.cornerMarkerOffset,
    g.cornerMarkerSize,
  );
  drawCornerBox(
    page,
    usedLeft + g.cornerMarkerOffset,
    usedBottom - g.cornerMarkerOffset - g.cornerMarkerSize,
    g.cornerMarkerSize,
  );
  drawCornerBox(
    page,
    usedRight - g.cornerMarkerOffset - g.cornerMarkerSize,
    usedBottom - g.cornerMarkerOffset - g.cornerMarkerSize,
    g.cornerMarkerSize,
  );

  for (let x = g.timingMarkStartX; x < g.timingMarkEndX; x += g.timingMarkSpacing) {
    drawFilledRect(page, x, usedTop + g.timingMarkEdgeOffset, g.timingMarkSize, g.timingMarkSize);
    drawFilledRect(
      page,
      x,
      usedBottom - g.timingMarkEdgeOffset - g.timingMarkSize,
      g.timingMarkSize,
      g.timingMarkSize,
    );
  }
  for (let y = g.timingMarkStartY; y < g.timingMarkEndY; y += g.timingMarkSpacing) {
    drawFilledRect(page, usedLeft + g.timingMarkEdgeOffset, y, g.timingMarkSize, g.timingMarkSize);
    drawFilledRect(
      page,
      usedRight - g.timingMarkEdgeOffset - g.timingMarkSize,
      y,
      g.timingMarkSize,
      g.timingMarkSize,
    );
  }

  for (let row = 0; row < template.rows; row++) {
    const cy = rowCenterY(template, row);
    drawFilledRect(page, g.rowMarkX, cy - g.rowMarkSize / 2, g.rowMarkSize, g.rowMarkSize);
  }
}

/** _bubble */
function drawBubble(page: Page, centerX: number, centerY: number, diameter: number, filled = false) {
  const r = diameter / 2;
  const pdfY = OMR_PAGE.pageHeight - centerY;
  if (filled) {
    page.drawCircle({ x: centerX, y: pdfY, size: r, color: rgb(0, 0, 0), borderColor: rgb(0, 0, 0), borderWidth: OMR_PAGE.answerBubbleBorder });
  } else {
    page.drawCircle({ x: centerX, y: pdfY, size: r, borderColor: rgb(0, 0, 0), borderWidth: OMR_PAGE.answerBubbleBorder });
  }
}

/** _headerSection blank sheet — matches _buildHeader layout. */
function drawHeader(
  page: Page,
  subject: DbSubject,
  sectionName: string,
  qrPng: Awaited<ReturnType<PDFDocument["embedPng"]>>,
  font: PDFFont,
  fontBold: PDFFont,
) {
  const g = OMR_PAGE;
  const sectionLabel = sectionName.trim() || "ALL";
  const subtitleLine1 = fitHeaderText(
    `SECTION: ${sectionLabel}${formatExamDate(subject.exam_date)}   ITEMS: ${subject.total_questions}`,
    42,
  );
  const subtitleLine2 = "NAME: _______________________________";
  const instructionLine =
    "Write your name. Shade your OMR ID. One bubble per question. Dark pencil (HB/2B).";

  const textLeft = g.marginLeft;
  let baseline = g.headerTop + 18;
  drawTextTopDown(page, fitHeaderText(subject.name, 28), textLeft, baseline, 18, fontBold);
  baseline += 4 + 8.2;
  drawTextTopDown(page, subtitleLine1, textLeft, baseline, 8.2, font);
  baseline += 2 + 8.2;
  drawTextTopDown(page, subtitleLine2, textLeft, baseline, 8.2, font);
  baseline += 2 + 8.2;
  drawTextTopDown(page, instructionLine, textLeft, baseline, 7.2, font, MUTED_INK);

  const qrPadding = 3;
  const qrInner = g.qrCodeSize - qrPadding * 2;
  drawOutlineRect(page, g.qrCodeX, g.qrCodeY, g.qrCodeSize, g.qrCodeSize, 0.6, PANEL_BORDER);
  page.drawImage(qrPng, {
    x: g.qrCodeX + qrPadding,
    y: pdfYFromTop(g.qrCodeY + qrPadding, qrInner),
    width: qrInner,
    height: qrInner,
  });
}

/** _idSectionBase blank */
function drawOmrIdSection(page: Page, fontBold: PDFFont, font: PDFFont) {
  const g = OMR_PAGE;
  drawOutlineRect(page, g.marginLeft, g.omrIdTop, g.answerGridWidth, g.omrIdHeight);

  const relativeFirstColumnX = g.omrIdFirstColumnX - g.marginLeft;
  const relativeFirstRowY = g.omrIdFirstRowY - g.omrIdTop;
  const titleTop = 3;
  const digitLabelWidth = 8;
  const digitLabelOffset = 21;

  const title = "OMR ID (4 DIGITS)";
  const titleWidth = fontBold.widthOfTextAtSize(title, 9);
  drawTextTopDown(
    page,
    title,
    g.marginLeft + (g.answerGridWidth - titleWidth) / 2,
    g.omrIdTop + titleTop + 9,
    9,
    fontBold,
  );

  for (let col = 0; col < g.omrIdColumns; col++) {
    const columnCenterX = g.marginLeft + relativeFirstColumnX + col * g.omrIdColumnSpacing;
    for (let digit = 0; digit < g.omrIdRows; digit++) {
      const bubbleCenterY = g.omrIdTop + relativeFirstRowY + digit * g.omrIdRowSpacing;
      const labelRight = columnCenterX - digitLabelOffset + digitLabelWidth;
      const label = String(digit);
      const labelWidth = font.widthOfTextAtSize(label, 5.8);
      drawTextTopDown(page, label, labelRight - labelWidth, bubbleCenterY + 2, 5.8, font);
      drawBubble(page, columnCenterX, bubbleCenterY, g.omrIdBubbleDiameter, false);
    }
  }
}

/** _answerOptionIndicatorRow */
function drawOptionIndicatorRow(
  page: Page,
  template: OmrTemplate,
  colIndex: number,
  fontBold: PDFFont,
) {
  const g = OMR_PAGE;
  const { bubbleAreaLeft } = columnBubbleLayout(template);
  const columnLeft = g.answerGridLeft + colIndex * template.columnWidth;

  for (let opt = 0; opt < g.answerOptionsCount; opt++) {
    const bubbleCenterX = bubbleAreaLeft + opt * template.bubbleSpacingX;
    const label = g.answerOptionLabels[opt];
    const labelWidth = fontBold.widthOfTextAtSize(label, 6.5);
    drawTextTopDown(
      page,
      label,
      columnLeft + bubbleCenterX - labelWidth / 2,
      g.answerGridTop + 1 + 6.5,
      6.5,
      fontBold,
    );
  }
}

/** _questionColumnAbsolute */
function drawQuestionColumn(
  page: Page,
  template: OmrTemplate,
  colIndex: number,
  startQuestion: number,
  endQuestion: number,
  font: PDFFont,
) {
  const g = OMR_PAGE;
  const { rowContentLeft, bubbleAreaLeft } = columnBubbleLayout(template);
  const columnLeft = g.answerGridLeft + colIndex * template.columnWidth;
  const questionCount = endQuestion - startQuestion + 1;

  for (let rowIndex = 0; rowIndex < template.rows; rowIndex++) {
    if (rowIndex >= questionCount) break;
    const questionNumber = startQuestion + rowIndex;
    const rowTop = g.answerGridTop + g.answerOptionIndicatorHeight + rowIndex * template.rowHeight;
    const rowMid = rowTop + template.rowHeight / 2;

    drawTextTopDown(
      page,
      `${questionNumber}.`,
      columnLeft + rowContentLeft,
      rowMid + 4,
      7,
      font,
    );

    for (let opt = 0; opt < g.answerOptionsCount; opt++) {
      const cx = columnLeft + bubbleAreaLeft + opt * template.bubbleSpacingX;
      drawBubble(page, cx, rowMid, g.answerBubbleDiameter, false);
    }
  }
}

/** _answersSectionAbsolute */
function drawAnswerGrid(page: Page, subject: DbSubject, template: OmrTemplate, font: PDFFont, fontBold: PDFFont) {
  const g = OMR_PAGE;
  drawOutlineRect(page, g.answerGridLeft, g.answerGridTop, g.answerGridWidth, g.answerGridHeight);

  for (let col = 0; col < template.columns; col++) {
    const startQ = col * template.rows + 1;
    const endQ = Math.min(startQ + template.rows - 1, subject.total_questions);
    if (startQ > subject.total_questions) continue;

    drawOptionIndicatorRow(page, template, col, fontBold);
    drawQuestionColumn(page, template, col, startQ, endQ, font);
  }
}

/** _footerNotes */
function drawFooter(page: Page, font: PDFFont) {
  drawTextTopDown(
    page,
    "Lay flat, good lighting, dark pencil. Edge marks are for scanning — do not mark them.",
    OMR_PAGE.marginLeft + 2,
    answerRowsBottom() + 4 + 5.8,
    5.8,
    font,
    MUTED_INK,
  );
}

/** _buildCalibrationMarks */
function drawCalibrationMarks(page: Page) {
  const g = OMR_PAGE;
  const diameter = g.answerBubbleDiameter;
  const bubbleTop = g.calibrationY - diameter / 2;
  const cy = bubbleTop + diameter / 2;
  drawBubble(page, g.calibrationFilledX, cy, diameter, true);
  drawBubble(page, g.calibrationEmptyX, cy, diameter, false);
}

async function drawSheetPage(pdf: PDFDocument, subject: DbSubject, sectionName: string) {
  if (subject.total_questions < 30 || subject.total_questions > 100) {
    throw new Error(
      "Web print supports standard 30–100 question sheets only. " +
        "Use the phone app to print custom or non-standard layouts so scanning stays accurate.",
    );
  }

  const page = pdf.addPage([OMR_PAGE.pageWidth, OMR_PAGE.pageHeight]);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const template = templateForCount(subject.total_questions);
  const sheetId = generateSheetId();
  const qrText = buildQrPayload(subject, sectionName.trim() || "ALL", sheetId);
  const qrDataUrl = await QRCode.toDataURL(qrText, {
    margin: 0,
    width: 512,
    errorCorrectionLevel: "L",
  });
  const qrPng = await pdf.embedPng(qrDataUrl);

  drawRegistrationMarks(page, template);
  drawHeader(page, subject, sectionName, qrPng, font, fontBold);
  drawOmrIdSection(page, fontBold, font);
  drawAnswerGrid(page, subject, template, font, fontBold);
  drawFooter(page, font);
  drawCalibrationMarks(page);
}

export async function generateAnswerSheetsPdf(
  subject: DbSubject,
  sectionName: string,
  copies: number,
): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  const count = Math.max(1, Math.min(copies, 200));
  for (let i = 0; i < count; i++) {
    await drawSheetPage(pdf, subject, sectionName);
  }
  return pdf.save();
}

export async function generateAnswerSheetPdf(
  subject: DbSubject,
  sectionName: string,
  copyCount: number,
): Promise<Uint8Array> {
  return generateAnswerSheetsPdf(subject, sectionName, copyCount);
}

export async function generateBlankSheetsPdf(
  subject: DbSubject,
  sectionName: string,
  copies: number,
): Promise<Uint8Array> {
  return generateAnswerSheetsPdf(subject, sectionName, copies);
}
