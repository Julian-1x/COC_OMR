import Link from "next/link";

import { EmptyState } from "@/components/dashboard-shell";

import { Input } from "@/components/ui/input";

import {

  displaySectionStudentCount,

  fetchSections,

  fetchSectionStudentCounts,

} from "@/lib/api/data";

import { requireTeacherSession } from "@/lib/api/session";

import { schoolYearOptions } from "@/lib/academic-term";

import { ClassesList } from "./classes-list";



export default async function ClassesPage({

  searchParams,

}: {

  searchParams: Promise<{ q?: string; view?: string; year?: string }>;

}) {

  const { q, view, year } = await searchParams;

  const query = q?.trim().toLowerCase() ?? "";

  const showArchived = view === "archived";

  const schoolYear = year?.trim() || undefined;

  const { supabase } = await requireTeacherSession();

  const [sections, counts] = await Promise.all([

    fetchSections(supabase, {

      archived: showArchived,

      schoolYear,

    }),

    fetchSectionStudentCounts(supabase),

  ]);



  const filtered = query

    ? sections.filter((s) => s.name.toLowerCase().includes(query))

    : sections;



  const yearOptions = schoolYearOptions();



  return (

    <>

      <div className="mb-6 flex flex-wrap items-end justify-between gap-3">

        <div>

          <h1 className="text-2xl font-extrabold text-slate-800">Classes</h1>

          <p className="mt-1 text-sm text-slate-500">

            {showArchived

              ? "Archived sections — read-only history from past terms."

              : "Active class sections for this term. Tap a card to open actions."}

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



      <div className="mb-4 flex flex-wrap items-center gap-2">

        <Link

          href="/dashboard/classes"

          className={`rounded-xl px-3 py-2 text-sm font-bold ${

            !showArchived

              ? "bg-emerald-500 text-white"

              : "border border-slate-200 bg-white text-slate-600 hover:border-emerald-300"

          }`}

        >

          Active

        </Link>

        <Link

          href="/dashboard/classes?view=archived"

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

          <button

            type="submit"

            className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700 hover:border-emerald-300"

          >

            Filter

          </button>

        </form>

      </div>



      {sections.length > 0 ? (

        <form className="mb-4 max-w-md" method="get">

          {showArchived ? <input type="hidden" name="view" value="archived" /> : null}

          {schoolYear ? <input type="hidden" name="year" value={schoolYear} /> : null}

          <Input

            name="q"

            defaultValue={q ?? ""}

            placeholder="Search classes…"

            aria-label="Search classes"

          />

        </form>

      ) : null}



      {sections.length === 0 ? (

        <EmptyState

          title={showArchived ? "No archived classes" : "No classes yet"}

          body={

            showArchived

              ? "When you archive a section on the phone app, it appears here with full history."

              : "Import a roster in Prepare, or add students in the phone app and sync."

          }

        />

      ) : filtered.length === 0 ? (

        <EmptyState title="No matches" body={`No class names match "${q}".`} />

      ) : (

        <ClassesList

          archived={showArchived}

          sections={filtered.map((section) => {

            const live = counts.get(section.name);

            const { count, rosterPending } = displaySectionStudentCount(

              live,

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


