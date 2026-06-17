import Link from "next/link";
import { EmptyState } from "@/components/dashboard-shell";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import {
  displaySectionStudentCount,
  fetchSections,
  fetchSectionStudentCounts,
} from "@/lib/api/data";
import { requireTeacherSession } from "@/lib/api/session";
import { ClassesList } from "./classes-list";

export default async function ClassesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const query = q?.trim().toLowerCase() ?? "";
  const { supabase } = await requireTeacherSession();
  const [sections, counts] = await Promise.all([
    fetchSections(supabase),
    fetchSectionStudentCounts(supabase),
  ]);

  const filtered = query
    ? sections.filter((s) => s.name.toLowerCase().includes(query))
    : sections;

  return (
    <>
      <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-extrabold text-slate-800">Classes</h1>
          <p className="mt-1 text-sm text-slate-500">Sections synced from your phone or imported here.</p>
        </div>
        <Link
          href="/dashboard/prepare/import"
          className="rounded-2xl bg-emerald-500 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-emerald-600"
        >
          Import roster
        </Link>
      </div>

      {sections.length > 0 ? (
        <form className="mb-4 max-w-md" method="get">
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
          title="No classes yet"
          body="Import a roster in Prepare, or sync from your phone after adding students in the app."
        />
      ) : filtered.length === 0 ? (
        <EmptyState title="No matches" body={`No class names match "${q}".`} />
      ) : (
        <ClassesList
          sections={filtered.map((section) => {
            const live = counts.get(section.name);
            const { count, rosterPending } = displaySectionStudentCount(
              live,
              section.student_count,
            );
            return { id: section.id, name: section.name, count, rosterPending };
          })}
        />
      )}
    </>
  );
}
