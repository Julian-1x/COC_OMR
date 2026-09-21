import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";
import {
  buildItemAnalysisReport,
  exportItemAnalysisCsv,
  exportItemAnalysisPdf,
} from "@/lib/omr/item-analysis";
import {
  buildStudentFeedbackRows,
  exportStudentFeedbackPdf,
} from "@/lib/omr/student-feedback";
import { exportResultsCsv, exportResultsPdf } from "@/lib/pdf/exports";
import { downloadBlob, downloadText } from "@/lib/utils";

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function safeFilePart(value: string): string {
  return value.replace(/[^\w.-]+/g, "_").slice(0, 40) || "export";
}

export type ResultsPackInput = {
  scans: DbScanResult[];
  students: DbStudent[];
  subjects: DbSubject[];
  sectionFilter?: string;
  subjectFilter?: string;
  /** Scans with detected_answers for analysis + feedback. */
  scansWithAnswers?: DbScanResult[];
};

export type ResultsPackResult = {
  files: string[];
  skipped: string[];
  pendingCount: number;
};

/** Download a desk pack: scores CSV/PDF, plus analysis + feedback when a subject is selected. */
export async function downloadResultsPack(input: ResultsPackInput): Promise<ResultsPackResult> {
  const {
    scans,
    students,
    subjects,
    sectionFilter,
    subjectFilter,
    scansWithAnswers = scans,
  } = input;

  const pendingCount = scans.filter((s) => s.needs_review).length;
  const stamp = new Date().toISOString().slice(0, 10);
  const sectionPart = sectionFilter ? safeFilePart(sectionFilter) : "all";
  const subject = subjectFilter
    ? subjects.find((s) => s.local_id === subjectFilter || s.name === subjectFilter)
    : null;
  const subjectPart = subject ? safeFilePart(subject.name) : "all";
  const base = `omr_${subjectPart}_${sectionPart}_${stamp}`;

  const files: string[] = [];
  const skipped: string[] = [];

  const csvName = `${base}_scores.csv`;
  downloadText(
    exportResultsCsv(scans, students, subjects, sectionFilter, subjectFilter),
    csvName,
    "text/csv",
  );
  files.push(csvName);
  await sleep(350);

  const title = [
    "OMR Results",
    subject?.name,
    sectionFilter,
  ]
    .filter(Boolean)
    .join(" · ");
  const { bytes } = await exportResultsPdf(scans, students, subjects, title);
  const pdfName = `${base}_scores.pdf`;
  downloadBlob(new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }), pdfName);
  files.push(pdfName);

  if (!subject) {
    skipped.push("Item analysis (pick a subject)");
    skipped.push("Student feedback (pick a subject)");
    return { files, skipped, pendingCount };
  }

  const subjectScans = scansWithAnswers.filter(
    (scan) => scan.subject_local_id === subject.local_id || scan.subject_name === subject.name,
  );
  const sectionStudents = sectionFilter
    ? students.filter((s) => s.section_name === sectionFilter)
    : students;
  const sectionOmrIds = new Set(sectionStudents.map((s) => s.omr_id));
  const scopedScans = sectionFilter
    ? subjectScans.filter((scan) => sectionOmrIds.has(scan.student_omr_id))
    : subjectScans;

  const report = buildItemAnalysisReport(subject, scopedScans);
  if (!report) {
    skipped.push("Item analysis (no approved scans yet)");
    skipped.push("Student feedback (no approved scans yet)");
    return { files, skipped, pendingCount };
  }

  await sleep(350);
  const analysisCsv = `${base}_item_analysis.csv`;
  downloadText(exportItemAnalysisCsv(subject.name, report, subject), analysisCsv, "text/csv");
  files.push(analysisCsv);

  await sleep(350);
  const analysisPdfBytes = await exportItemAnalysisPdf(subject.name, report, subject);
  const analysisPdf = `${base}_item_analysis.pdf`;
  downloadBlob(
    new Blob([Uint8Array.from(analysisPdfBytes)], { type: "application/pdf" }),
    analysisPdf,
  );
  files.push(analysisPdf);

  const feedbackRows = buildStudentFeedbackRows(subject, scopedScans, sectionStudents);
  if (feedbackRows.length === 0) {
    skipped.push("Student feedback (no graded rows)");
    return { files, skipped, pendingCount };
  }

  await sleep(350);
  const feedbackBytes = await exportStudentFeedbackPdf(subject, feedbackRows, {
    sectionLabel: sectionFilter,
  });
  const feedbackPdf = `${base}_student_feedback.pdf`;
  downloadBlob(
    new Blob([Uint8Array.from(feedbackBytes)], { type: "application/pdf" }),
    feedbackPdf,
  );
  files.push(feedbackPdf);

  return { files, skipped, pendingCount };
}
