/**
 * Mirror of OmrSheetGeometry in lib/models/omr_template_specs.dart.
 * Web custom print must share these numbers with the phone scanner.
 */
import { OMR_PAGE } from "@/lib/omr/constants";

export type OmrLayoutOrientation = "lengthwise" | "crosswise";
export type OmrLayoutPageFill = "full" | "half" | "quarter";

export type OmrLayoutForm = {
  orientation: OmrLayoutOrientation;
  pageFill: OmrLayoutPageFill;
  id: string;
};

export type OmrSheetGeometry = {
  pageWidth: number;
  pageHeight: number;
  contentBlockWidth: number;
  contentBlockHeight: number;
  marginLeft: number;
  marginTop: number;
  marginRight: number;
  marginBottom: number;
  cornerMarkerSize: number;
  cornerMarkerOffset: number;
  timingMarkSize: number;
  timingMarkSpacing: number;
  timingMarkEdgeOffset: number;
  timingMarkStartX: number;
  timingMarkEndX: number;
  timingMarkStartY: number;
  timingMarkEndY: number;
  headerTop: number;
  headerHeight: number;
  omrIdTop: number;
  omrIdHeight: number;
  omrIdFirstColumnX: number;
  omrIdFirstRowY: number;
  omrIdColumnSpacing: number;
  omrIdRowSpacing: number;
  omrIdBubbleDiameter: number;
  answerGridTop: number;
  answerGridBottom: number;
  answerGridLeft: number;
  answerGridRight: number;
  answerOptionIndicatorHeight: number;
  answerGridFooterHeight: number;
  answerBubbleDiameter: number;
  answerColumnInset: number;
  answerNumberBubbleGap: number;
  questionNumberWidth: number;
  calibrationY: number;
  calibrationFilledX: number;
  calibrationEmptyX: number;
  calibrationBubbleSize: number;
  rowMarkX: number;
  rowMarkSize: number;
  qrCodeSize: number;
  qrCodeX: number;
  qrCodeY: number;
};

function clamp(n: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, n));
}

export function parseLayoutForm(raw: string | null | undefined): OmrLayoutForm {
  const value = (raw ?? "").trim().toLowerCase();
  if (!value || value === "compact" || value === "long") {
    return { orientation: "lengthwise", pageFill: "full", id: "lengthwise_full" };
  }
  const parts = value.split("_");
  let orientation: OmrLayoutOrientation = "lengthwise";
  let pageFill: OmrLayoutPageFill = "full";
  if (parts.length >= 2) {
    orientation = parts[0].includes("cross") ? "crosswise" : "lengthwise";
    const fillRaw = parts.slice(1).join("_");
    if (fillRaw === "half") pageFill = "half";
    else if (fillRaw === "quarter" || fillRaw === "1/4" || fillRaw === "q") pageFill = "quarter";
  } else if (value.includes("cross")) {
    orientation = "crosswise";
  } else if (value === "half") {
    pageFill = "half";
  } else if (value === "quarter" || value === "1/4") {
    pageFill = "quarter";
  }
  return { orientation, pageFill, id: `${orientation}_${pageFill}` };
}

export function answerGridWidth(g: OmrSheetGeometry): number {
  return g.answerGridRight - g.answerGridLeft;
}

export function answerRowsTop(g: OmrSheetGeometry): number {
  return g.answerGridTop + g.answerOptionIndicatorHeight;
}

export function answerRowsBottom(g: OmrSheetGeometry): number {
  return g.answerGridBottom - g.answerGridFooterHeight;
}

export function answerGridContentHeight(g: OmrSheetGeometry): number {
  return answerRowsBottom(g) - answerRowsTop(g);
}

export function answerGridHeight(g: OmrSheetGeometry): number {
  return g.answerGridBottom - g.answerGridTop;
}

/** Scale vs frozen full-portrait width (1.0 = standard 30–100 sheet). */
export function layoutScale(g: OmrSheetGeometry): number {
  return g.contentBlockWidth / OMR_PAGE.pageWidth;
}

export function standardPortraitGeometry(): OmrSheetGeometry {
  return {
    pageWidth: OMR_PAGE.pageWidth,
    pageHeight: OMR_PAGE.pageHeight,
    contentBlockWidth: OMR_PAGE.contentBlockWidth,
    contentBlockHeight: OMR_PAGE.contentBlockHeight,
    marginLeft: OMR_PAGE.marginLeft,
    marginTop: OMR_PAGE.marginTop,
    marginRight: OMR_PAGE.marginRight,
    marginBottom: OMR_PAGE.marginBottom,
    cornerMarkerSize: OMR_PAGE.cornerMarkerSize,
    cornerMarkerOffset: OMR_PAGE.cornerMarkerOffset,
    timingMarkSize: OMR_PAGE.timingMarkSize,
    timingMarkSpacing: OMR_PAGE.timingMarkSpacing,
    timingMarkEdgeOffset: OMR_PAGE.timingMarkEdgeOffset,
    timingMarkStartX: OMR_PAGE.timingMarkStartX,
    timingMarkEndX: OMR_PAGE.timingMarkEndX,
    timingMarkStartY: OMR_PAGE.timingMarkStartY,
    timingMarkEndY: OMR_PAGE.timingMarkEndY,
    headerTop: OMR_PAGE.headerTop,
    headerHeight: OMR_PAGE.headerHeight,
    omrIdTop: OMR_PAGE.omrIdTop,
    omrIdHeight: OMR_PAGE.omrIdHeight,
    omrIdFirstColumnX: OMR_PAGE.omrIdFirstColumnX,
    omrIdFirstRowY: OMR_PAGE.omrIdFirstRowY,
    omrIdColumnSpacing: OMR_PAGE.omrIdColumnSpacing,
    omrIdRowSpacing: OMR_PAGE.omrIdRowSpacing,
    omrIdBubbleDiameter: OMR_PAGE.omrIdBubbleDiameter,
    answerGridTop: OMR_PAGE.answerGridTop,
    answerGridBottom: OMR_PAGE.answerGridBottom,
    answerGridLeft: OMR_PAGE.answerGridLeft,
    answerGridRight: OMR_PAGE.answerGridRight,
    answerOptionIndicatorHeight: OMR_PAGE.answerOptionIndicatorHeight,
    answerGridFooterHeight: OMR_PAGE.answerGridFooterHeight,
    answerBubbleDiameter: OMR_PAGE.answerBubbleDiameter,
    answerColumnInset: OMR_PAGE.answerColumnInset,
    answerNumberBubbleGap: OMR_PAGE.answerNumberBubbleGap,
    questionNumberWidth: OMR_PAGE.questionNumberWidth,
    calibrationY: OMR_PAGE.calibrationY,
    calibrationFilledX: OMR_PAGE.calibrationFilledX,
    calibrationEmptyX: OMR_PAGE.calibrationEmptyX,
    calibrationBubbleSize: OMR_PAGE.calibrationBubbleSize,
    rowMarkX: OMR_PAGE.rowMarkX,
    rowMarkSize: OMR_PAGE.rowMarkSize,
    qrCodeSize: OMR_PAGE.qrCodeSize,
    qrCodeX: OMR_PAGE.qrCodeX,
    qrCodeY: OMR_PAGE.qrCodeY,
  };
}

/** Dense full-page geometry — same registration, smaller answer bubbles. */
export function denseFullPortraitGeometry(): OmrSheetGeometry {
  const bubble = 9.5;
  const footer = 8.0;
  const inset = bubble / 2 + 1.0;
  return {
    ...standardPortraitGeometry(),
    answerGridFooterHeight: footer,
    answerBubbleDiameter: bubble,
    answerColumnInset: inset,
    answerNumberBubbleGap: 4.0,
    questionNumberWidth: 13.0,
  };
}

function rowMarkX(args: {
  contentLeft: number;
  timingEdge: number;
  timingSize: number;
  rowMarkSize: number;
  scale: number;
}): number {
  const leftOfContent = args.contentLeft - clamp(10 * args.scale, 6, 10);
  const sampleHalf = clamp(args.rowMarkSize, 3, 6);
  const clearOfTiming = args.timingEdge + args.timingSize + sampleHalf + 1;
  return leftOfContent < clearOfTiming ? clearOfTiming : leftOfContent;
}

/**
 * Auto-place page size, content block, and registration marks for a form.
 * Full lengthwise always returns standard portrait (frozen 30–100 contract).
 */
export function geometryForForm(form: OmrLayoutForm): OmrSheetGeometry {
  const lengthwise = form.orientation === "lengthwise";
  if (lengthwise && form.pageFill === "full") {
    return standardPortraitGeometry();
  }

  const pageWidth = lengthwise ? OMR_PAGE.pageWidth : OMR_PAGE.pageHeight;
  const pageHeight = lengthwise ? OMR_PAGE.pageHeight : OMR_PAGE.pageWidth;

  let blockWidth = pageWidth;
  let blockHeight = pageHeight;
  if (form.pageFill === "half") {
    blockHeight = pageHeight / 2;
  } else if (form.pageFill === "quarter") {
    blockWidth = pageWidth / 2;
    blockHeight = pageHeight / 2;
  }

  const scaleW = blockWidth / OMR_PAGE.pageWidth;
  const scaleH = blockHeight / OMR_PAGE.pageHeight;
  const scale = clamp(Math.min(scaleW, scaleH), 0.48, 1);

  const marginLeft = clamp(OMR_PAGE.marginLeft * scale, 12, 28);
  const marginRight = clamp(OMR_PAGE.marginRight * scale, 12, 28);
  const marginTop = clamp(OMR_PAGE.marginTop * scale, 14, 34);
  const marginBottom = clamp(OMR_PAGE.marginBottom * scale, 12, 28);
  const cornerSize = clamp(OMR_PAGE.cornerMarkerSize * scale, 12, 20);
  const cornerOffset = clamp(OMR_PAGE.cornerMarkerOffset * scale, 5, 8);
  const timingSize = clamp(OMR_PAGE.timingMarkSize * scale, 4, 6);
  const timingEdge = clamp(OMR_PAGE.timingMarkEdgeOffset * scale, 5, 8);

  const blockLeft = 0;
  const blockTop = 0;
  const contentLeft = blockLeft + marginLeft;
  const contentTop = blockTop + marginTop;
  const contentRight = blockLeft + blockWidth - marginRight;
  const contentBottom = blockTop + blockHeight - marginBottom;
  const contentWidth = contentRight - contentLeft;

  const qrSize = clamp(OMR_PAGE.qrCodeSize * scale, 56, OMR_PAGE.qrCodeSize);
  const qrCodeX = contentRight - qrSize;
  const qrCodeY = contentTop;

  const headerHeight = Math.max(clamp(OMR_PAGE.headerHeight * scale, 52, 80), qrSize + 8);
  const headerTop = contentTop;

  const omrIdTitleBand = 14;
  const omrIdDigitRows = OMR_PAGE.omrIdRows;
  const omrBubble = clamp(OMR_PAGE.omrIdBubbleDiameter * scale, 8, 11.5);
  let omrRowSpacing = clamp(OMR_PAGE.omrIdRowSpacing * scale, 8, 12);
  const maxOmrBlockWidth = contentWidth * 0.94;
  let omrColSpacing = clamp(OMR_PAGE.omrIdColumnSpacing * scale, 22, 50);
  const maxColSpacing = (maxOmrBlockWidth - omrBubble) / (OMR_PAGE.omrIdColumns - 1);
  if (omrColSpacing > maxColSpacing) {
    omrColSpacing = clamp(maxColSpacing, 18, 50);
  }
  const minOmrRowSpacing = omrBubble + 3;
  if (omrRowSpacing < minOmrRowSpacing) {
    omrRowSpacing = minOmrRowSpacing;
  }
  const omrBlockWidth = omrColSpacing * (OMR_PAGE.omrIdColumns - 1) + omrBubble;
  let omrIdHeight =
    omrIdTitleBand + omrBubble + (omrIdDigitRows - 1) * omrRowSpacing + 8;
  const omrIdTop = headerTop + headerHeight + clamp(6 * scale, 4, 8);
  let omrIdFirstRowY = omrIdTop + omrIdTitleBand + omrBubble / 2;
  const omrIdFirstColumnX = contentLeft + (contentWidth - omrBlockWidth) / 2;

  const footerReserve = clamp(OMR_PAGE.answerGridFooterHeight * scale, 16, 30);
  const optionBar = clamp(OMR_PAGE.answerOptionIndicatorHeight * scale, 10, 14);
  let answerGridTop = omrIdTop + omrIdHeight + clamp(10 * scale, 6, 12);
  const answerGridBottom = contentBottom - footerReserve;
  const answerGridLeft = contentLeft;
  const answerGridRight = contentRight;

  const minAnswerGridHeight = 48;
  const availableForAnswers =
    answerGridBottom - answerGridTop - optionBar - footerReserve;
  if (availableForAnswers < minAnswerGridHeight) {
    const deficit = minAnswerGridHeight - availableForAnswers;
    const spacingShrink = deficit / (omrIdDigitRows - 1);
    const shrunk = omrRowSpacing - spacingShrink;
    const upper = Math.max(minOmrRowSpacing, 12);
    omrRowSpacing = clamp(shrunk, minOmrRowSpacing, upper);
    omrIdHeight =
      omrIdTitleBand + omrBubble + (omrIdDigitRows - 1) * omrRowSpacing + 8;
    omrIdFirstRowY = omrIdTop + omrIdTitleBand + omrBubble / 2;
    answerGridTop = omrIdTop + omrIdHeight + clamp(10 * scale, 6, 12);
  }

  const answerRowsTopLocal = answerGridTop + optionBar;
  const answerRowsBottomLocal = answerGridBottom - footerReserve;

  const timingInsetX = clamp(OMR_PAGE.timingMarkStartX * scale, 20, 60);
  const timingStartX = blockLeft + timingInsetX;
  const timingEndX = blockLeft + blockWidth - timingInsetX;
  let timingStartY = clamp(
    answerRowsTopLocal - clamp(14 * scale, 8, 14),
    blockTop + timingEdge,
    blockTop + blockHeight - timingEdge,
  );
  let timingEndY = clamp(
    answerRowsBottomLocal + clamp(14 * scale, 8, 14),
    blockTop + timingEdge,
    blockTop + blockHeight - timingEdge,
  );
  const gridSpan = clamp(timingEndY - timingStartY, 40, blockHeight);
  let timingSpacing = clamp(
    OMR_PAGE.timingMarkSpacing * scale,
    24,
    clamp(gridSpan / 3, 24, 80),
  );
  const xSpan = clamp(timingEndX - timingStartX, 40, blockWidth);
  const ySpan = clamp(timingEndY - timingStartY, 40, blockHeight);
  const maxSpacingForFourX = xSpan / 3;
  const maxSpacingForFourY = ySpan / 3;
  if (timingSpacing > maxSpacingForFourX) {
    timingSpacing = clamp(maxSpacingForFourX, 16, timingSpacing);
  }
  if (timingSpacing > maxSpacingForFourY) {
    timingSpacing = clamp(maxSpacingForFourY, 16, timingSpacing);
  }

  const answerBubble = clamp(OMR_PAGE.answerBubbleDiameter * scale, 8, 11.5);
  const calSize = clamp(OMR_PAGE.calibrationBubbleSize * scale, 7, 10);
  const printerBleed = 4;
  const calY = clamp(
    contentBottom - calSize / 2 - printerBleed,
    contentTop + 20,
    contentBottom - calSize / 2,
  );
  const answerColumnInset = Math.max(
    clamp(OMR_PAGE.answerColumnInset * scale, 3, 6),
    answerBubble / 2 + 1,
  );
  const rowMarkSize = clamp(OMR_PAGE.rowMarkSize * scale, 3, 4);

  return {
    pageWidth,
    pageHeight,
    contentBlockWidth: blockWidth,
    contentBlockHeight: blockHeight,
    marginLeft,
    marginTop,
    marginRight,
    marginBottom,
    cornerMarkerSize: cornerSize,
    cornerMarkerOffset: cornerOffset,
    timingMarkSize: timingSize,
    timingMarkSpacing: timingSpacing,
    timingMarkEdgeOffset: timingEdge,
    timingMarkStartX: timingStartX,
    timingMarkEndX: timingEndX,
    timingMarkStartY: timingStartY,
    timingMarkEndY: timingEndY,
    headerTop,
    headerHeight,
    omrIdTop,
    omrIdHeight,
    omrIdFirstColumnX,
    omrIdFirstRowY,
    omrIdColumnSpacing: omrColSpacing,
    omrIdRowSpacing: omrRowSpacing,
    omrIdBubbleDiameter: omrBubble,
    answerGridTop,
    answerGridBottom,
    answerGridLeft,
    answerGridRight,
    answerOptionIndicatorHeight: optionBar,
    answerGridFooterHeight: footerReserve,
    answerBubbleDiameter: answerBubble,
    answerColumnInset,
    answerNumberBubbleGap: clamp(OMR_PAGE.answerNumberBubbleGap * scale, 3, 6),
    questionNumberWidth: clamp(OMR_PAGE.questionNumberWidth * scale, 10, 16),
    calibrationY: calY,
    calibrationFilledX: contentLeft + clamp(52 * scale, 24, 52),
    calibrationEmptyX: contentLeft + clamp(82 * scale, 40, 82),
    calibrationBubbleSize: calSize,
    rowMarkX: rowMarkX({
      contentLeft,
      timingEdge,
      timingSize,
      rowMarkSize,
      scale,
    }),
    rowMarkSize,
    qrCodeSize: qrSize,
    qrCodeX,
    qrCodeY,
  };
}
