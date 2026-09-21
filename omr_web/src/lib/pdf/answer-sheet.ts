/**
 * OMR PDF — scan-contract aligned with lib/pages/answer_sheet_generator.dart.
 *
 * Custom sheets use the same geometry the phone locks into ScannerSessionLayout.
 * Half/quarter forms tile multi-up like the phone so cut sheets stay full-size
 * and corner/bubble positions match native OpenCV warps.
 */
import { PDFDocument, rgb, StandardFonts, type PDFPage, type PDFFont } from "pdf-lib";
import QRCode from "qrcode";
import type { DbSubject } from "@/lib/types/database";
import { OMR_PAGE, buildQrPayload } from "@/lib/omr/constants";
import { answerKeyScopeOf } from "@/lib/omr/answer-key-scope";
import {
  answerGridHeight,
  answerGridWidth,
  answerRowsBottom,
  layoutScale,
  type OmrSheetGeometry,
} from "@/lib/omr/sheet-geometry";
import {
  optionLabels,
  profileColumnBubbleLayout,
  profileRowCenterY,
  resolvePrintLayout,
  tileOffset,
  tilingForGeometry,
  type OmrLayoutProfile,
} from "@/lib/omr/layout-profile";
import { generateSheetId } from "@/lib/import/roster";
import { pdfSafeText } from "@/lib/pdf/pdf-text";

const PANEL_BORDER = rgb(0.75, 0.75, 0.75);
const PANEL_BORDER_WIDTH = 0.55;
const MUTED_INK = rgb(0.4, 0.4, 0.4);
const BODY_INK = rgb(0.1, 0.1, 0.1);
const GUIDE_INK = rgb(0.8, 0.8, 0.8);
const BUBBLE_BORDER = OMR_PAGE.answerBubbleBorder;

type Page = PDFPage;
type Origin = { dx: number; dy: number };

function clamp(n: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, n));
}

function pdfYFromTop(pageHeight: number, top: number, height: number) {
  return pageHeight - top - height;
}

function drawFilledRect(
  page: Page,
  pageHeight: number,
  left: number,
  top: number,
  width: number,
  height: number,
  color = rgb(0, 0, 0),
) {
  page.drawRectangle({
    x: left,
    y: pdfYFromTop(pageHeight, top, height),
    width,
    height,
    color,
  });
}

function drawOutlineRect(
  page: Page,
  pageHeight: number,
  left: number,
  top: number,
  width: number,
  height: number,
  borderWidth = PANEL_BORDER_WIDTH,
  borderColor = PANEL_BORDER,
) {
  page.drawRectangle({
    x: left,
    y: pdfYFromTop(pageHeight, top, height),
    width,
    height,
    borderColor,
    borderWidth,
  });
}

function drawTextTopDown(
  page: Page,
  pageHeight: number,
  text: string,
  left: number,
  baselineFromTop: number,
  size: number,
  font: PDFFont,
  color = BODY_INK,
) {
  page.drawText(pdfSafeText(text), {
    x: left,
    y: pageHeight - baselineFromTop,
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
  return /^\d{4}-\d{2}-\d{2}$/.test(d) ? ` · ${d}` : "";
}

function drawCornerBox(
  page: Page,
  pageHeight: number,
  left: number,
  top: number,
  size: number,
) {
  drawFilledRect(page, pageHeight, left, top, size, size);
  const inset = size * 0.25;
  drawFilledRect(page, pageHeight, left + inset, top + inset, size * 0.5, size * 0.5, rgb(1, 1, 1));
}

function drawBubble(
  page: Page,
  pageHeight: number,
  centerX: number,
  centerY: number,
  diameter: number,
  filled = false,
) {
  const r = diameter / 2;
  const pdfY = pageHeight - centerY;
  if (filled) {
    page.drawCircle({
      x: centerX,
      y: pdfY,
      size: r,
      color: rgb(0, 0, 0),
      borderColor: rgb(0, 0, 0),
      borderWidth: BUBBLE_BORDER,
    });
  } else {
    page.drawCircle({
      x: centerX,
      y: pdfY,
      size: r,
      borderColor: rgb(0, 0, 0),
      borderWidth: BUBBLE_BORDER,
    });
  }
}

/** Registration marks hug the content block (full / half / quarter tile). */
function drawRegistrationMarks(
  page: Page,
  profile: OmrLayoutProfile,
  origin: Origin,
) {
  const g = profile.geometry;
  const ph = g.pageHeight;
  const ox = origin.dx;
  const oy = origin.dy;
  const usedLeft = ox;
  const usedTop = oy;
  const usedRight = ox + g.contentBlockWidth;
  const usedBottom = oy + g.contentBlockHeight;

  drawCornerBox(page, ph, usedLeft + g.cornerMarkerOffset, usedTop + g.cornerMarkerOffset, g.cornerMarkerSize);
  drawCornerBox(
    page,
    ph,
    usedRight - g.cornerMarkerOffset - g.cornerMarkerSize,
    usedTop + g.cornerMarkerOffset,
    g.cornerMarkerSize,
  );
  drawCornerBox(
    page,
    ph,
    usedLeft + g.cornerMarkerOffset,
    usedBottom - g.cornerMarkerOffset - g.cornerMarkerSize,
    g.cornerMarkerSize,
  );
  drawCornerBox(
    page,
    ph,
    usedRight - g.cornerMarkerOffset - g.cornerMarkerSize,
    usedBottom - g.cornerMarkerOffset - g.cornerMarkerSize,
    g.cornerMarkerSize,
  );

  for (let x = g.timingMarkStartX; x < g.timingMarkEndX; x += g.timingMarkSpacing) {
    drawFilledRect(page, ph, ox + x, usedTop + g.timingMarkEdgeOffset, g.timingMarkSize, g.timingMarkSize);
    drawFilledRect(
      page,
      ph,
      ox + x,
      usedBottom - g.timingMarkEdgeOffset - g.timingMarkSize,
      g.timingMarkSize,
      g.timingMarkSize,
    );
  }
  for (let y = g.timingMarkStartY; y < g.timingMarkEndY; y += g.timingMarkSpacing) {
    drawFilledRect(page, ph, usedLeft + g.timingMarkEdgeOffset, oy + y, g.timingMarkSize, g.timingMarkSize);
    drawFilledRect(
      page,
      ph,
      usedRight - g.timingMarkEdgeOffset - g.timingMarkSize,
      oy + y,
      g.timingMarkSize,
      g.timingMarkSize,
    );
  }

  for (let row = 0; row < profile.grid.rows; row++) {
    const cy = oy + profileRowCenterY(profile, row);
    drawFilledRect(page, ph, ox + g.rowMarkX, cy - g.rowMarkSize / 2, g.rowMarkSize, g.rowMarkSize);
  }
}

function drawHeader(
  page: Page,
  profile: OmrLayoutProfile,
  subject: DbSubject,
  sectionName: string,
  qrPng: Awaited<ReturnType<PDFDocument["embedPng"]>>,
  font: PDFFont,
  fontBold: PDFFont,
  origin: Origin,
) {
  const g = profile.geometry;
  const ph = g.pageHeight;
  const ox = origin.dx;
  const oy = origin.dy;
  const scale = layoutScale(g);
  const titleFontSize = clamp(16 * scale, 11, 18);
  const metaFontSize = clamp(8.2 * scale, 7, 8.2);
  const hintFontSize = clamp(7.2 * scale, 6.2, 7.2);

  const scope = answerKeyScopeOf(subject);
  const sectionLabel = sectionName.trim() || "ALL";
  const scopeTag = scope.printScopeTag;
  const subtitleLine1 = fitHeaderText(
    `SECTION: ${sectionLabel} · ${scopeTag}${formatExamDate(subject.exam_date)} · ${subject.total_questions}Q`,
    48,
  );
  const subtitleLine2 = "NAME: _______________________________";
  const instructionLine =
    "Write your name. Shade your OMR ID. One bubble per question. Dark pencil (HB/2B).";

  const textLeft = ox + g.marginLeft;
  let baseline = oy + g.headerTop + titleFontSize;
  drawTextTopDown(
    page,
    ph,
    fitHeaderText(subject.name, 28),
    textLeft,
    baseline,
    titleFontSize,
    fontBold,
  );
  baseline += clamp(4 * scale, 2, 4) + metaFontSize;
  drawTextTopDown(page, ph, subtitleLine1, textLeft, baseline, metaFontSize, font);
  baseline += 2 + metaFontSize;
  drawTextTopDown(page, ph, subtitleLine2, textLeft, baseline, metaFontSize, font);
  if (scale >= 0.55) {
    baseline += 2 + hintFontSize;
    drawTextTopDown(page, ph, instructionLine, textLeft, baseline, hintFontSize, font, MUTED_INK);
  }

  const qrPadding = 3;
  const qrInner = g.qrCodeSize - qrPadding * 2;
  drawOutlineRect(
    page,
    ph,
    ox + g.qrCodeX,
    oy + g.qrCodeY,
    g.qrCodeSize,
    g.qrCodeSize,
    0.6,
    PANEL_BORDER,
  );
  page.drawImage(qrPng, {
    x: ox + g.qrCodeX + qrPadding,
    y: pdfYFromTop(ph, oy + g.qrCodeY + qrPadding, qrInner),
    width: qrInner,
    height: qrInner,
  });
}

function drawOmrIdSection(
  page: Page,
  profile: OmrLayoutProfile,
  fontBold: PDFFont,
  font: PDFFont,
  origin: Origin,
) {
  const g = profile.geometry;
  const ph = g.pageHeight;
  const ox = origin.dx;
  const oy = origin.dy;
  const scale = layoutScale(g);
  const gridW = answerGridWidth(g);
  drawOutlineRect(page, ph, ox + g.marginLeft, oy + g.omrIdTop, gridW, g.omrIdHeight);

  const relativeFirstColumnX = g.omrIdFirstColumnX - g.marginLeft;
  const relativeFirstRowY = g.omrIdFirstRowY - g.omrIdTop;
  const titleTop = 3;
  const titleFontSize = clamp(9 * scale, 7, 9);
  const digitFontSize = clamp(5.8 * scale, 5, 5.8);
  const digitLabelWidth = clamp(8 * scale, 6, 8);
  const digitLabelOffset = g.omrIdBubbleDiameter / 2 + clamp(10 * scale, 7, 10);

  const title = "OMR ID (4 DIGITS)";
  const titleWidth = fontBold.widthOfTextAtSize(title, titleFontSize);
  drawTextTopDown(
    page,
    ph,
    title,
    ox + g.marginLeft + (gridW - titleWidth) / 2,
    oy + g.omrIdTop + titleTop + titleFontSize,
    titleFontSize,
    fontBold,
  );

  for (let col = 0; col < OMR_PAGE.omrIdColumns; col++) {
    const columnCenterX =
      ox + g.marginLeft + relativeFirstColumnX + col * g.omrIdColumnSpacing;
    for (let digit = 0; digit < OMR_PAGE.omrIdRows; digit++) {
      const bubbleCenterY =
        oy + g.omrIdTop + relativeFirstRowY + digit * g.omrIdRowSpacing;
      const labelRight = columnCenterX - digitLabelOffset + digitLabelWidth;
      const label = String(digit);
      const labelWidth = font.widthOfTextAtSize(label, digitFontSize);
      drawTextTopDown(
        page,
        ph,
        label,
        labelRight - labelWidth,
        bubbleCenterY + 2,
        digitFontSize,
        font,
      );
      drawBubble(page, ph, columnCenterX, bubbleCenterY, g.omrIdBubbleDiameter, false);
    }
  }
}

function drawOptionIndicatorRow(
  page: Page,
  profile: OmrLayoutProfile,
  colIndex: number,
  fontBold: PDFFont,
  origin: Origin,
) {
  const g = profile.geometry;
  const ph = g.pageHeight;
  const { bubbleAreaLeft } = profileColumnBubbleLayout(profile);
  const columnLeft = origin.dx + g.answerGridLeft + colIndex * profile.grid.columnWidth;
  const labels = optionLabels(profile.optionsCount);

  for (let opt = 0; opt < labels.length; opt++) {
    const bubbleCenterX = bubbleAreaLeft + opt * profile.grid.bubbleSpacingX;
    const label = labels[opt];
    const labelWidth = fontBold.widthOfTextAtSize(label, 6.5);
    drawTextTopDown(
      page,
      ph,
      label,
      columnLeft + bubbleCenterX - labelWidth / 2,
      origin.dy + g.answerGridTop + 1 + 6.5,
      6.5,
      fontBold,
    );
  }
}

function drawQuestionColumn(
  page: Page,
  profile: OmrLayoutProfile,
  colIndex: number,
  startQuestion: number,
  endQuestion: number,
  font: PDFFont,
  origin: Origin,
) {
  const g = profile.geometry;
  const ph = g.pageHeight;
  const { rowContentLeft, bubbleAreaLeft } = profileColumnBubbleLayout(profile);
  const columnLeft = origin.dx + g.answerGridLeft + colIndex * profile.grid.columnWidth;
  const questionCount = endQuestion - startQuestion + 1;
  const labels = optionLabels(profile.optionsCount);

  for (let rowIndex = 0; rowIndex < profile.grid.rows; rowIndex++) {
    if (rowIndex >= questionCount) break;
    const questionNumber = startQuestion + rowIndex;
    const rowTop =
      origin.dy +
      g.answerGridTop +
      g.answerOptionIndicatorHeight +
      rowIndex * profile.grid.rowHeight;
    const rowMid = rowTop + profile.grid.rowHeight / 2;

    drawTextTopDown(
      page,
      ph,
      `${questionNumber}.`,
      columnLeft + rowContentLeft,
      rowMid + 4,
      7,
      font,
    );

    for (let opt = 0; opt < labels.length; opt++) {
      const cx = columnLeft + bubbleAreaLeft + opt * profile.grid.bubbleSpacingX;
      drawBubble(page, ph, cx, rowMid, g.answerBubbleDiameter, false);
    }
  }
}

function drawAnswerGrid(
  page: Page,
  profile: OmrLayoutProfile,
  subject: DbSubject,
  font: PDFFont,
  fontBold: PDFFont,
  origin: Origin,
) {
  const g = profile.geometry;
  const ph = g.pageHeight;
  drawOutlineRect(
    page,
    ph,
    origin.dx + g.answerGridLeft,
    origin.dy + g.answerGridTop,
    answerGridWidth(g),
    answerGridHeight(g),
  );

  for (let col = 0; col < profile.grid.columns; col++) {
    const startQ = col * profile.grid.rows + 1;
    const endQ = Math.min(startQ + profile.grid.rows - 1, subject.total_questions);
    if (startQ > subject.total_questions) continue;

    drawOptionIndicatorRow(page, profile, col, fontBold, origin);
    drawQuestionColumn(page, profile, col, startQ, endQ, font, origin);
  }
}

function drawFooter(page: Page, geometry: OmrSheetGeometry, font: PDFFont, origin: Origin) {
  const scale = layoutScale(geometry);
  if (scale < 0.55) return;
  drawTextTopDown(
    page,
    geometry.pageHeight,
    "Lay flat, good lighting, dark pencil. Edge marks are for scanning — do not mark them.",
    origin.dx + geometry.marginLeft + 2,
    origin.dy + answerRowsBottom(geometry) + 4 + 5.8,
    5.8,
    font,
    MUTED_INK,
  );
}

function drawCalibrationMarks(page: Page, geometry: OmrSheetGeometry, origin: Origin) {
  const diameter = geometry.answerBubbleDiameter;
  const bubbleTop = origin.dy + geometry.calibrationY - diameter / 2;
  const cy = bubbleTop + diameter / 2;
  drawBubble(
    page,
    geometry.pageHeight,
    origin.dx + geometry.calibrationFilledX,
    cy,
    diameter,
    true,
  );
  drawBubble(
    page,
    geometry.pageHeight,
    origin.dx + geometry.calibrationEmptyX,
    cy,
    diameter,
    false,
  );
}

function drawTileCutGuides(
  page: Page,
  geometry: OmrSheetGeometry,
  tiling: { columns: number; rows: number },
) {
  const guideWidth = 0.6;
  const ph = geometry.pageHeight;
  for (let column = 1; column < tiling.columns; column++) {
    const x = column * geometry.contentBlockWidth - guideWidth / 2;
    drawFilledRect(page, ph, x, 0, guideWidth, geometry.pageHeight, GUIDE_INK);
  }
  for (let row = 1; row < tiling.rows; row++) {
    const y = row * geometry.contentBlockHeight - guideWidth / 2;
    drawFilledRect(page, ph, 0, y, geometry.pageWidth, guideWidth, GUIDE_INK);
  }
}

async function drawOneSheetTile(
  page: Page,
  profile: OmrLayoutProfile,
  subject: DbSubject,
  sectionName: string,
  font: PDFFont,
  fontBold: PDFFont,
  origin: Origin,
  pdf: PDFDocument,
) {
  const sheetId = generateSheetId();
  const qrText = buildQrPayload(subject, sectionName.trim() || "ALL", sheetId);
  const qrDataUrl = await QRCode.toDataURL(qrText, {
    margin: 0,
    width: 512,
    errorCorrectionLevel: "L",
  });
  const qrPng = await pdf.embedPng(qrDataUrl);

  drawRegistrationMarks(page, profile, origin);
  drawHeader(page, profile, subject, sectionName, qrPng, font, fontBold, origin);
  drawOmrIdSection(page, profile, fontBold, font, origin);
  drawAnswerGrid(page, profile, subject, font, fontBold, origin);
  drawFooter(page, profile.geometry, font, origin);
  drawCalibrationMarks(page, profile.geometry, origin);
}

function assertSectionPrintable(subject: DbSubject, sectionName: string) {
  const scope = answerKeyScopeOf(subject);
  const section = sectionName.trim();
  if (scope.isUnassigned) {
    throw new Error(
      "This answer key has no section assigned. Link a section on the answer key before printing.",
    );
  }
  if (section && !scope.allowsSection(section)) {
    throw new Error(
      `Section "${section}" is not on this answer key (${scope.badgeLabel}). ` +
        "Choose a linked section, or edit the key’s sections before printing.",
    );
  }
}

export async function generateAnswerSheetsPdf(
  subject: DbSubject,
  sectionName: string,
  copies: number,
): Promise<Uint8Array> {
  const fit = resolvePrintLayout(subject);
  if (!fit.ok) {
    throw new Error(fit.error);
  }
  assertSectionPrintable(subject, sectionName);

  const profile = fit.profile;
  const g = profile.geometry;
  const pdf = await PDFDocument.create();
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const count = Math.max(1, Math.min(copies, 200));
  const tiling = tilingForGeometry(g);
  const perPage = tiling?.sheetsPerPage ?? 1;

  for (let start = 0; start < count; start += perPage) {
    const page = pdf.addPage([g.pageWidth, g.pageHeight]);
    const end = Math.min(start + perPage, count);
    if (tiling) {
      drawTileCutGuides(page, g, tiling);
    }
    for (let slot = 0; slot < end - start; slot++) {
      const origin = tiling
        ? tileOffset(tiling, slot, g)
        : { dx: 0, dy: 0 };
      await drawOneSheetTile(
        page,
        profile,
        subject,
        sectionName,
        font,
        fontBold,
        origin,
        pdf,
      );
    }
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
