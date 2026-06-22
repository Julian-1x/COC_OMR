"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { formatDistanceToNow } from "date-fns";
import { BookOpen, Hash, Printer, FileSpreadsheet, Smartphone } from "lucide-react";
import { Card, StatCard } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { EmptyState } from "@/components/dashboard-shell";
import { ExpandableClassCard } from "@/components/expandable-class-card";
import type { DbSubject } from "@/lib/types/database";
import { formatPassingLabel } from "@/lib/omr/passing-score";
import {
  classRosterHref,
  omrIdsHref,
  printSheetsHref,
  sectionPrintSheetsHref,
} from "@/lib/prepare-links";

export type PrepareSection = {
  name: string;
  studentCount: number;
  rosterPending: boolean;
};

type PrepareContentProps = {
  sections: PrepareSection[];
  studentCount: number;
  subjects: DbSubject[];
  lastUpdated: string | null;
};

export function PrepareContent({
  sections,
  studentCount,
  subjects,
  lastUpdated,
}: PrepareContentProps) {
  const [sectionQuery, setSectionQuery] = useState("");
  const [keyQuery, setKeyQuery] = useState("");
  const [expandedSection, setExpandedSection] = useState<string | null>(null);

  const filteredSections = useMemo(() => {
    const q = sectionQuery.trim().toLowerCase();
    if (!q) return sections;
    return sections.filter((s) => s.name.toLowerCase().includes(q));
  }, [sections, sectionQuery]);

  const filteredSubjects = useMemo(() => {
    const q = keyQuery.trim().toLowerCase();
    if (!q) return subjects;
    return subjects.filter(
      (s) =>
        s.name.toLowerCase().includes(q) ||
        (s.section_names ?? []).some((name) => name.toLowerCase().includes(q)),
    );
  }, [subjects, keyQuery]);

  const hasStudents = studentCount > 0;
  const hasAnyData = hasStudents || subjects.length > 0 || sections.length > 0;
  const lastSyncLabel = lastUpdated
    ? formatDistanceToNow(new Date(lastUpdated), { addSuffix: true })
    : null;

  return (
    <>
      <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-slate-800">Prepare</h1>
          <p className="mt-1 text-sm text-slate-500">
            Answer keys, OMR IDs, and printable sheets — from your phone after sync, or built here.
          </p>
          {lastSyncLabel && hasAnyData ? (
            <p className="mt-1 text-xs text-slate-400">Phone data last updated {lastSyncLabel}</p>
          ) : null}
        </div>
        <Link
          href="/dashboard/prepare/import"
          className="inline-flex items-center gap-2 rounded-2xl bg-emerald-500 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-emerald-600"
        >
          <FileSpreadsheet className="h-4 w-4" />
          Import roster
        </Link>
      </div>

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <StatCard label="Classes" value={sections.length} />
        <StatCard label="Students" value={studentCount} />
        <StatCard label="Answer keys" value={subjects.length} />
      </div>

      {!hasAnyData ? (
        <Card className="mb-6 border-amber-200 bg-amber-50">
          <div className="flex items-start gap-3">
            <Smartphone className="mt-0.5 h-5 w-5 shrink-0 text-amber-800" />
            <p className="text-sm leading-relaxed text-amber-900">
              Nothing here yet. If you already set up classes on your phone, open the app →{" "}
              <strong>Settings</strong> → <strong>Sync Now</strong> on Wi‑Fi, then refresh this page.
              Or{" "}
              <Link href="/dashboard/prepare/import" className="font-bold underline">
                import a roster
              </Link>{" "}
              here instead.
            </p>
          </div>
        </Card>
      ) : (
        <Card className="mb-6 border-emerald-200 bg-emerald-50/80">
          <div className="flex items-start gap-3">
            <Smartphone className="mt-0.5 h-5 w-5 shrink-0 text-emerald-700" />
            <p className="text-sm leading-relaxed text-emerald-900">
              This is your <strong>synced</strong> exam setup — same data as your phone after{" "}
              <strong>Sync Now</strong>. Print OMR IDs and sheets by class below. Changes here or on
              the phone need another sync to stay matched.
            </p>
          </div>
        </Card>
      )}

      <Card title="Answer keys" subtitle="From your phone sync or created on this desk" className="mb-6">
        {subjects.length > 3 ? (
          <div className="mb-3 max-w-md">
            <Input
              value={keyQuery}
              onChange={(e) => setKeyQuery(e.target.value)}
              placeholder="Search answer keys or sections…"
              aria-label="Search answer keys"
            />
          </div>
        ) : null}

        {subjects.length === 0 ? (
          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-slate-500">Create a subject before printing exam sheets.</p>
            <Link
              href="/dashboard/prepare/answer-keys/new"
              className="rounded-xl bg-emerald-500 px-3 py-2 text-sm font-bold text-white hover:bg-emerald-600"
            >
              New answer key
            </Link>
          </div>
        ) : filteredSubjects.length === 0 ? (
          <p className="text-sm text-slate-500">No answer keys match your search.</p>
        ) : (
          <div className="max-h-80 overflow-y-auto rounded-xl border border-slate-100">
            <table className="min-w-full text-sm">
              <thead className="sticky top-0 bg-white">
                <tr className="border-b text-xs font-bold uppercase text-slate-500">
                  <th className="px-3 py-2 text-left">Subject</th>
                  <th className="px-3 py-2 text-left">Items</th>
                  <th className="px-3 py-2 text-left">Pass</th>
                  <th className="px-3 py-2 text-left">Sections</th>
                  <th className="px-3 py-2 text-left" />
                </tr>
              </thead>
              <tbody>
                {filteredSubjects.map((subject) => {
                  const sectionList = subject.section_names ?? [];
                  return (
                    <tr key={subject.id} className="border-b border-slate-50 align-top">
                      <td className="px-3 py-2.5 font-semibold text-slate-800">{subject.name}</td>
                      <td className="px-3 py-2.5 text-slate-600">{subject.total_questions}</td>
                      <td className="px-3 py-2.5 text-xs text-slate-500">
                        {formatPassingLabel(subject.passing_score, subject.total_questions)}
                      </td>
                      <td className="px-3 py-2.5">
                        {sectionList.length === 0 ? (
                          <span className="text-xs text-amber-700">No sections assigned</span>
                        ) : (
                          <div className="flex max-w-xs flex-wrap gap-1">
                            {sectionList.map((section) => (
                              <span
                                key={section}
                                className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-600"
                              >
                                {section}
                              </span>
                            ))}
                          </div>
                        )}
                      </td>
                      <td className="px-3 py-2.5">
                        <div className="flex flex-wrap justify-end gap-1">
                          <Link
                            href={`/dashboard/prepare/answer-keys/${encodeURIComponent(subject.local_id)}`}
                            className="rounded-lg bg-emerald-50 px-2 py-1 text-xs font-bold text-emerald-800 hover:bg-emerald-100"
                          >
                            Edit
                          </Link>
                          {sectionList[0] ? (
                            <Link
                              href={printSheetsHref(subject.local_id, sectionList[0])}
                              className="inline-flex items-center gap-1 rounded-lg bg-slate-100 px-2 py-1 text-xs font-bold text-slate-700 hover:bg-slate-200"
                            >
                              <Printer className="h-3 w-3" />
                              Print
                            </Link>
                          ) : null}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        <div className="mt-3 flex flex-wrap gap-2">
          <Link
            href="/dashboard/prepare/answer-keys"
            className="text-sm font-bold text-emerald-700 hover:underline"
          >
            Manage all answer keys →
          </Link>
          <Link
            href="/dashboard/prepare/answer-keys/new"
            className="text-sm font-bold text-emerald-700 hover:underline"
          >
            New answer key
          </Link>
        </div>
      </Card>

      <Card
        title="By class"
        subtitle="Tap a class card to open OMR IDs, print sheets, and quick actions"
        className="mb-6"
      >
        {sections.length > 4 ? (
          <div className="mb-3 max-w-md">
            <Input
              value={sectionQuery}
              onChange={(e) => setSectionQuery(e.target.value)}
              placeholder="Search classes…"
              aria-label="Search classes"
            />
          </div>
        ) : null}

        {sections.length === 0 ? (
          <EmptyState
            title="No classes yet"
            body="Sync from your phone (Settings → Sync Now) or import a roster."
          />
        ) : filteredSections.length === 0 ? (
          <p className="text-sm text-slate-500">No classes match your search.</p>
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {filteredSections.map((section) => (
              <ExpandableClassCard
                key={section.name}
                section={section}
                isOpen={expandedSection === section.name}
                onToggle={() =>
                  setExpandedSection((current) =>
                    current === section.name ? null : section.name,
                  )
                }
              >
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <Link
                    href={classRosterHref(section.name)}
                    className="text-xs font-bold text-emerald-700 hover:underline"
                  >
                    View roster
                  </Link>
                </div>

                <div className="mt-3 flex flex-wrap gap-2">
                  <Link
                    href={omrIdsHref(section.name)}
                    className="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-bold text-slate-700 hover:border-emerald-300 hover:text-emerald-800"
                  >
                    <Hash className="h-3.5 w-3.5" />
                    OMR IDs
                  </Link>
                  <Link
                    href={sectionPrintSheetsHref(section.name)}
                    className="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-bold text-slate-700 hover:border-emerald-300 hover:text-emerald-800"
                  >
                    <Printer className="h-3.5 w-3.5" />
                    Print sheets
                  </Link>
                </div>

                {subjects.length > 0 ? (
                  <div className="mt-3 border-t border-slate-100 pt-3">
                    <p className="text-xs font-bold uppercase tracking-wide text-slate-400">
                      Quick print
                    </p>
                    <div className="mt-1.5 flex flex-wrap gap-1">
                      {subjects
                        .filter((s) => (s.section_names ?? []).includes(section.name))
                        .slice(0, 4)
                        .map((subject) => (
                          <Link
                            key={subject.local_id}
                            href={printSheetsHref(subject.local_id, section.name)}
                            className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-800 hover:bg-emerald-100"
                          >
                            <BookOpen className="h-3 w-3" />
                            {subject.name}
                          </Link>
                        ))}
                      {subjects.filter((s) => (s.section_names ?? []).includes(section.name))
                        .length === 0 ? (
                        <span className="text-xs text-slate-400">No keys for this class</span>
                      ) : null}
                    </div>
                  </div>
                ) : null}
              </ExpandableClassCard>
            ))}
          </div>
        )}
      </Card>
    </>
  );
}
