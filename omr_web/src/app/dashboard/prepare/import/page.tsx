"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { PageSkeleton } from "@/components/page-skeleton";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Label } from "@/components/ui/input";
import { commitRosterImport } from "@/lib/actions/roster";
import { previewImportRows, parseCsvText, parseXlsxBuffer } from "@/lib/import/roster";
import { downloadText } from "@/lib/utils";

export default function ImportRosterPage() {
  const router = useRouter();
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [previewCount, setPreviewCount] = useState(0);
  const [pendingRows, setPendingRows] = useState<ReturnType<typeof previewImportRows> | null>(null);

  async function handleFile(file: File) {
    setError(null);
    setMessage(null);
    const ext = file.name.split(".").pop()?.toLowerCase();
    let raw: unknown[][] = [];
    if (ext === "csv") {
      raw = parseCsvText(await file.text());
    } else if (ext === "xlsx") {
      raw = parseXlsxBuffer(await file.arrayBuffer());
    } else {
      setError("Use a .csv or .xlsx file.");
      return;
    }
    const preview = previewImportRows(raw);
    setPendingRows(preview);
    setPreviewCount(preview.rows.length);
    if (preview.errors.length) setError(preview.errors.join(" "));
  }

  async function commitImport() {
    if (!pendingRows) return;
    setLoading(true);
    setError(null);
    try {
      const result = await commitRosterImport(pendingRows.rows);
      setMessage(
        `Imported ${result.newCount} new, updated ${result.updatedCount}, unchanged ${result.unchanged}. Sync your phone to pull these changes.`,
      );
      setPendingRows(null);
      setPreviewCount(0);
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
        <p className="mt-1 text-sm text-slate-500">CSV or Excel with Student ID, Name, and Section columns.</p>
      </div>

      <Card>
        <Label htmlFor="roster">Roster file</Label>
        <input
          id="roster"
          type="file"
          accept=".csv,.xlsx"
          className="mt-2 block w-full text-sm"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void handleFile(file);
          }}
        />
        {previewCount > 0 ? (
          <p className="mt-3 text-sm font-semibold text-slate-700">{previewCount} students ready to import.</p>
        ) : null}
        {error ? <p className="mt-3 text-sm font-semibold text-red-600">{error}</p> : null}
        {message ? <p className="mt-3 text-sm font-semibold text-emerald-700">{message}</p> : null}
        <div className="mt-4 flex gap-2">
          <Button type="button" disabled={!pendingRows || loading} onClick={() => void commitImport()}>
            {loading ? "Importing…" : "Commit import"}
          </Button>
          <Button
            type="button"
            variant="secondary"
            onClick={() =>
              downloadText(
                "Student ID,Name,Section\n2024-001,Juan Dela Cruz,BSIT-1A\n2024-002,Maria Santos,BSIT-1A",
                "roster_template.csv",
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
