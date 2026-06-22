"use client";

import type { ReactNode } from "react";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

export type ExpandableClassSection = {
  name: string;
  studentCount: number;
  rosterPending?: boolean;
  subtitle?: string;
};

export function ExpandableClassCard({
  section,
  isOpen,
  onToggle,
  children,
}: {
  section: ExpandableClassSection;
  isOpen: boolean;
  onToggle: () => void;
  children: ReactNode;
}) {
  return (
    <div
      className={cn(
        "rounded-xl border bg-white transition",
        isOpen ? "border-emerald-200 shadow-sm" : "border-slate-200 hover:border-slate-300",
      )}
    >
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center justify-between gap-3 p-4 text-left"
        aria-expanded={isOpen}
        aria-controls={`class-panel-${section.name}`}
      >
        <div className="min-w-0">
          <h3 className="font-extrabold text-slate-800">{section.name}</h3>
          <p className="mt-0.5 text-sm text-slate-500">
            {section.studentCount} student{section.studentCount === 1 ? "" : "s"}
            {section.subtitle ? ` · ${section.subtitle}` : ""}
          </p>
          {section.rosterPending ? (
            <p className="mt-1 text-xs font-semibold text-amber-700">
              Roster still syncing — run Sync Now on your phone
            </p>
          ) : null}
        </div>
        <ChevronDown
          className={cn(
            "h-5 w-5 shrink-0 text-slate-400 transition-transform",
            isOpen && "rotate-180",
          )}
          aria-hidden
        />
      </button>
      {isOpen ? (
        <div
          id={`class-panel-${section.name}`}
          className="border-t border-slate-100 px-4 pb-4 pt-3"
        >
          {children}
        </div>
      ) : null}
    </div>
  );
}
