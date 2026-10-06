"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { FileUp } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Label } from "@/components/ui/input";
import { commitRosterImport } from "@/lib/actions/roster";
import {
  previewImportRows,
  parseCsvText,
  parseXlsxBuffer,
  type ImportPreview,
} from "@/lib/import/roster";
import {
  commonTermLabels,
  defaultTermLabel,
  schoolYearForDate,
  schoolYearOptions,
} from "@/lib/academic-term";
import { downloadText } from "@/lib/utils";
import { SyncLoopNotice } from "@/components/desk-notices";
import {
  clearSessionKey,
  readJsonPref,
  readSessionJson,
  writeJsonPref,
  writeSessionJson,
} from "@/lib/ui-prefs";

const IMPORT_PREFS_KEY = "coc-omr-import-prefs-v1";
const IMPORT_DRAFT_KEY = "coc-omr-import-draft-v1";

type ImportPrefs = {
  schoolYear?: string;
  termLabel?: string;
};

type ImportDraft = {
  fileName?: string | null;
  preview?: ImportPreview | null;
};

export default function ImportRosterPage() {
  const router = useRouter();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [previewCount, setPreviewCount] = useState(0);
  const [fileName, setFileName] = useState<string | null>(null);
  const [pendingRows, setPendingRows] = useState<ImportPreview | null>(null);
  const [schoolYear, setSchoolYear] = useState(schoolYearForDate());
  const [termLabel, setTermLabel] = useState(defaultTermLabel());
  const [hydrated, setHydrated] = useState(false);
  const yearOptions = schoolYearOptions();

  useEffect(() => {
    const prefs = readJsonPref<ImportPrefs>(IMPORT_PREFS_KEY);
    if (prefs?.schoolYear) setSchoolYear(prefs.schoolYear);
    if (prefs?.termLabel) setTermLabel(prefs.termLabel);

    const draft = readSessionJson<ImportDraft>(IMPORT_DRAFT_KEY);
    if (draft?.preview?.rows?.length) {
      setPendingRows(draft.preview);
      setPreviewCount(draft.preview.rows.length);
      setFileName(draft.fileName ?? "Restored preview");
      setMessage(
        `Restored unfinished import preview (${draft.preview.rows.length} students). Commit or choose a new file.`,
      );
    }
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    writeJsonPref(IMPORT_PREFS_KEY, { schoolYear, termLabel });
  }, [schoolYear, termLabel, hydrated]);

  useEffect(() => {
    if (!hydrated) return;
    if (!pendingRows?.rows?.length) {
      clearSessionKey(IMPORT_DRAFT_KEY);
      return;
    }
    writeSessionJson(IMPORT_DRAFT_KEY, {
      fileName,
      preview: pendingRows,
    } satisfies ImportDraft);
  }, [pendingRows, fileName, hydrated]);

  async function handleFile(file: File) {
    setError(null);
    setMessage(null);
    setFileName(file.name);
    const ext = file.name.split(".").pop()?.toLowerCase();
    let raw: unknown[][] = [];
    if (ext === "csv") {
      raw = parseCsvText(await file.text());
    } else if (ext === "xlsx") {
      raw = parseXlsxBuffer(await file.arrayBuffer());
    } else {
      setPendingRows(null);
      setPreviewCount(0);
      setError("Use a .csv or .xlsx file.");
      return;
    }
    const preview = previewImportRows(raw);
    setPreviewCount(preview.rows.length);
    if (preview.rows.length === 0) {
      setPendingRows(null);
      setError(
        preview.errors.length
          ? preview.errors.join(" ")
          : "No students found. Use a Class List Report with Student ID, Student Name, and Section.",
      );
      return;
    }
    setPendingRows(preview);
    if (preview.errors.length) setError(preview.errors.join(" "));
  }

  async function commitImport() {
    if (!pendingRows) return;
    setLoading(true);
    setError(null);
    try {
      const result = await commitRosterImport(pendingRows.rows, { schoolYear, termLabel });
      setMessage(
        `Imported ${result.newCount} new, updated ${result.updatedCount}, unchanged ${result.unchanged}. Sync your phone to pull these changes.`,
      );
      setPendingRows(null);
      setPreviewCount(0);
      setFileName(null);
      clearSessionKey(IMPORT_DRAFT_KEY);
      if (fileInputRef.current) fileInputRef.current.value = "";
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Import failed.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <div className="mb-4">
        <Link href="/dashboard/prepare" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Prepare
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Import roster</h1>
        <p className="mt-1 text-sm text-slate-500">
          Class List Report (.xlsx) — needs Student ID, Student Name, and Section.
        </p>
      </div>

      <SyncLoopNotice className="mb-4" />

      <Card>
        <div className="mb-4 grid gap-3 sm:grid-cols-2">
          <div>
            <Label htmlFor="school-year">School year</Label>
            <select
              id="school-year"
              value={schoolYear}
              onChange={(e) => setSchoolYear(e.target.value)}
              className="mt-2 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700"
            >
              {yearOptions.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </div>
          <div>
            <Label htmlFor="term">Semester</Label>
            <select
              id="term"
              value={termLabel}
              onChange={(e) => setTermLabel(e.target.value)}
              className="mt-2 w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700"
            >
              {commonTermLabels.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </div>
        </div>
        <p className="mb-4 text-xs font-medium text-slate-500">
          Each school year has 1st Sem and 2nd Sem (Summer optional). New sections from this
          import are tagged with the year and semester you pick. Year and semester are remembered
          for next time.
        </p>
        <Label htmlFor="roster">Roster file</Label>
        <input
          id="roster"
          ref={fileInputRef}
          type="file"
          accept=".csv,.xlsx"
          className="sr-only"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void handleFile(file);
          }}
        />
        <div className="mt-2 flex flex-wrap items-center gap-3">
          <Button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            disabled={loading}
          >
            <FileUp className="h-4 w-4" />
            Choose roster file
          </Button>
          <span className="text-sm font-semibold text-slate-600">
            {fileName ?? "No file chosen yet (.xlsx or .csv)"}
          </span>
        </div>
        {error ? <p className="mt-3 text-sm font-semibold text-red-600">{error}</p> : null}
        {message ? <p className="mt-3 text-sm font-semibold text-emerald-700">{message}</p> : null}
        <div className="mt-4 flex flex-wrap gap-2">
          <Button
            type="button"
            disabled={!pendingRows || previewCount < 1 || loading}
            onClick={() => void commitImport()}
          >
            {loading
              ? "Importing…"
              : previewCount > 0
                ? `Commit import (${previewCount})`
                : "Commit import"}
          </Button>
          {pendingRows ? (
            <Button
              type="button"
              variant="secondary"
              disabled={loading}
              onClick={() => {
                setPendingRows(null);
                setPreviewCount(0);
                setFileName(null);
                setMessage(null);
                clearSessionKey(IMPORT_DRAFT_KEY);
                if (fileInputRef.current) fileInputRef.current.value = "";
              }}
            >
              Clear preview
            </Button>
          ) : null}
          <Button
            type="button"
            variant="secondary"
            onClick={() =>
              downloadText(
                [
                  "SESSION NAME,CAMPUS,STUDENT ID,STUDENT NAME,GENDER,COLLEGE,COURSE,SUBJECT,SECTION,EMAIL",
                  "SY 26-27 SEM I,Carmen Campus,02-2024-12345,Juan Dela Cruz,Male,CIT,BSIT,ITE 101,BSIT-1A,juan@example.com",
                  "SY 26-27 SEM I,Carmen Campus,02-2024-12346,Maria Santos,Female,CIT,BSIT,ITE 101,BSIT-1A,maria@example.com",
                ].join("\n"),
                "class_list_report_template.csv",
                "text/csv",
              )
            }
          >
            Download template
          </Button>
        </div>
      </Card>
    </>
  );
}
