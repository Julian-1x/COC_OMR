"use client";

import Link from "next/link";
import { useState } from "react";
import { Hash, Printer, Users } from "lucide-react";
import {
  ExpandableClassCard,
  type ExpandableClassSection,
} from "@/components/expandable-class-card";
import {
  classRosterHref,
  omrIdsHref,
  sectionPrintSheetsHref,
} from "@/lib/prepare-links";
import { formatSectionTerm } from "@/lib/academic-term";

export function ClassesList({
  sections,
  archived = false,
}: {
  sections: {
    id: string;
    name: string;
    count: number;
    rosterPending: boolean;
    schoolYear?: string | null;
    termLabel?: string | null;
    archivedAt?: string | null;
  }[];
  archived?: boolean;
}) {
  const [expandedName, setExpandedName] = useState<string | null>(null);

  function toggleSection(name: string) {
    setExpandedName((current) => (current === name ? null : name));
  }

  return (
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
      {sections.map((section) => {
        const termLabel = formatSectionTerm({
          school_year: section.schoolYear,
          term_label: section.termLabel,
        });
        const cardSection: ExpandableClassSection = {
          name: section.name,
          studentCount: section.count,
          rosterPending: section.rosterPending,
          subtitle: archived
            ? [termLabel, section.archivedAt ? `Archived ${section.archivedAt.slice(0, 10)}` : null]
                .filter(Boolean)
                .join(" · ")
            : termLabel ?? undefined,
        };

        return (
          <ExpandableClassCard
            key={section.id}
            section={cardSection}
            isOpen={expandedName === section.name}
            onToggle={() => toggleSection(section.name)}
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
                </>
              ) : (
                <span className="rounded-xl bg-slate-100 px-3 py-2 text-xs font-semibold text-slate-600">
                  Read-only archive
                </span>
              )}
            </div>
          </ExpandableClassCard>
        );
      })}
    </div>
  );
}
