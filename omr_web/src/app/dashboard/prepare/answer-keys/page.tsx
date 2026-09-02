"use client";

import Link from "next/link";
import { useState } from "react";
import { EmptyState } from "@/components/dashboard-shell";
import { PageSkeleton } from "@/components/page-skeleton";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { createBrowserApiClient } from "@/lib/api/laravel-client";
import { deleteSubject, fetchSubjects } from "@/lib/api/data";
import { slowApiLoadingMessage, useSlowApiLoad } from "@/lib/api/use-slow-api-load";
import type { DbSubject } from "@/lib/types/database";
import { formatPassingLabel } from "@/lib/omr/passing-score";

export default function AnswerKeysPage() {
  const [subjects, setSubjects] = useState<DbSubject[]>([]);
  const {
    loading,
    error,
    attempt: loadAttempt,
    maxAttempts,
    reload,
  } = useSlowApiLoad(async () => {
    const api = createBrowserApiClient();
    setSubjects(await fetchSubjects(api));
  }, []);

  async function remove(localId: string, subjectName: string) {
    if (
      !confirm(
        `Delete answer key "${subjectName}"?\n\nThis removes it from the cloud. Sync on your phone after deleting.`,
      )
    ) {
      return;
    }
    const api = createBrowserApiClient();
    await deleteSubject(api, localId);
    reload();
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

      {error ? (
        <Card className="mb-3 border-red-200 bg-red-50">
          <p className="text-sm font-semibold text-red-700">{error}</p>
          <Button type="button" variant="secondary" className="mt-3" onClick={reload}>
            Try again
          </Button>
        </Card>
      ) : null}
      {loading ? (
        <div>
          <PageSkeleton rows={4} />
          <p className="mt-2 text-xs text-slate-500">{slowApiLoadingMessage(loadAttempt, maxAttempts)}</p>
        </div>
      ) : subjects.length === 0 ? (
        <EmptyState title="No answer keys" body="Create a subject and assign it to your sections." />
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {subjects.map((subject) => (
            <Card key={subject.id}>
              <h2 className="text-lg font-extrabold text-slate-800">{subject.name}</h2>
              <p className="mt-1 text-sm text-slate-500">
                {subject.total_questions} items · {formatPassingLabel(subject.passing_score, subject.total_questions)}
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
