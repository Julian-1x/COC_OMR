import { PDFDocument, rgb, StandardFonts } from "pdf-lib";
import QRCode from "qrcode";
import type { DbStudent, DbSubject } from "@/lib/types/database";
import {
  PAGE,
  templateForCount,
  bubblePosition,
  questionPosition,
  buildQrPayload,
  bubbleCenterX,
  rowCenterY,
  answerRowsTop,
} from "@/lib/omr/constants";
import { generateSheetId } from "@/lib/import/roster";
import { formatPassingLabel } from "@/lib/omr/passing-score";

function drawCircle(
  page: ReturnType<PDFDocument["addPage"]>,
  x: number,
  y: number,
  diameter: number,
  fill = false,
) {
  const r = diameter / 2;
  const pdfY = PAGE.height - y;
  if (fill) {
    page.drawCircle({ x, y: pdfY, size: r, color: rgb(0, 0, 0) });
  } else {
    page.drawCircle({ x, y: pdfY, size: r, borderColor: rgb(0, 0, 0), borderWidth: 1.2 });
  }
}

function drawFilledSquare(page: ReturnType<PDFDocument["addPage"]>, x: number, y: number, size: number) {
  page.drawRectangle({
    x: x - size / 2,
    y: PAGE.height - y - size / 2,
    width: size,
    height: size,
    color: rgb(0, 0, 0),
  });
}

function drawCornerMarkers(page: ReturnType<PDFDocument["addPage"]>) {
  const s = PAGE.cornerMarkerSize;
  const o = PAGE.cornerMarkerOffset;
  const corners = [
    [o, o],
    [PAGE.width - o - s, o],
    [o, PAGE.height - o - s],
    [PAGE.width - o - s, PAGE.height - o - s],
  ];
  for (const [x, y] of corners) {
    page.drawRectangle({ x, y, width: s, height: s, color: rgb(0, 0, 0) });
  }
}

function drawTimingMarks(page: ReturnType<PDFDocument["addPage"]>) {
  const sz = PAGE.timingMarkSize;
  for (let x = PAGE.timingMarkStartX; x <= PAGE.timingMarkEndX; x += PAGE.timingMarkSpacing) {
    page.drawRectangle({ x: x - sz / 2, y: PAGE.timingMarkStartY - sz / 2, width: sz, height: sz, color: rgb(0, 0, 0) });
    page.drawRectangle({ x: x - sz / 2, y: PAGE.timingMarkEndY - sz / 2, width: sz, height: sz, color: rgb(0, 0, 0) });
  }
  for (let y = PAGE.timingMarkStartY; y <= PAGE.timingMarkEndY; y += PAGE.timingMarkSpacing) {
    page.drawRectangle({ x: PAGE.timingMarkStartX - sz / 2, y: y - sz / 2, width: sz, height: sz, color: rgb(0, 0, 0) });
    page.drawRectangle({ x: PAGE.timingMarkEndX - sz / 2, y: y - sz / 2, width: sz, height: sz, color: rgb(0, 0, 0) });
  }
}

async function drawSheetPage(
  pdf: PDFDocument,
  subject: DbSubject,
  sectionName: string,
  student?: DbStudent,
) {
  const page = pdf.addPage([PAGE.width, PAGE.height]);
  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const fontBold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const template = templateForCount(subject.total_questions);
  const sheetId = generateSheetId();
  const qrText = buildQrPayload(subject, sectionName, sheetId);
  const qrDataUrl = await QRCode.toDataURL(qrText, { margin: 0, width: 200 });
  const qrImage = await pdf.embedPng(qrDataUrl);

  drawCornerMarkers(page);
  drawTimingMarks(page);

  page.drawImage(qrImage, {
    x: PAGE.qrX,
    y: PAGE.height - PAGE.qrY - PAGE.qrSize,
    width: PAGE.qrSize,
    height: PAGE.qrSize,
  });

  const headerY = PAGE.height - PAGE.marginTop - 20;
  page.drawText(subject.name, { x: PAGE.marginLeft, y: headerY, size: 14, font: fontBold, color: rgb(0.1, 0.1, 0.1) });
  page.drawText(`Section: ${sectionName}`, { x: PAGE.marginLeft, y: headerY - 16, size: 10, font, color: rgb(0.3, 0.3, 0.3) });
  page.drawText(`${subject.total_questions} items · ${formatPassingLabel(subject.passing_score, subject.total_questions)}`, {
    x: PAGE.marginLeft,
    y: headerY - 30,
    size: 9,
    font,
    color: rgb(0.4, 0.4, 0.4),
  });

  page.drawText("STUDENT ID (OMR)", {
    x: PAGE.marginLeft,
    y: PAGE.height - PAGE.omrIdTop + 10,
    size: 9,
    font: fontBold,
  });

  const omrDigits = (student?.omr_id ?? "0000").padStart(4, "0").slice(0, 4);
  for (let col = 0; col < PAGE.omrIdColumns; col++) {
    const cx = PAGE.omrIdFirstColumnX + col * PAGE.omrIdColumnSpacing;
    page.drawText(String(col + 1), { x: cx - 3, y: PAGE.height - PAGE.omrIdTop + 10, size: 8, font: fontBold });
    for (let row = 0; row < PAGE.omrIdRows; row++) {
      const cy = PAGE.omrIdFirstRowY + row * PAGE.omrIdRowSpacing;
      const digit = row.toString();
      const filled = omrDigits[col] === digit;
      page.drawText(digit, { x: cx - 14, y: PAGE.height - cy - 3, size: 7, font });
      drawCircle(page, cx, cy, PAGE.omrIdBubbleDiameter, filled);
    }
  }

  if (student) {
    page.drawText(student.name, {
      x: PAGE.marginLeft,
      y: PAGE.height - PAGE.omrIdTop - PAGE.omrIdHeight - 8,
      size: 10,
      font,
    });
  }

  for (let col = 0; col < template.columns; col++) {
    const cx = bubbleCenterX(template, col, 2);
    for (let opt = 0; opt < PAGE.answerOptionsCount; opt++) {
      const bx = bubbleCenterX(template, col, opt);
      page.drawText(PAGE.answerOptionLabels[opt], {
        x: bx - 3,
        y: PAGE.height - answerRowsTop() + 4,
        size: 7,
        font: fontBold,
      });
    }
    void cx;
  }

  for (let q = 1; q <= subject.total_questions; q++) {
    const { col, row } = questionPosition(template, q);
    const qx = PAGE.answerGridLeft + col * template.columnWidth + PAGE.answerColumnInset;
    const qy = rowCenterY(template, row);
    page.drawText(String(q), { x: qx, y: PAGE.height - qy - 3, size: 7, font });
    for (let opt = 0; opt < PAGE.answerOptionsCount; opt++) {
      const pos = bubblePosition(template, q, opt);
      drawCircle(page, pos.x, pos.y, PAGE.answerBubbleDiameter);
    }
  }

  drawCircle(page, PAGE.calibrationFilledX, PAGE.calibrationY, PAGE.calibrationBubbleSize, true);
  drawCircle(page, PAGE.calibrationEmptyX, PAGE.calibrationY, PAGE.calibrationBubbleSize, false);

  page.drawText("Print at 100% scale (Actual size). Do not shrink to fit.", {
    x: PAGE.marginLeft,
    y: 18,
    size: 7,
    font,
    color: rgb(0.45, 0.45, 0.45),
  });
}

export async function generateAnswerSheetPdf(
  subject: DbSubject,
  sectionName: string,
  students?: DbStudent[],
): Promise<Uint8Array> {
  const pdf = await PDFDocument.create();
  if (students && students.length > 0) {
    for (const student of students) {
      await drawSheetPage(pdf, subject, sectionName, student);
    }
  } else {
    await drawSheetPage(pdf, subject, sectionName);
  }
  return pdf.save();
}

export async function generateBlankSheetsPdf(
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
