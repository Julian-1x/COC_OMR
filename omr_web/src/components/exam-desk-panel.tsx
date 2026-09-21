"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Card } from "@/components/ui/card";
import { Label, Select } from "@/components/ui/input";
import type { DbSubject } from "@/lib/types/database";
import { liveSectionsForSubject } from "@/lib/omr/answer-key-scope";
import {
  examActionLinks,
  type ExamTarget,
} from "@/lib/omr/desk-insights";

export function ExamDeskPanel({
  subjects,
  activeSectionNames,
  initialTarget,
}: {
  subjects: DbSubject[];
  activeSectionNames: string[];
  initialTarget: ExamTarget | null;
}) {
  const printable = useMemo(() => {
    return subjects
      .map((subject) => ({
        subject,
        sections: liveSectionsForSubject(subject, activeSectionNames),
      }))
      .filter((row) => row.sections.length > 0);
  }, [subjects, activeSectionNames]);

  const [subjectId, setSubjectId] = useState(
    initialTarget?.subjectLocalId ?? printable[0]?.subject.local_id ?? "",
  );
  const selected = printable.find((row) => row.subject.local_id === subjectId) ?? printable[0];
  const [sectionName, setSectionName] = useState(
    initialTarget?.sectionName ?? selected?.sections[0] ?? "",
  );

  const sectionsForSubject = selected?.sections ?? [];
  const effectiveSection =
    sectionName && sectionsForSubject.includes(sectionName)
      ? sectionName
      : sectionsForSubject[0] ?? "";

  if (printable.length === 0) {
    return (
      <Card className="border-amber-200 bg-amber-50" title="Exam desk">
        <p className="text-sm text-amber-950">
          Link an answer key to a class, then print sheets from here.
        </p>
        <div className="mt-3 flex flex-wrap gap-2">
          <Link
            href="/dashboard/prepare/answer-keys"
            className="rounded-xl bg-emerald-500 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-emerald-600"
          >
            Answer keys
          </Link>
          <Link
            href="/dashboard/prepare/import"
            className="rounded-xl border border-emerald-200 bg-white px-4 py-2.5 text-sm font-extrabold text-emerald-800 hover:bg-emerald-50"
          >
            Import roster
          </Link>
        </div>
      </Card>
    );
  }

  const target: ExamTarget = {
    subjectLocalId: selected!.subject.local_id,
    subjectName: selected!.subject.name,
    sectionName: effectiveSection,
  };
  const links = examActionLinks(target);

  return (
    <Card title="Exam desk" subtitle="Pick subject + class, then print or open results">
      <div className="grid gap-3 sm:grid-cols-2">
        <div>
          <Label htmlFor="exam-subject">Subject</Label>
          <Select
            id="exam-subject"
            value={selected!.subject.local_id}
            onChange={(e) => {
              setSubjectId(e.target.value);
              const next = printable.find((row) => row.subject.local_id === e.target.value);
              setSectionName(next?.sections[0] ?? "");
            }}
          >
            {printable.map((row) => (
              <option key={row.subject.local_id} value={row.subject.local_id}>
                {row.subject.name}
              </option>
            ))}
          </Select>
        </div>
        <div>
          <Label htmlFor="exam-section">Class</Label>
          <Select
            id="exam-section"
            value={effectiveSection}
            onChange={(e) => setSectionName(e.target.value)}
          >
            {sectionsForSubject.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </Select>
        </div>
      </div>

      <div className="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
        <Link
          href={links.print}
          className="rounded-xl bg-emerald-500 px-4 py-3 text-center text-sm font-extrabold text-white hover:bg-emerald-600"
        >
          Print sheets
        </Link>
        <Link
          href={links.omrIds}
          className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-center text-sm font-extrabold text-emerald-900 hover:bg-emerald-100"
        >
          OMR ID list
        </Link>
        <Link
          href={links.results}
          className="rounded-xl border border-slate-200 bg-white px-4 py-3 text-center text-sm font-extrabold text-slate-800 hover:border-emerald-300"
        >
          Results
        </Link>
        <Link
          href={links.analysis}
          className="rounded-xl border border-slate-200 bg-white px-4 py-3 text-center text-sm font-extrabold text-slate-800 hover:border-emerald-300"
        >
          Item analysis
        </Link>
      </div>
    </Card>
  );
}
