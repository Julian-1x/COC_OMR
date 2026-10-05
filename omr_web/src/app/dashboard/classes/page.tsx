import Link from "next/link";
import { EmptyState } from "@/components/dashboard-shell";
import { Input } from "@/components/ui/input";
import { displaySectionStudentCount, fetchSections } from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import {
  commonTermLabels,
  schoolYearOptions,
  semesterTermLabels,
} from "@/lib/academic-term";
import { SyncLoopNotice } from "@/components/desk-notices";
import { ClassesList } from "./classes-list";

function buildClassesHref(opts: {
  view?: string;
  year?: string;
  term?: string;
  q?: string;
}) {
  const params = new URLSearchParams();
  if (opts.view === "archived") params.set("view", "archived");
  if (opts.year) params.set("year", opts.year);
  if (opts.term) params.set("term", opts.term);
  if (opts.q) params.set("q", opts.q);
  const qs = params.toString();
  return qs ? `/dashboard/classes?${qs}` : "/dashboard/classes";
}

export default async function ClassesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; view?: string; year?: string; term?: string }>;
}) {
  const { q, view, year, term } = await searchParams;
  const query = q?.trim().toLowerCase() ?? "";
  const showArchived = view === "archived";
  const schoolYear = year?.trim() || undefined;
  const termFilter = term?.trim() || undefined;
  const { api } = await requireTeacherSession();
  const sections = await fetchSections(api, {
    archived: showArchived,
    schoolYear,
  });

  const afterTerm = termFilter
    ? sections.filter((s) => (s.term_label ?? "").trim() === termFilter)
    : sections;

  const filtered = query
    ? afterTerm.filter((s) => s.name.toLowerCase().includes(query))
    : afterTerm;

  const yearOptions = schoolYearOptions();
  const groupByTerm = Boolean(schoolYear) && !termFilter;

  return (
    <>
      <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-slate-800">Classes</h1>
          <p className="mt-1 text-sm text-slate-500">
            {showArchived
              ? "Archived sections — restore within 4 months or they are permanently deleted"
              : "Active sections · each school year has 1st Sem and 2nd Sem"}
          </p>
        </div>
        {!showArchived ? (
          <Link
            href="/dashboard/prepare/import"
            className="rounded-2xl bg-emerald-500 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-emerald-600"
          >
            Import roster
          </Link>
        ) : null}
      </div>

      <SyncLoopNotice className="mb-4" />

      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Link
          href={buildClassesHref({ year: schoolYear, term: termFilter })}
          className={`rounded-xl px-3 py-2 text-sm font-bold ${
            !showArchived
              ? "bg-emerald-500 text-white"
              : "border border-slate-200 bg-white text-slate-600 hover:border-emerald-300"
          }`}
        >
          Active
        </Link>
        <Link
          href={buildClassesHref({
            view: "archived",
            year: schoolYear,
            term: termFilter,
          })}
          className={`rounded-xl px-3 py-2 text-sm font-bold ${
            showArchived
              ? "bg-emerald-500 text-white"
              : "border border-slate-200 bg-white text-slate-600 hover:border-emerald-300"
          }`}
        >
          Archived
        </Link>
        <form className="ml-auto flex flex-wrap items-center gap-2" method="get">
          {showArchived ? <input type="hidden" name="view" value="archived" /> : null}
          <select
            name="year"
            defaultValue={schoolYear ?? ""}
            className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700"
            aria-label="School year"
          >
            <option value="">All years</option>
            {yearOptions.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
          <select
            name="term"
            defaultValue={termFilter ?? ""}
            className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700"
            aria-label="Semester"
          >
            <option value="">Both semesters</option>
            {semesterTermLabels.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
            <option value="Summer">Summer (optional)</option>
          </select>
          <button
            type="submit"
            className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700 hover:border-emerald-300"
          >
            Filter
          </button>
        </form>
      </div>

      {schoolYear && !termFilter ? (
        <p className="mb-4 text-xs font-semibold text-slate-500">
          School year {schoolYear}: classes are grouped into{" "}
          {commonTermLabels.slice(0, 2).join(" and ")}
          {afterTerm.some((s) => s.term_label === "Summer") ? " (plus Summer if used)" : ""}.
        </p>
      ) : null}

      {sections.length > 0 ? (
        <form className="mb-4 max-w-md" method="get">
          {showArchived ? <input type="hidden" name="view" value="archived" /> : null}
          {schoolYear ? <input type="hidden" name="year" value={schoolYear} /> : null}
          {termFilter ? <input type="hidden" name="term" value={termFilter} /> : null}
          <Input name="q" defaultValue={q ?? ""} placeholder="Search classes…" aria-label="Search classes" />
        </form>
      ) : null}

      {sections.length === 0 ? (
        <EmptyState
          title={showArchived ? "No archived classes" : "No classes yet"}
          body={
            showArchived
              ? "Archive a class from Active (or from the phone End of term flow). Restore within 4 months — after that archived classes are permanently deleted."
              : "Import a roster in Prepare and choose school year + 1st Sem or 2nd Sem. You can also add students on the phone and Sync Now."
          }
        />
      ) : filtered.length === 0 ? (
        <EmptyState
          title="No matches"
          body={
            query
              ? `No class names match "${q}".`
              : "No classes for this school year / semester filter."
          }
        />
      ) : (
        <ClassesList
          archived={showArchived}
          groupByTerm={groupByTerm}
          sections={filtered.map((section) => {
            const { count, rosterPending } = displaySectionStudentCount(
              undefined,
              section.student_count,
            );
            return {
              id: section.id,
              name: section.name,
              count,
              rosterPending,
              schoolYear: section.school_year,
              termLabel: section.term_label,
              archivedAt: section.archived_at,
            };
          })}
        />
      )}
    </>
  );
}
