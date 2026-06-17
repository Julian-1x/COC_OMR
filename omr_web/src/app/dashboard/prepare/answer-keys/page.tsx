"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { EmptyState } from "@/components/dashboard-shell";
import { PageSkeleton } from "@/components/page-skeleton";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { deleteSubject, fetchSubjects } from "@/lib/api/data";
import type { DbSubject } from "@/lib/types/database";

export default function AnswerKeysPage() {
  const [subjects, setSubjects] = useState<DbSubject[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    try {
      const supabase = createClient();
      setSubjects(await fetchSubjects(supabase));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  async function remove(localId: string, subjectName: string) {
    if (
      !confirm(
        `Delete answer key "${subjectName}"?\n\nThis removes it from the cloud. Sync on your phone after deleting.`,
      )
    ) {
      return;
    }
    const supabase = createClient();
    await deleteSubject(supabase, localId);
    await load();
  }

  return (
    <>
      <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <Link href="/dashboard/prepare" className="text-sm font-bold text-emerald-700 hover:underline">
            ← Prepare
          </Link>
          <h1 className="mt-2 text-2xl font-extrabold text-slate-800">Answer keys</h1>
        </div>
        <Link
          href="/dashboard/prepare/answer-keys/new"
          className="rounded-2xl bg-emerald-500 px-4 py-2.5 text-sm font-extrabold text-white hover:bg-emerald-600"
        >
          New answer key
        </Link>
      </div>

      {error ? <p className="mb-3 text-sm font-semibold text-red-600">{error}</p> : null}
      {loading ? (
        <PageSkeleton rows={4} />
      ) : subjects.length === 0 ? (
        <EmptyState title="No answer keys" body="Create a subject and assign it to your sections." />
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {subjects.map((subject) => (
            <Card key={subject.id}>
              <h2 className="text-lg font-extrabold text-slate-800">{subject.name}</h2>
              <p className="mt-1 text-sm text-slate-500">
                {subject.total_questions} items · Pass {subject.passing_score}%
              </p>
              <p className="mt-1 text-xs text-slate-400">
                Sections: {(subject.section_names ?? []).join(", ") || "None"}
              </p>
              <div className="mt-4 flex gap-2">
                <Link
                  href={`/dashboard/prepare/answer-keys/${encodeURIComponent(subject.local_id)}`}
                  className="rounded-xl bg-emerald-50 px-3 py-2 text-sm font-bold text-emerald-800"
                >
                  Edit
                </Link>
                <Button type="button" variant="ghost" onClick={() => void remove(subject.local_id, subject.name)}>
                  Delete
                </Button>
              </div>
            </Card>
          ))}
        </div>
      )}
    </>
  );
}
