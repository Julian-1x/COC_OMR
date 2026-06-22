import Papa from "papaparse";
import * as XLSX from "xlsx";
import type { DbStudent, DbSubject } from "@/lib/types/database";

export type ImportRow = {
  schoolId: string;
  name: string;
  section: string;
};

export type ImportPreview = {
  rows: ImportRow[];
  errors: string[];
  duplicates: number;
  skipped: number;
};

export type ImportCommitResult = {
  imported: number;
  updated: number;
  unchanged: number;
  sections: string[];
};

/** Canonical school ID form — must match Flutter `normalizeSchoolId`. */
export function normalizeSchoolId(value: string): string {
  return value.trim().toUpperCase();
}

function normalizeHeader(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function readCell(cell: unknown): string {
  if (cell == null) return "";
  return String(cell).trim();
}

const schoolIdHeaderKeys = [
  "student id",
  "school id",
  "student number",
  "student no",
  "lrn",
  "id number",
  "id",
];

const nameHeaderKeys = ["name", "student name", "full name", "learner name"];
const firstNameHeaderKeys = ["first name", "firstname", "given name"];
const lastNameHeaderKeys = ["last name", "lastname", "surname", "family name"];
const sectionHeaderKeys = [
  "section",
  "section name",
  "class",
  "class section",
  "year and section",
  "block",
  "strand",
];

function headerHasMatch(header: string[], keys: string[]): boolean {
  for (const key of keys) {
    if (header.includes(key)) return true;
    if (header.some((cell) => cell.includes(key))) return true;
  }
  return false;
}

function detectHeaderRow(rows: unknown[][]): number {
  let bestIndex = -1;
  let bestScore = 0;
  for (let i = 0; i < Math.min(rows.length, 8); i++) {
    const header = rows[i].map((c) => normalizeHeader(readCell(c)));
    let score = 0;
    if (headerHasMatch(header, schoolIdHeaderKeys)) score++;
    if (
      headerHasMatch(header, nameHeaderKeys) ||
      (headerHasMatch(header, firstNameHeaderKeys) &&
        headerHasMatch(header, lastNameHeaderKeys))
    ) {
      score++;
    }
    if (headerHasMatch(header, sectionHeaderKeys)) score++;
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }
  return bestScore >= 2 ? bestIndex : rows.length > 0 ? 0 : -1;
}

function mapHeaders(header: string[]): Record<string, number> {
  const find = (keys: string[]) => {
    for (const key of keys) {
      const exact = header.indexOf(key);
      if (exact !== -1) return exact;
    }
    for (let i = 0; i < header.length; i++) {
      const cell = header[i];
      if (!cell) continue;
      for (const key of keys) {
        if (cell === key || cell.includes(key)) return i;
      }
    }
    return -1;
  };
  return {
    schoolId: find(schoolIdHeaderKeys),
    name: find(nameHeaderKeys),
    firstName: find(firstNameHeaderKeys),
    lastName: find(lastNameHeaderKeys),
    section: find(sectionHeaderKeys),
  };
}

export function parseCsvText(text: string): unknown[][] {
  const result = Papa.parse<unknown[]>(text, { skipEmptyLines: true });
  return result.data;
}

export function parseXlsxBuffer(buffer: ArrayBuffer): unknown[][] {
  const workbook = XLSX.read(buffer, { type: "array" });
  const sheetName = workbook.SheetNames[0];
  const sheet = workbook.Sheets[sheetName];
  return XLSX.utils.sheet_to_json(sheet, { header: 1, defval: "" }) as unknown[][];
}

export function previewImportRows(rawRows: unknown[][]): ImportPreview {
  const errors: string[] = [];
  const rows: ImportRow[] = [];
  let duplicates = 0;
  let skipped = 0;

  if (rawRows.length === 0) {
    return { rows, errors: ["File is empty."], duplicates, skipped };
  }

  const headerIndex = detectHeaderRow(rawRows);
  if (headerIndex === -1) {
    return { rows, errors: ["Could not find a header row."], duplicates, skipped };
  }

  const header = rawRows[headerIndex].map((c) => normalizeHeader(readCell(c)));
  const cols = mapHeaders(header);

  const schoolIdIdx = cols.schoolId !== -1 ? cols.schoolId : 0;
  const sectionIdx = cols.section !== -1 ? cols.section : 2;
  const nameIdx =
    cols.name !== -1
      ? cols.name
      : cols.firstName !== -1 && cols.lastName !== -1
        ? -2
        : 1;

  const seen = new Set<string>();

  for (let i = headerIndex + 1; i < rawRows.length; i++) {
    const row = rawRows[i];
    if (!row || row.every((c) => readCell(c) === "")) continue;

    const schoolId = readCell(row[schoolIdIdx]);
    const section = readCell(row[sectionIdx]);
    let name = "";
    if (nameIdx === -2) {
      name = `${readCell(row[cols.firstName])} ${readCell(row[cols.lastName])}`.trim();
    } else {
      name = readCell(row[nameIdx]);
    }

    if (!schoolId || !name) {
      skipped++;
      continue;
    }

    const resolvedSection = section.trim() || "UNASSIGNED";

    const key = normalizeSchoolId(schoolId);
    if (seen.has(key)) {
      duplicates++;
      continue;
    }
    seen.add(key);

    rows.push({ schoolId, name, section: resolvedSection });
  }

  if (rows.length === 0 && errors.length === 0) {
    errors.push("No valid student rows found. Check column headers.");
  }

  return { rows, errors, duplicates, skipped };
}

export function nextOmrId(existing: DbStudent[], reserved: Set<string>): string {
  const used = new Set([
    ...existing.map((s) => s.omr_id),
    ...reserved,
  ]);
  for (let n = 1; n <= 9999; n++) {
    const id = n.toString().padStart(4, "0");
    if (!used.has(id)) return id;
  }
  throw new Error("No available OMR IDs remaining.");
}

export function buildImportPlan(
  preview: ImportRow[],
  existing: DbStudent[],
): { toUpsert: Array<ImportRow & { omrId: string; isNew: boolean }>; unchanged: number } {
  const bySchoolId = new Map(
    existing.map((s) => [normalizeSchoolId(s.school_id), s]),
  );
  const reserved = new Set<string>();
  const toUpsert: Array<ImportRow & { omrId: string; isNew: boolean }> = [];
  let unchanged = 0;

  for (const row of preview) {
    const match = bySchoolId.get(normalizeSchoolId(row.schoolId));
    if (
      match &&
      match.name === row.name &&
      match.section_name === row.section
    ) {
      unchanged++;
      continue;
    }

    const omrId = match?.omr_id ?? nextOmrId(existing, reserved);
    reserved.add(omrId);
    toUpsert.push({ ...row, omrId, isNew: !match });
  }

  return { toUpsert, unchanged };
}

export function generateSubjectLocalId(existing: DbSubject[]): string {
  const nums = existing
    .map((s) => s.local_id.match(/SUB-(\d+)/)?.[1])
    .filter(Boolean)
    .map((n) => parseInt(n!, 10));
  const next = (nums.length ? Math.max(...nums) : 0) + 1;
  return `SUB-${next.toString().padStart(4, "0")}`;
}

export function generateSheetId(): string {
  return `SHEET-${Date.now().toString().slice(-6)}`;
}
