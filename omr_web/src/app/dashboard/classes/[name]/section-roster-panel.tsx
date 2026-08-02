"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label } from "@/components/ui/input";
import { removeStudent, saveStudent } from "@/lib/actions/students";
import { exportSectionRosterCsv } from "@/lib/pdf/exports";
import { downloadText } from "@/lib/utils";
import type { DbStudent } from "@/lib/types/database";

export function SectionRosterPanel({
  sectionName,
  students,
}: {
  sectionName: string;
  students: DbStudent[];
}) {
  const router = useRouter();
  const [schoolId, setSchoolId] = useState("");
  const [name, setName] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const filteredStudents = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return students;
    return students.filter(
      (student) =>
        student.name.toLowerCase().includes(q) ||
        student.school_id.toLowerCase().includes(q) ||
        student.omr_id.includes(q),
    );
  }, [students, searchQuery]);

  async function addStudent(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      await saveStudent({
        school_id: schoolId,
        name,
        section_name: sectionName,
      });
      setSchoolId("");
      setName("");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save student.");
    } finally {
      setLoading(false);
    }
  }

  async function deleteStudentRow(omrId: string) {
    if (!confirm(`Remove student OMR ${omrId} from ${sectionName}?`)) return;
    setError(null);
    try {
      await removeStudent(omrId, sectionName);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not remove student.");
    }
  }

  function exportRoster() {
    downloadText(exportSectionRosterCsv(students, sectionName), `${sectionName}_roster.csv`, "text/csv");
  }

  return (
    <>
      <div className="mb-4 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={exportRoster}
          className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700"
        >
          Export roster CSV
        </button>
      </div>

      <Card title="Add student" className="mb-4">
        <form className="grid gap-3 md:grid-cols-3" onSubmit={(e) => void addStudent(e)}>
          <div>
            <Label htmlFor="schoolId">Student ID</Label>
            <Input id="schoolId" value={schoolId} onChange={(e) => setSchoolId(e.target.value)} required />
          </div>
          <div>
            <Label htmlFor="studentName">Name</Label>
            <Input id="studentName" value={name} onChange={(e) => setName(e.target.value)} required />
          </div>
          <div className="flex items-end">
            <Button type="submit" disabled={loading}>
              {loading ? "Saving…" : "Add"}
            </Button>
          </div>
        </form>
        {error ? <p className="mt-2 text-sm font-semibold text-red-600">{error}</p> : null}
      </Card>

      <Card>
        {students.length > 0 ? (
          <div className="mb-4 max-w-md">
            <Label htmlFor="rosterSearch">Search students</Label>
            <Input
              id="rosterSearch"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Name, student ID, or OMR ID…"
              aria-label="Search students in roster"
            />
            <p className="mt-1 text-xs font-semibold text-slate-500">
              Showing {filteredStudents.length} of {students.length}
            </p>
          </div>
        ) : null}
        <div className="overflow-x-auto">
          <table className="min-w-full text-left text-sm">
            <thead>
              <tr className="border-b border-slate-200 text-xs font-bold uppercase tracking-wide text-slate-500">
                <th className="px-2 py-2">OMR ID</th>
                <th className="px-2 py-2">Student ID</th>
                <th className="px-2 py-2">Name</th>
                <th className="px-2 py-2" />
              </tr>
            </thead>
            <tbody>
              {filteredStudents.length === 0 ? (
                <tr>
                  <td colSpan={4} className="px-2 py-6 text-center text-sm text-slate-500">
                    {students.length === 0
                      ? "No students yet — add one above or import a roster."
                      : `No students match "${searchQuery.trim()}".`}
                  </td>
                </tr>
              ) : (
                filteredStudents.map((student) => (
                  <tr key={student.id} className="border-b border-slate-100">
                    <td className="px-2 py-2 font-mono font-bold text-emerald-800">{student.omr_id}</td>
                    <td className="px-2 py-2">{student.school_id}</td>
                    <td className="px-2 py-2 font-semibold text-slate-800">{student.name}</td>
                    <td className="px-2 py-2 text-right">
                      <button
                        type="button"
                        onClick={() => void deleteStudentRow(student.omr_id)}
                        className="text-xs font-bold text-red-600 hover:underline"
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  );
}
