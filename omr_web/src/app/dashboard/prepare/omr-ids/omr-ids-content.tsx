"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { createClient } from "@/lib/supabase/client";
import { fetchSections, fetchStudents } from "@/lib/api/data";
import type { DbStudent } from "@/lib/types/database";
import { exportOmrIdsCsv, exportOmrIdsPdf } from "@/lib/pdf/exports";
import { downloadBlob, downloadText } from "@/lib/utils";

export default function OmrIdsPage() {
  const searchParams = useSearchParams();
  const [sections, setSections] = useState<string[]>([]);
  const [students, setStudents] = useState<DbStudent[]>([]);
  const [sectionName, setSectionName] = useState(searchParams.get("section") ?? "");
  const [studentQuery, setStudentQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pdfNote, setPdfNote] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      const supabase = createClient();
      const [sectionRows, studentRows] = await Promise.all([
        fetchSections(supabase),
        fetchStudents(supabase),
      ]);
      const names = sectionRows.map((s) => s.name);
      setSections(names);
      setStudents(studentRows);
      const param = searchParams.get("section") ?? "";
      if (param && names.includes(param)) {
        setSectionName(param);
      } else {
        setSectionName((prev) => prev || names[0] || "");
        if (param && !names.includes(param)) {
          setError(`Section "${param}" was not found. Choose a section below.`);
        }
      }
    }
    void load();
  }, [searchParams]);

  async function downloadPdf() {
    if (!sectionName || !sections.includes(sectionName)) {
      setError("Choose a valid section.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const { bytes, truncated, total } = await exportOmrIdsPdf(students, sectionName);
      downloadBlob(
        new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }),
        `omr_ids_${sectionName}.pdf`,
      );
      setPdfNote(
        truncated ? `PDF shows first 50 of ${total} students. Use CSV for the full list.` : null,
      );
    } finally {
      setLoading(false);
    }
  }

  function downloadCsv() {
    if (!sectionName || !sections.includes(sectionName)) {
      setError("Choose a valid section.");
      return;
    }
    downloadText(exportOmrIdsCsv(students, sectionName), `omr_ids_${sectionName}.csv`, "text/csv");
  }

  const filtered = students
    .filter((s) => s.section_name === sectionName)
    .filter((s) => {
      const q = studentQuery.trim().toLowerCase();
      if (!q) return true;
      return (
        s.name.toLowerCase().includes(q) ||
        s.omr_id.includes(q) ||
        s.school_id.toLowerCase().includes(q)
      );
    })
    .sort((a, b) => a.omr_id.localeCompare(b.omr_id));

  const sectionTotal = students.filter((s) => s.section_name === sectionName).length;

  return (
    <>
      <div className="mb-4">
        <Link href="/dashboard/prepare" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Prepare
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">OMR ID handouts</h1>
        <p className="mt-1 text-sm text-slate-500">
          Students synced from your phone — search or download the full list per section.
        </p>
      </div>

      <Card className="mb-4 max-w-xl">
        <Label htmlFor="section">Section</Label>
        <Select id="section" value={sectionName} onChange={(e) => setSectionName(e.target.value)}>
          {sections.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
        <div className="mt-4 flex gap-2">
          <Button type="button" disabled={loading || !sectionName} onClick={downloadPdf}>
            Download PDF
          </Button>
          <Button type="button" variant="secondary" disabled={!sectionName} onClick={downloadCsv}>
            Download CSV
          </Button>
        </div>
        {error ? <p className="mt-3 text-sm font-semibold text-red-600">{error}</p> : null}
        {pdfNote ? <p className="mt-3 text-xs font-semibold text-amber-700">{pdfNote}</p> : null}
      </Card>

      {sectionTotal > 8 ? (
        <div className="mb-3 max-w-md">
          <Input
            value={studentQuery}
            onChange={(e) => setStudentQuery(e.target.value)}
            placeholder="Search name, OMR ID, or student ID…"
            aria-label="Search students"
          />
        </div>
      ) : null}

      <Card title={`${sectionTotal} students in ${sectionName || "this class"}`}>
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead>
              <tr className="border-b text-xs font-bold uppercase text-slate-500">
                <th className="px-2 py-2 text-left">OMR ID</th>
                <th className="px-2 py-2 text-left">Name</th>
                <th className="px-2 py-2 text-left">Student ID</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((s) => (
                <tr key={s.id} className="border-b border-slate-100">
                  <td className="px-2 py-2 font-mono font-bold text-emerald-800">{s.omr_id}</td>
                  <td className="px-2 py-2 font-semibold">{s.name}</td>
                  <td className="px-2 py-2">{s.school_id}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  );
}
