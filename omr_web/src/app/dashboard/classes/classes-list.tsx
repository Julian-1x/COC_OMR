import Link from "next/link";
import { Card } from "@/components/ui/card";

export function ClassesList({
  sections,
}: {
  sections: { id: string; name: string; count: number; rosterPending: boolean }[];
}) {
  return (
    <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
      {sections.map((section) => (
        <Link key={section.id} href={`/dashboard/classes/${encodeURIComponent(section.name)}`}>
          <Card className="transition hover:border-emerald-300 hover:shadow-md">
            <h2 className="text-lg font-extrabold text-slate-800">{section.name}</h2>
            <p className="mt-2 text-sm text-slate-500">{section.count} students</p>
            {section.rosterPending ? (
              <p className="mt-1 text-xs font-semibold text-amber-700">
                Roster not fully synced — tap Sync Now on your phone
              </p>
            ) : null}
          </Card>
        </Link>
      ))}
    </div>
  );
}
