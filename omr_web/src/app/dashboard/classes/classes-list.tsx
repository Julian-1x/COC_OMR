"use client";

import Link from "next/link";
import { useMemo, useState, useTransition } from "react";
import { Archive, Hash, Printer, RotateCcw, Trash2, Users } from "lucide-react";
import {
  ExpandableClassCard,
  type ExpandableClassSection,
} from "@/components/expandable-class-card";
import {
  classRosterHref,
  omrIdsHref,
  sectionPrintSheetsHref,
} from "@/lib/prepare-links";
import { formatSectionTerm, termGroupKey, termGroupOrder } from "@/lib/academic-term";
import {
  archiveSectionAction,
  permanentlyDeleteSectionAction,
  restoreSection,
} from "@/lib/actions/sections";
import { archiveRetentionLabel } from "@/lib/archive-retention";

export type ClassListItem = {
  id: string;
  name: string;
  count: number;
  rosterPending: boolean;
  schoolYear?: string | null;
  termLabel?: string | null;
  archivedAt?: string | null;
};

export function ClassesList({
  sections,
  archived = false,
  groupByTerm = false,
}: {
  sections: ClassListItem[];
  archived?: boolean;
  /** When true, show 1st Sem / 2nd Sem headings (school year already filtered). */
  groupByTerm?: boolean;
}) {
  const [expandedId, setExpandedId] = useState<string | null>(null);

  function toggleSection(id: string) {
    setExpandedId((current) => (current === id ? null : id));
  }

  const groups = useMemo(() => {
    if (!groupByTerm) {
      return [{ key: "", label: null as string | null, items: sections }];
    }
    const map = new Map<string, ClassListItem[]>();
    for (const section of sections) {
      const key = termGroupKey(section.termLabel);
      const list = map.get(key) ?? [];
      list.push(section);
      map.set(key, list);
    }
    const orderedKeys = [
      ...termGroupOrder.filter((key) => map.has(key)),
      ...[...map.keys()].filter((key) => !termGroupOrder.includes(key)).sort(),
    ];
    return orderedKeys.map((key) => ({
      key,
      label: key,
      items: map.get(key) ?? [],
    }));
  }, [groupByTerm, sections]);

  return (
    <div className="space-y-8">
      {groups.map((group) => (
        <div key={group.key || "all"}>
          {group.label ? (
            <h2 className="mb-3 text-sm font-extrabold uppercase tracking-wide text-slate-500">
              {group.label}
              <span className="ml-2 font-semibold normal-case text-slate-400">
                ({group.items.length})
              </span>
            </h2>
          ) : null}
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {group.items.map((section) => {
              const termLabel = formatSectionTerm({
                school_year: section.schoolYear,
                term_label: section.termLabel,
              });
              const cardSection: ExpandableClassSection = {
                name: section.name,
                studentCount: section.count,
                rosterPending: section.rosterPending,
                subtitle: archived
                  ? [
                      termLabel,
                      section.archivedAt
                        ? `Archived ${section.archivedAt.slice(0, 10)}`
                        : null,
                      archiveRetentionLabel(section.archivedAt),
                    ]
                      .filter(Boolean)
                      .join(" · ")
                  : (termLabel ?? undefined),
              };

              return (
                <ExpandableClassCard
                  key={section.id}
                  section={cardSection}
                  isOpen={expandedId === section.id}
                  onToggle={() => toggleSection(section.id)}
                >
                  <div className="flex flex-wrap gap-2">
                    <Link
                      href={classRosterHref(section.name)}
                      className="inline-flex items-center gap-1.5 rounded-xl bg-emerald-500 px-3 py-2 text-xs font-bold text-white hover:bg-emerald-600"
                    >
                      <Users className="h-3.5 w-3.5" />
                      View roster
                    </Link>
                    {!archived ? (
                      <>
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
                        <ArchiveSectionButton
                          name={section.name}
                          schoolYear={section.schoolYear}
                          termLabel={section.termLabel}
                        />
                      </>
                    ) : (
                      <>
                        <RestoreSectionButton name={section.name} />
                        <DeleteArchivedSectionButton
                          sectionId={section.id}
                          name={section.name}
                          studentCount={section.count}
                        />
                      </>
                    )}
                  </div>
                </ExpandableClassCard>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

function ArchiveSectionButton({
  name,
  schoolYear,
  termLabel,
}: {
  name: string;
  schoolYear?: string | null;
  termLabel?: string | null;
}) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleArchive() {
    const termLine = [termLabel, schoolYear].filter(Boolean).join(" · ") || "term not set";
    const confirmed = window.confirm(
      `Archive "${name}" (${termLine})?\n\n` +
        `Scores and roster stay on the web under Archived.\n` +
        `On the phone, after Sync Now this class leaves the dashboard and appears in Phone Archive.\n\n` +
        `Tip: each school year has 1st Sem and 2nd Sem — archive when that semester ends.`,
    );
    if (!confirmed) return;

    setError(null);
    startTransition(async () => {
      try {
        await archiveSectionAction(name, {
          schoolYear: schoolYear ?? undefined,
          termLabel: termLabel ?? undefined,
        });
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not archive. Try again.");
      }
    });
  }

  return (
    <div className="flex flex-col gap-1">
      <button
        type="button"
        onClick={handleArchive}
        disabled={isPending}
        className="inline-flex items-center gap-1.5 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs font-bold text-amber-900 hover:border-amber-300 disabled:cursor-not-allowed disabled:opacity-60"
      >
        <Archive className="h-3.5 w-3.5" />
        {isPending ? "Archiving…" : "Archive"}
      </button>
      {error ? <span className="text-xs font-semibold text-red-600">{error}</span> : null}
    </div>
  );
}

function RestoreSectionButton({ name }: { name: string }) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleRestore() {
    const confirmed = window.confirm(
      `Restore "${name}"?\n\nThe class returns here and to the phone app the next time that teacher taps Sync Now.`,
    );
    if (!confirmed) return;

    setError(null);
    startTransition(async () => {
      try {
        await restoreSection(name);
      } catch (err) {
        setError(err instanceof Error ? err.message : "Could not restore. Try again.");
      }
    });
  }

  return (
    <div className="flex flex-col gap-1">
      <button
        type="button"
        onClick={handleRestore}
        disabled={isPending}
        className="inline-flex items-center gap-1.5 rounded-xl bg-emerald-500 px-3 py-2 text-xs font-bold text-white hover:bg-emerald-600 disabled:cursor-not-allowed disabled:opacity-60"
      >
        <RotateCcw className="h-3.5 w-3.5" />
        {isPending ? "Restoring…" : "Restore"}
      </button>
      {error ? <span className="text-xs font-semibold text-red-600">{error}</span> : null}
    </div>
  );
}

function DeleteArchivedSectionButton({
  sectionId,
  name,
  studentCount,
}: {
  sectionId: string;
  name: string;
  studentCount: number;
}) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleDelete() {
    const confirmed = window.confirm(
      `Delete "${name}" forever?\n\n` +
        `This permanently removes the class and its ${studentCount} student` +
        `${studentCount === 1 ? "" : "s"} / scores from the school server.\n` +
        `This cannot be undone. Phones drop it after Sync Now.`,
    );
    if (!confirmed) return;
    const typed = window.prompt(
      `Type DELETE to permanently remove "${name}" from the school server.`,
    );
    if (typed?.trim().toUpperCase() !== "DELETE") {
      return;
    }

    setError(null);
    startTransition(async () => {
      try {
        await permanentlyDeleteSectionAction({ sectionId, sectionName: name });
      } catch (err) {
        setError(
          err instanceof Error ? err.message : "Could not delete. Try again.",
        );
      }
    });
  }

  return (
    <div className="flex flex-col gap-1">
      <button
        type="button"
        onClick={handleDelete}
        disabled={isPending}
        className="inline-flex items-center gap-1.5 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-bold text-red-800 hover:border-red-300 disabled:cursor-not-allowed disabled:opacity-60"
      >
        <Trash2 className="h-3.5 w-3.5" />
        {isPending ? "Deleting…" : "Delete forever"}
      </button>
      {error ? <span className="text-xs font-semibold text-red-600">{error}</span> : null}
    </div>
  );
}
