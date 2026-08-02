import { PDFDocument, rgb, StandardFonts, type PDFPage, type PDFFont } from "pdf-lib";
import QRCode from "qrcode";
import type { DbSubject } from "@/lib/types/database";
import {
  PAGE,
  templateForCount,
  questionPosition,
  buildQrPayload,
  type OmrTemplate,
} from "@/lib/omr/constants";
import { generateSheetId } from "@/lib/import/roster";
import { pdfSafeText } from "@/lib/pdf/pdf-text";

/** Matches answer_sheet_generator.dart panel styling. */
const PANEL_BORDER = rgb(0.75, 0.75, 0.75);
const PANEL_BORDER_WIDTH = 0.55;
const MUTED_INK = rgb(0.4, 0.4, 0.4);
const BODY_INK = rgb(0.1, 0.1, 0.1);

type Page = PDFPage;

/** Top-down page coords (origin top-left) → pdf-lib bottom-left origin (top edge of rect). */
function rectPdfY(top: number, height: number) {
  return PAGE.height - top - height;
}

function drawFilledRectTopDown(page: Page, left: number, top: number, width: number, height: number, color = rgb(0, 0, 0)) {
  page.drawRectangle({ x: left, y: rectPdfY(top, height), width, height, color });
}

function drawOutlineRectTopDown(
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
    y: rectPdfY(top, height),
    width,
    height,
    borderColor,
    borderWidth,
  });
}

/** Black square with white center — matches _cornerBox in answer_sheet_generator.dart. */
function drawCornerBox(page: Page, left: number, top: number, size: number) {
  drawFilledRectTopDown(page, left, top, size, size);
  const inset = size * 0.25;
  drawFilledRectTopDown(page, left + inset, top + inset, size * 0.5, size * 0.5, rgb(1, 1, 1));
}

function drawCornerMarkers(page: Page) {
  const s = PAGE.cornerMarkerSize;
  const o = PAGE.cornerMarkerOffset;
  drawCornerBox(page, o, o, s);
  drawCornerBox(page, PAGE.width - o - s, o, s);
  drawCornerBox(page, o, PAGE.height - o - s, s);
  drawCornerBox(page, PAGE.width - o - s, PAGE.height - o - s, s);
}

/** Timing marks — same positions as Flutter _buildTimingMarks. */
function drawTimingMarks(page: Page) {
  const sz = PAGE.timingMarkSize;
  const edge = PAGE.timingMarkEdgeOffset;

  for (let x = PAGE.timingMarkStartX; x < PAGE.timingMarkEndX; x += PAGE.timingMarkSpacing) {
    drawFilledRectTopDown(page, x, edge, sz, sz);
    drawFilledRectTopDown(page, x, PAGE.height - edge - sz, sz, sz);
  }
  for (let y = PAGE.timingMarkStartY; y < PAGE.timingMarkEndY; y += PAGE.timingMarkSpacing) {
    drawFilledRectTopDown(page, edge, y, sz, sz);
    drawFilledRectTopDown(page, PAGE.width - edge - sz, y, sz, sz);
  }
}

function drawRowMarks(page: Page, template: OmrTemplate) {
  const sz = 4;
  const markX = PAGE.marginLeft - 10;
  for (let row = 0; row < template.rows; row++) {
    const cy = answerRowCenterY(template, row);
    drawFilledRectTopDown(page, markX, cy - sz / 2, sz, sz);
  }
}

function answerRowsTop() {
  return PAGE.answerGridTop + PAGE.answerOptionIndicatorHeight;
}

function answerRowCenterY(template: OmrTemplate, rowIndex: number) {
  return answerRowsTop() + rowIndex * template.rowHeight + template.rowHeight / 2;
}

function bubbleAreaLayout(template: OmrTemplate, columnWidth: number) {
  const bubbleAreaWidth = template.bubbleSpacingX * (PAGE.answerOptionsCount - 1);
  const usableWidth = columnWidth - PAGE.answerColumnInset * 2;
  const rowContentWidth = PAGE.questionNumberWidth + PAGE.answerNumberBubbleGap + bubbleAreaWidth;
  const rowContentLeft = PAGE.answerColumnInset + (usableWidth - rowContentWidth) / 2;
  const bubbleAreaLeft = rowContentLeft + PAGE.questionNumberWidth + PAGE.answerNumberBubbleGap;
  return { bubbleAreaWidth, rowContentLeft, bubbleAreaLeft };
}

function drawBubbleTopLeft(page: Page, left: number, top: number, diameter: number, fill = false) {
  const r = diameter / 2;
  const cx = left + r;
  const cyTopDown = top + r;
  const pdfY = PAGE.height - cyTopDown;
  if (fill) {
    page.drawCircle({ x: cx, y: pdfY, size: r, color: rgb(0, 0, 0) });
  } else {
    page.drawCircle({ x: cx, y: pdfY, size: r, borderColor: rgb(0, 0, 0), borderWidth: 1.2 });
  }
}

function drawTextBaselineFromTop(
  page: Page,
  text: string,
  x: number,
  baselineFromTop: number,
  size: number,
  font: PDFFont,
  color = BODY_INK,
) {
  page.drawText(pdfSafeText(text), {
    x,
    y: PAGE.height - baselineFromTop,
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
  return d.match(/^\d{4}-\d{2}-\d{2}$/) ? `   DATE: ${d}` : "";
}

function drawHeader(
  page: Page,
  subject: DbSubject,
  sectionName: string,
  qrImage: Awaited<ReturnType<PDFDocument["embedPng"]>>,
  font: PDFFont,
  fontBold: PDFFont,
) {
  const sectionLabel = sectionName.trim() || "ALL";
  const subjectCode = subject.local_id ?? "SUB-????";
  const line1 = fitHeaderText(
    `SUBJECT CODE: ${subjectCode}   VERSION: 2   ITEMS: ${subject.total_questions}`,
    42,
  );
  const line2 = fitHeaderText(`SECTION: ${sectionLabel}${formatExamDate(subject.exam_date)}`, 42);

  let y = PAGE.headerTop + 14;
  drawTextBaselineFromTop(page, subject.name, PAGE.marginLeft, y, 18, fontBold);
  y += 22;
  drawTextBaselineFromTop(page, line1, PAGE.marginLeft, y, 8.2, font);
  y += 10;
  drawTextBaselineFromTop(page, line2, PAGE.marginLeft, y, 8.2, font);
  y += 10;
  drawTextBaselineFromTop(
    page,
    "Fill one bubble per question. Use a dark pencil (HB or 2B).",
    PAGE.marginLeft,
    y,
    7.2,
    font,
    MUTED_INK,
  );

  const qrBoxLeft = PAGE.marginLeft + PAGE.contentWidth - 72;
  drawOutlineRectTopDown(page, qrBoxLeft, PAGE.headerTop, 72, 72, 0.6, PANEL_BORDER);
  page.drawImage(qrImage, {
    x: qrBoxLeft + 4,
    y: rectPdfY(PAGE.headerTop + 4, 64),
    width: 64,
    height: 64,
  });
}

/** Bordered OMR ID panel — matches _idSectionBase (blank, no column headers). */
function drawOmrIdSection(page: Page, fontBold: PDFFont, font: PDFFont) {
  drawOutlineRectTopDown(page, PAGE.marginLeft, PAGE.omrIdTop, PAGE.contentWidth, PAGE.omrIdHeight);

  const title = "OMR ID (4 DIGITS)";
  const titleWidth = fontBold.widthOfTextAtSize(title, 9);
  drawTextBaselineFromTop(
    page,
    title,
    PAGE.marginLeft + (PAGE.contentWidth - titleWidth) / 2,
    PAGE.omrIdTop + 12,
    9,
    fontBold,
  );

  const digitLabelOffset = 21;
  const digitLabelWidth = 8;

  for (let col = 0; col < PAGE.omrIdColumns; col++) {
    const columnCenterX = PAGE.omrIdFirstColumnX + col * PAGE.omrIdColumnSpacing;

    for (let digit = 0; digit < PAGE.omrIdRows; digit++) {
      const bubbleCenterY = PAGE.omrIdFirstRowY + digit * PAGE.omrIdRowSpacing;
      const labelRight = columnCenterX - digitLabelOffset + digitLabelWidth;
      const label = String(digit);
      const labelWidth = font.widthOfTextAtSize(label, 5.8);
      drawTextBaselineFromTop(page, label, labelRight - labelWidth, bubbleCenterY + 2, 5.8, font);

      const bubbleLeft = columnCenterX - PAGE.omrIdBubbleDiameter / 2;
      const bubbleTop = bubbleCenterY - PAGE.omrIdBubbleDiameter / 2;
      drawBubbleTopLeft(page, bubbleLeft, bubbleTop, PAGE.omrIdBubbleDiameter, false);
    }
  }
}

/** Bordered answer grid — matches _answersSectionAbsolute. */
function drawAnswerGrid(page: Page, subject: DbSubject, template: OmrTemplate, font: PDFFont, fontBold: PDFFont) {
  drawOutlineRectTopDown(page, PAGE.answerGridLeft, PAGE.answerGridTop, PAGE.answerGridWidth, PAGE.answerGridHeight);

  for (let col = 0; col < template.columns; col++) {
    const columnLeft = PAGE.answerGridLeft + col * template.columnWidth;
    const { rowContentLeft, bubbleAreaLeft } = bubbleAreaLayout(template, template.columnWidth);

    for (let opt = 0; opt < PAGE.answerOptionsCount; opt++) {
      const bubbleCenterX = bubbleAreaLeft + opt * template.bubbleSpacingX;
      const label = PAGE.answerOptionLabels[opt];
      const labelWidth = fontBold.widthOfTextAtSize(label, 6.5);
      drawTextBaselineFromTop(
        page,
        label,
        columnLeft + bubbleCenterX - labelWidth / 2,
        PAGE.answerGridTop + 8,
        6.5,
        fontBold,
      );
    }

    const startQ = col * template.rows + 1;
    const endQ = Math.min(startQ + template.rows - 1, subject.total_questions);
    if (startQ > subject.total_questions) continue;

    for (let row = 0; row < template.rows; row++) {
      const questionNumber = startQ + row;
      if (questionNumber > endQ) break;

      const rowTop = answerRowsTop() + row * template.rowHeight;
      const rowMid = rowTop + template.rowHeight / 2;

      drawTextBaselineFromTop(
        page,
        `${questionNumber}.`,
        columnLeft + rowContentLeft,
        rowMid + 3,
        7,
        font,
      );

      for (let opt = 0; opt < PAGE.answerOptionsCount; opt++) {
        const bubbleLeft =
          columnLeft + bubbleAreaLeft + opt * template.bubbleSpacingX - PAGE.answerBubbleDiameter / 2;
        const bubbleTop = rowMid - PAGE.answerBubbleDiameter / 2;
        drawBubbleTopLeft(page, bubbleLeft, bubbleTop, PAGE.answerBubbleDiameter, false);
      }
    }
  }
}

function drawFooter(page: Page, font: PDFFont) {
  drawTextBaselineFromTop(
    page,
    "Lay flat, good lighting, dark pencil. Edge marks are for scanning — do not mark them.",
    PAGE.marginLeft + 2,
    PAGE.answerRowsBottom + 8,
    5.8,
    font,
    MUTED_INK,
  );
}

function drawCalibrationMarks(page: Page) {
  const bubbleTop = PAGE.calibrationY - PAGE.answerBubbleDiameter / 2;
  drawBubbleTopLeft(
    page,
    PAGE.calibrationFilledX - PAGE.answerBubbleDiameter / 2,
    bubbleTop,
    PAGE.answerBubbleDiameter,
    true,
  );
  drawBubbleTopLeft(
    page,
    PAGE.calibrationEmptyX - PAGE.answerBubbleDiameter / 2,
    bubbleTop,
    PAGE.answerBubbleDiameter,
    false,
  );
}

async function drawSheetPage(pdf: PDFDocument, subject: DbSubject, sectionName: string) {
  const page = pdf.addPage([PAGE.width, PAGE.height]);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const template = templateForCount(subject.total_questions);
  const sheetId = generateSheetId();
  const qrText = buildQrPayload(subject, sectionName, sheetId);
  const qrDataUrl = await QRCode.toDataURL(qrText, { margin: 0, width: 256 });
  const qrImage = await pdf.embedPng(qrDataUrl);

  drawCornerMarkers(page);
  drawTimingMarks(page);
  drawRowMarks(page, template);
  drawHeader(page, subject, sectionName, qrImage, font, fontBold);
  drawOmrIdSection(page, fontBold, font);
  drawAnswerGrid(page, subject, template, font, fontBold);
  drawFooter(page, font);
  drawCalibrationMarks(page);
}

/** Identical blank sheets (no names, no pre-filled OMR ID). Layout matches the phone app PDF. */
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

/** @deprecated Use generateAnswerSheetsPdf */
export async function generateAnswerSheetPdf(
  subject: DbSubject,
  sectionName: string,
  copyCount: number,
): Promise<Uint8Array> {
  return generateAnswerSheetsPdf(subject, sectionName, copyCount);
}

/** @deprecated Use generateAnswerSheetsPdf */
export async function generateBlankSheetsPdf(
  subject: DbSubject,
  sectionName: string,
  copies: number,
): Promise<Uint8Array> {
  return generateAnswerSheetsPdf(subject, sectionName, copies);
}
