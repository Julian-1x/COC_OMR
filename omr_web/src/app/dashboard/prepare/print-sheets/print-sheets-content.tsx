"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { createClient } from "@/lib/supabase/client";
import { fetchSections, fetchStudents, fetchSubjects } from "@/lib/api/data";
import type { DbSubject, DbStudent } from "@/lib/types/database";
import { generateAnswerSheetPdf, generateBlankSheetsPdf } from "@/lib/pdf/answer-sheet";
import { downloadBlob } from "@/lib/utils";

export default function PrintSheetsPage() {
  const searchParams = useSearchParams();
  const [subjects, setSubjects] = useState<DbSubject[]>([]);
  const [sections, setSections] = useState<string[]>([]);
  const [students, setStudents] = useState<DbStudent[]>([]);
  const [subjectId, setSubjectId] = useState("");
  const [sectionName, setSectionName] = useState(searchParams.get("section") ?? "");
  const [copies, setCopies] = useState(1);
  const [mode, setMode] = useState<"class" | "blank">("class");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      const supabase = createClient();
      const [subjectRows, sectionRows, studentRows] = await Promise.all([
        fetchSubjects(supabase),
        fetchSections(supabase),
        fetchStudents(supabase),
      ]);
      setSubjects(subjectRows);
      const names = sectionRows.map((s) => s.name);
      setSections(names);
      setStudents(studentRows);
      const subjectParam = searchParams.get("subject") ?? "";
      const sectionParam = searchParams.get("section") ?? "";
      if (subjectParam && subjectRows.some((s) => s.local_id === subjectParam)) {
        setSubjectId(subjectParam);
      } else if (subjectRows[0]) {
        setSubjectId((prev) => prev || subjectRows[0].local_id);
      }
      if (sectionParam && names.includes(sectionParam)) {
        setSectionName(sectionParam);
      } else {
        setSectionName((prev) => prev || names[0] || "");
        if (sectionParam && !names.includes(sectionParam)) {
          setError(`Section "${sectionParam}" was not found. Choose a section below.`);
        }
      }
    }
    void load();
  }, [searchParams]);

  const subject = subjects.find((s) => s.local_id === subjectId);
  const sectionStudents = students.filter((s) => s.section_name === sectionName);

  async function downloadPdf() {
    if (!subject || !sectionName || !sections.includes(sectionName)) {
      setError("Choose a valid subject and section.");
      return;
    }
    if (mode === "class" && sectionStudents.length === 0) {
      setError("No students in this section. Import a roster or sync from your phone.");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const bytes =
        mode === "class"
          ? await generateAnswerSheetPdf(subject, sectionName, sectionStudents)
          : await generateBlankSheetsPdf(subject, sectionName, copies);
      downloadBlob(
        new Blob([Uint8Array.from(bytes)], { type: "application/pdf" }),
        `${subject.name}_${sectionName}_${mode}.pdf`,
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "PDF failed.");
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
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Print OMR sheets</h1>
        <p className="mt-1 text-sm text-slate-500">Print at 100% scale (Actual size). Do not use Fit to page.</p>
      </div>

      <Card className="max-w-xl">
        <div className="space-y-3">
          <div>
            <Label htmlFor="subject">Subject</Label>
            <Select id="subject" value={subjectId} onChange={(e) => setSubjectId(e.target.value)}>
              {subjects.map((s) => (
                <option key={s.local_id} value={s.local_id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label htmlFor="section">Section</Label>
            <Select id="section" value={sectionName} onChange={(e) => setSectionName(e.target.value)}>
              {sections.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </Select>
          </div>
          <div>
            <Label>Mode</Label>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => setMode("class")}
                className={`rounded-xl px-3 py-2 text-sm font-bold ${
                  mode === "class" ? "bg-emerald-500 text-white" : "bg-slate-100 text-slate-600"
                }`}
              >
                One per student ({sectionStudents.length})
              </button>
              <button
                type="button"
                onClick={() => setMode("blank")}
                className={`rounded-xl px-3 py-2 text-sm font-bold ${
                  mode === "blank" ? "bg-emerald-500 text-white" : "bg-slate-100 text-slate-600"
                }`}
              >
                Blank copies
              </button>
            </div>
          </div>
          {mode === "blank" ? (
            <div>
              <Label htmlFor="copies">Copies</Label>
              <Input
                id="copies"
                type="number"
                min={1}
                max={200}
                value={copies}
                onChange={(e) => setCopies(parseInt(e.target.value, 10) || 1)}
              />
            </div>
          ) : null}
          {error ? <p className="text-sm font-semibold text-red-600">{error}</p> : null}
          <Button type="button" disabled={loading || !subject} onClick={downloadPdf}>
            {loading ? "Generating…" : "Download PDF"}
          </Button>
        </div>
      </Card>
    </>
  );
}
