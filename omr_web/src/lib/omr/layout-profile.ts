/**
 * Mirror of OmrLayoutProfile.tryComputeExplicitGrid in omr_template_specs.dart.
 * Resolves print/scan layout from synced answer-key custom grid fields.
 */
import { OMR_PAGE, templateForCount, type OmrTemplate } from "@/lib/omr/constants";
import { isStandardSheetQuestionCount } from "@/lib/omr/answer-key-scope";
import type { DbSubject } from "@/lib/types/database";
import {
  answerGridContentHeight,
  answerGridWidth,
  answerRowsTop,
  denseFullPortraitGeometry,
  geometryForForm,
  parseLayoutForm,
  standardPortraitGeometry,
  type OmrLayoutForm,
  type OmrSheetGeometry,
} from "@/lib/omr/sheet-geometry";

export const MIN_CUSTOM_ITEMS = 5;
export const MAX_CUSTOM_ITEMS = 200;
export const MIN_ROW_HEIGHT = 20;
export const MIN_ROW_HEIGHT_DENSE = 16;
export const DENSE_PACK_MARGIN = 0.5;
export const MIN_BUBBLE_SPACING_X = 12.5;
export const MIN_BUBBLE_SPACING_X_DENSE = 11.5;
export const DENSE_SPACING_MARGIN = 0.5;
export const MIN_BUBBLE_SPACING_X_QUARTER = 14;
export const PREFERRED_MAX_BUBBLE_SPACING_X = 26;
export const MIN_BUBBLE_VERTICAL_CLEARANCE = 4;
export const MAX_ROWS_PER_COLUMN = 31;
export const MAX_COLUMNS_LENGTHWISE = 5;
export const ABSOLUTE_MAX_COLUMNS_LENGTHWISE = 8;
export const MAX_COLUMNS_QUARTER = 4;

export type OmrLayoutProfile = {
  grid: OmrTemplate;
  optionsCount: number;
  isCustom: boolean;
  form: OmrLayoutForm;
  itemCount: number;
  geometry: OmrSheetGeometry;
};

export type LayoutFitResult =
  | { ok: true; profile: OmrLayoutProfile; error?: undefined }
  | { ok: false; profile?: undefined; error: string };

function clampInt(n: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, Math.trunc(n)));
}

function isFullLengthwise(form: OmrLayoutForm): boolean {
  return form.orientation === "lengthwise" && form.pageFill === "full";
}

export function maxColumnsFor(form: OmrLayoutForm, itemCount = 0): number {
  if (form.orientation === "crosswise") return 6;
  if (form.pageFill === "quarter") return MAX_COLUMNS_QUARTER;
  if (itemCount <= 0) return MAX_COLUMNS_LENGTHWISE;
  const preferredCapacity = MAX_COLUMNS_LENGTHWISE * MAX_ROWS_PER_COLUMN;
  if (itemCount <= preferredCapacity) return MAX_COLUMNS_LENGTHWISE;
  const needed = Math.ceil(itemCount / MAX_ROWS_PER_COLUMN);
  if (needed <= MAX_COLUMNS_LENGTHWISE) return MAX_COLUMNS_LENGTHWISE;
  return clampInt(needed, MAX_COLUMNS_LENGTHWISE, ABSOLUTE_MAX_COLUMNS_LENGTHWISE);
}

export function minBubbleSpacingXFor(form: OmrLayoutForm): number {
  return form.pageFill === "quarter" ? MIN_BUBBLE_SPACING_X_QUARTER : MIN_BUBBLE_SPACING_X;
}

export function scanMinRowHeight(geometry: OmrSheetGeometry): number {
  const clearanceFloor = geometry.answerBubbleDiameter + MIN_BUBBLE_VERTICAL_CLEARANCE;
  const packFloor =
    geometry.answerBubbleDiameter < OMR_PAGE.answerBubbleDiameter
      ? MIN_ROW_HEIGHT_DENSE + DENSE_PACK_MARGIN
      : MIN_ROW_HEIGHT;
  return Math.max(clearanceFloor, packFloor);
}

export function scanMinBubbleSpacing(form: OmrLayoutForm, geometry: OmrSheetGeometry): number {
  if (form.pageFill === "quarter") return MIN_BUBBLE_SPACING_X_QUARTER;
  if (geometry.answerBubbleDiameter < OMR_PAGE.answerBubbleDiameter) {
    return MIN_BUBBLE_SPACING_X_DENSE + DENSE_SPACING_MARGIN;
  }
  return MIN_BUBBLE_SPACING_X;
}

function rowPitchScannable(args: {
  rowHeight: number;
  geometry: OmrSheetGeometry;
  minRow: number;
}): boolean {
  if (args.rowHeight < args.minRow) return false;
  if (args.rowHeight < args.geometry.answerBubbleDiameter + MIN_BUBBLE_VERTICAL_CLEARANCE) {
    return false;
  }
  return true;
}

function maxBubbleSpacing(
  columnWidth: number,
  optionsCount: number,
  geometry: OmrSheetGeometry,
): number {
  const usableWidth = columnWidth - geometry.answerColumnInset * 2;
  const fixed = geometry.questionNumberWidth + geometry.answerNumberBubbleGap;
  const span = usableWidth - fixed - geometry.answerBubbleDiameter;
  const gaps = clampInt(optionsCount, 2, 6) - 1;
  if (gaps <= 0) return span;
  if (span <= 0) return 0;
  return span / gaps;
}

export function profileRowCenterY(profile: OmrLayoutProfile, rowIndex: number): number {
  return (
    answerRowsTop(profile.geometry) +
    rowIndex * profile.grid.rowHeight +
    profile.grid.rowHeight / 2
  );
}

export function profileBubbleCenterX(
  profile: OmrLayoutProfile,
  colIndex: number,
  optionIndex: number,
): number {
  const g = profile.geometry;
  const optionSpan = clampInt(profile.optionsCount, 2, 6) - 1;
  const columnLeft = g.answerGridLeft + colIndex * profile.grid.columnWidth;
  const bubbleAreaWidth = profile.grid.bubbleSpacingX * optionSpan;
  const usableWidth = profile.grid.columnWidth - g.answerColumnInset * 2;
  const rowContentWidth = g.questionNumberWidth + g.answerNumberBubbleGap + bubbleAreaWidth;
  const rowContentLeft =
    columnLeft + g.answerColumnInset + (usableWidth - rowContentWidth) / 2;
  const bubbleAreaLeft = rowContentLeft + g.questionNumberWidth + g.answerNumberBubbleGap;
  return bubbleAreaLeft + optionIndex * profile.grid.bubbleSpacingX;
}

export function profileColumnBubbleLayout(profile: OmrLayoutProfile) {
  const g = profile.geometry;
  const opts = clampInt(profile.optionsCount, 2, 6);
  const bubbleAreaWidth = profile.grid.bubbleSpacingX * (opts - 1);
  const usableWidth = profile.grid.columnWidth - g.answerColumnInset * 2;
  const rowContentWidth = g.questionNumberWidth + g.answerNumberBubbleGap + bubbleAreaWidth;
  const rowContentLeft = g.answerColumnInset + (usableWidth - rowContentWidth) / 2;
  const bubbleAreaLeft = rowContentLeft + g.questionNumberWidth + g.answerNumberBubbleGap;
  return { rowContentLeft, bubbleAreaLeft, bubbleAreaWidth };
}

function bubblesFitInsideColumns(profile: OmrLayoutProfile): boolean {
  const opts = clampInt(profile.optionsCount, 2, 6);
  const g = profile.geometry;
  for (let col = 0; col < profile.grid.columns; col++) {
    const leftEdge = profileBubbleCenterX(profile, col, 0) - g.answerBubbleDiameter / 2;
    const rightEdge =
      profileBubbleCenterX(profile, col, opts - 1) + g.answerBubbleDiameter / 2;
    const columnLeft = g.answerGridLeft + col * profile.grid.columnWidth;
    const columnRight = columnLeft + profile.grid.columnWidth;
    if (leftEdge < columnLeft - 0.05 || rightEdge > columnRight + 0.05) {
      return false;
    }
  }
  return true;
}

function hasAdequateTimingMarks(geometry: OmrSheetGeometry, minPerEdge = 4): boolean {
  const spacing = geometry.timingMarkSpacing;
  if (spacing <= 0) return false;
  const xCount = Math.floor((geometry.timingMarkEndX - geometry.timingMarkStartX) / spacing) + 1;
  const yCount = Math.floor((geometry.timingMarkEndY - geometry.timingMarkStartY) / spacing) + 1;
  return xCount >= minPerEdge && yCount >= minPerEdge;
}

function tryExplicitGridOnGeometry(args: {
  columns: number;
  rows: number;
  items: number;
  opts: number;
  form: OmrLayoutForm;
  geometry: OmrSheetGeometry;
  minRow: number;
  minSpacing: number;
}): LayoutFitResult {
  const { columns, rows, items, opts, form, geometry, minRow, minSpacing } = args;
  if (answerGridContentHeight(geometry) < minRow * 2 || answerGridWidth(geometry) < 80) {
    return {
      ok: false,
      error:
        "This page size is too small for a scannable answer grid. Try Full page or Half page.",
    };
  }

  const gridHeight = answerGridContentHeight(geometry);
  const gridWidth = answerGridWidth(geometry);
  const rowHeight = gridHeight / rows;
  if (rows > MAX_ROWS_PER_COLUMN) {
    return {
      ok: false,
      error: `Grid height ${rows} exceeds the scan-safe maximum of ${MAX_ROWS_PER_COLUMN} rows per column.`,
    };
  }
  const maxCols = maxColumnsFor(form, items);
  if (columns > maxCols) {
    return {
      ok: false,
      error: `Grid width ${columns} is too wide to scan reliably on a phone. Use at most ${maxCols} tall columns.`,
    };
  }
  if (columns === 1 && items > 25) {
    return {
      ok: false,
      error: "A single question column is not reliable for this many questions. Use at least 2 columns.",
    };
  }
  if (!rowPitchScannable({ rowHeight, geometry, minRow })) {
    return {
      ok: false,
      error:
        `Grid height ${rows} is too tall for this sheet — rows would be too small to scan reliably.`,
    };
  }

  const columnWidth = gridWidth / columns;
  const maxSpacing = maxBubbleSpacing(columnWidth, opts, geometry);
  if (maxSpacing < minSpacing) {
    return {
      ok: false,
      error:
        `Grid width ${columns} is too wide for this sheet — bubbles would be too close together.`,
    };
  }

  const bubbleSpacingX =
    maxSpacing < PREFERRED_MAX_BUBBLE_SPACING_X ? maxSpacing : PREFERRED_MAX_BUBBLE_SPACING_X;

  const grid: OmrTemplate = {
    templateId: `custom_${items}_o${opts}_${form.id}_${columns}x${rows}`,
    maxItems: items,
    columns,
    rows,
    rowHeight,
    columnWidth,
    bubbleSpacingX,
  };

  const profile: OmrLayoutProfile = {
    grid,
    optionsCount: opts,
    isCustom: true,
    form,
    itemCount: items,
    geometry,
  };

  if (!bubblesFitInsideColumns(profile)) {
    return {
      ok: false,
      error: "Bubbles would spill past column edges on this grid.",
    };
  }
  if (!hasAdequateTimingMarks(geometry)) {
    return {
      ok: false,
      error: "This page size does not leave enough room for timing marks. Use a full portrait page.",
    };
  }

  return { ok: true, profile };
}

/** Port of OmrLayoutProfile.tryComputeExplicitGrid. */
export function tryComputeExplicitGrid(args: {
  columns: number;
  rows: number;
  optionsCount: number;
  form: OmrLayoutForm;
  itemCount?: number;
}): LayoutFitResult {
  const cols = clampInt(args.columns, 1, 10);
  const rowCount = clampInt(args.rows, 1, 200);
  const capacity = cols * rowCount;
  const opts = clampInt(args.optionsCount, 2, 6);
  const items = args.itemCount ?? capacity;

  if (items < MIN_CUSTOM_ITEMS) {
    return { ok: false, error: `Custom sheets need at least ${MIN_CUSTOM_ITEMS} questions.` };
  }
  if (items > MAX_CUSTOM_ITEMS) {
    return { ok: false, error: `Custom sheets support at most ${MAX_CUSTOM_ITEMS} questions.` };
  }
  if (capacity < items) {
    return {
      ok: false,
      error: `Grid ${cols}×${rowCount} holds only ${capacity} questions, but this exam has ${items}.`,
    };
  }
  if (capacity - items >= cols) {
    return {
      ok: false,
      error: `Grid ${cols}×${rowCount} has too many empty slots for ${items} questions.`,
    };
  }

  const form = args.form;
  const roomy = tryExplicitGridOnGeometry({
    columns: cols,
    rows: rowCount,
    items,
    opts,
    form,
    geometry: geometryForForm(form),
    minRow: MIN_ROW_HEIGHT,
    minSpacing: minBubbleSpacingXFor(form),
  });
  if (roomy.ok) return roomy;

  if (isFullLengthwise(form)) {
    const denseGeometry = denseFullPortraitGeometry();
    const dense = tryExplicitGridOnGeometry({
      columns: cols,
      rows: rowCount,
      items,
      opts,
      form,
      geometry: denseGeometry,
      minRow: scanMinRowHeight(denseGeometry),
      minSpacing: scanMinBubbleSpacing(form, denseGeometry),
    });
    if (dense.ok) return dense;
  }

  return roomy;
}

function standardProfile(subject: DbSubject): LayoutFitResult {
  if (!isStandardSheetQuestionCount(subject.total_questions)) {
    return {
      ok: false,
      error:
        "This answer key is not a standard 30–100 sheet and has no synced custom layout. " +
        "Open it on the phone, attach a custom sheet, sync, then print here.",
    };
  }
  const grid = templateForCount(subject.total_questions);
  return {
    ok: true,
    profile: {
      grid,
      optionsCount: OMR_PAGE.answerOptionsCount,
      isCustom: false,
      form: parseLayoutForm("lengthwise_full"),
      itemCount: subject.total_questions,
      geometry: standardPortraitGeometry(),
    },
  };
}

/**
 * Portrait forms the scanner still accepts (legacy half/quarter included).
 * New phone layouts are full portrait only — see teacherSelectableCustomForms in Dart.
 */
export const ALL_CUSTOM_FORMS: OmrLayoutForm[] = [
  parseLayoutForm("lengthwise_full"),
  parseLayoutForm("lengthwise_half"),
  parseLayoutForm("lengthwise_quarter"),
];

/**
 * Same gates as ScannerSessionLayout.examReadyScanErrorForSubject on the phone.
 * Web must refuse to print anything the phone would refuse to scan.
 */
export function examReadyScanErrorForSubject(subject: DbSubject): string | null {
  if (!subject.use_custom_layout) return null;

  const cols = subject.custom_grid_columns;
  const rows = subject.custom_grid_rows;
  if (cols == null || rows == null || cols < 1 || rows < 1) {
    return (
      "This custom sheet is missing its layout grid. " +
      "On the phone: open Print Sheets / the answer key, pick the custom layout again, Sync Now, then print here."
    );
  }

  const form = parseLayoutForm(subject.layout_shape ?? "lengthwise_full");
  if (!ALL_CUSTOM_FORMS.some((f) => f.id === form.id)) {
    return (
      "This custom sheet uses a landscape layout that is no longer supported. " +
      "On the phone, open the custom sheet editor and pick a portrait (lengthwise) layout, then sync."
    );
  }

  const fit = tryComputeExplicitGrid({
    columns: cols,
    rows,
    optionsCount: subject.options_count ?? 5,
    form,
    itemCount: subject.total_questions,
  });
  if (!fit.ok) {
    return (
      fit.error ??
      "This custom sheet layout is no longer scannable. Pick a different layout or question count on the phone."
    );
  }

  const profile = fit.profile;
  if (profile.itemCount < subject.total_questions) {
    return (
      `This custom sheet fits ${profile.itemCount} questions, but the answer key has ${subject.total_questions}. ` +
      "Update the layout or question count on the phone before printing."
    );
  }

  const gridCapacity = cols * rows;
  if (subject.total_questions > gridCapacity) {
    return `This layout grid holds ${gridCapacity} questions, but the answer key has ${subject.total_questions}.`;
  }

  if (profile.grid.rowHeight < scanMinRowHeight(profile.geometry)) {
    return "Rows on this sheet are too small to scan reliably. Pick a larger page size or fewer questions on the phone.";
  }
  if (profile.grid.rows > MAX_ROWS_PER_COLUMN) {
    return "This layout has too many rows per column to scan reliably.";
  }
  const maxCols = maxColumnsFor(form, subject.total_questions);
  if (profile.grid.columns > maxCols) {
    return `This layout is too wide to scan reliably. Use at most ${maxCols} question columns.`;
  }
  if (profile.grid.columns === 1 && subject.total_questions > 25) {
    return "A single question column is not reliable for this many questions. Use at least 2 columns.";
  }
  const minSpacing = scanMinBubbleSpacing(form, profile.geometry);
  if (profile.grid.bubbleSpacingX < minSpacing) {
    return "Bubbles on this sheet are too close together to scan reliably.";
  }
  if (
    profile.grid.rowHeight <
    profile.geometry.answerBubbleDiameter + MIN_BUBBLE_VERTICAL_CLEARANCE
  ) {
    return "Answer bubbles would sit too close vertically to scan reliably.";
  }

  return null;
}

/**
 * Resolve the print/scan profile for a synced answer key.
 * Custom keys need use_custom_layout + grid columns/rows from the phone,
 * and must pass the same exam-ready gates the phone scanner uses.
 */
export function resolvePrintLayout(subject: DbSubject): LayoutFitResult {
  const useCustom = Boolean(subject.use_custom_layout);

  if (useCustom) {
    const gate = examReadyScanErrorForSubject(subject);
    if (gate) {
      return { ok: false, error: gate };
    }
    const form = parseLayoutForm(subject.layout_shape ?? "lengthwise_full");
    return tryComputeExplicitGrid({
      columns: subject.custom_grid_columns!,
      rows: subject.custom_grid_rows!,
      optionsCount: subject.options_count ?? 5,
      form,
      itemCount: subject.total_questions,
    });
  }

  return standardProfile(subject);
}

export function canPrintOnWeb(subject: DbSubject): boolean {
  return resolvePrintLayout(subject).ok;
}

export function webPrintBlockedReason(subject: DbSubject): string | null {
  const fit = resolvePrintLayout(subject);
  return fit.ok ? null : fit.error;
}

export function optionLabels(optionsCount: number): string[] {
  return [...OMR_PAGE.answerOptionLabels].slice(0, clampInt(optionsCount, 2, 6));
}

/** Multi-up packing for half/quarter sheets — same as OmrSheetTiling.forGeometry. */
export type SheetTiling = { columns: number; rows: number; sheetsPerPage: number };

export function tilingForGeometry(geometry: {
  pageWidth: number;
  pageHeight: number;
  contentBlockWidth: number;
  contentBlockHeight: number;
}): SheetTiling | null {
  const epsilon = 0.05;
  const blockW = geometry.contentBlockWidth;
  const blockH = geometry.contentBlockHeight;
  const pageW = geometry.pageWidth;
  const pageH = geometry.pageHeight;
  if (blockW <= 0 || blockH <= 0) return null;

  const divides = (total: number, part: number) => {
    const rounded = Math.round(total / part);
    if (rounded < 1) return false;
    return Math.abs(rounded * part - total) <= epsilon;
  };
  if (!divides(pageW, blockW) || !divides(pageH, blockH)) return null;

  const columns = Math.round(pageW / blockW);
  const rows = Math.round(pageH / blockH);
  if (columns < 1 || rows < 1) return null;
  const sheetsPerPage = columns * rows;
  if (sheetsPerPage <= 1) return null;
  if (
    Math.abs(columns * blockW - pageW) > epsilon ||
    Math.abs(rows * blockH - pageH) > epsilon
  ) {
    return null;
  }
  return { columns, rows, sheetsPerPage };
}

export function tileOffset(
  tiling: SheetTiling,
  slotIndex: number,
  geometry: { contentBlockWidth: number; contentBlockHeight: number },
): { dx: number; dy: number } {
  return {
    dx: (slotIndex % tiling.columns) * geometry.contentBlockWidth,
    dy: Math.floor(slotIndex / tiling.columns) * geometry.contentBlockHeight,
  };
}
