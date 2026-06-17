import Link from "next/link";
import { Card } from "@/components/ui/card";
import { requireTeacherSession } from "@/lib/api/session";
import { BookOpen, FileSpreadsheet, Printer, Hash } from "lucide-react";

const tools = [
  {
    href: "/dashboard/prepare/answer-keys",
    title: "Answer keys",
    body: "Create and edit subjects, assign sections, set passing score.",
    icon: BookOpen,
  },
  {
    href: "/dashboard/prepare/print-sheets",
    title: "Print OMR sheets",
    body: "Download printable bubble sheets at 100% scale.",
    icon: Printer,
  },
  {
    href: "/dashboard/prepare/omr-ids",
    title: "OMR ID handouts",
    body: "Export per-section OMR ID lists for students.",
    icon: Hash,
  },
  {
    href: "/dashboard/prepare/import",
    title: "Import roster",
    body: "Upload CSV or Excel roster files.",
    icon: FileSpreadsheet,
  },
];

export default async function PreparePage() {
  await requireTeacherSession();

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-extrabold text-slate-800">Prepare</h1>
        <p className="mt-1 text-sm text-slate-500">Exam setup before scanning day.</p>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {tools.map((tool) => {
          const Icon = tool.icon;
          return (
            <Link key={tool.href} href={tool.href}>
              <Card className="h-full transition hover:border-emerald-300 hover:shadow-md">
                <div className="flex items-start gap-3">
                  <div className="rounded-xl bg-emerald-50 p-2 text-emerald-700">
                    <Icon className="h-5 w-5" />
                  </div>
                  <div>
                    <h2 className="font-extrabold text-slate-800">{tool.title}</h2>
                    <p className="mt-1 text-sm text-slate-500">{tool.body}</p>
                  </div>
                </div>
              </Card>
            </Link>
          );
        })}
      </div>
    </>
  );
}
