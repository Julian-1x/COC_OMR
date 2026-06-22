"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { PageSkeleton } from "@/components/page-skeleton";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input, Label, Select } from "@/components/ui/input";
import { createClient } from "@/lib/supabase/client";
import { fetchSections, fetchSubject, fetchSubjects, upsertSubject } from "@/lib/api/data";
import { generateSubjectLocalId } from "@/lib/import/roster";
import {
  defaultPassingPoints,
  formatPassingLabel,
  passingPercent,
} from "@/lib/omr/passing-score";
import {
  formatCorrectAnswer,
  getQuestionAnswers,
  isAnswerSelected,
  toggleQuestionAnswer,
} from "@/lib/omr/answer-key";
import type { AnswerKeyMap } from "@/lib/types/database";

const ITEM_COUNTS = [30, 40, 50, 60, 70, 80, 90, 100];

export default function AnswerKeyEditorPage() {
  const params = useParams<{ localId: string }>();
  const router = useRouter();
  const localIdParam = params.localId === "new" ? null : decodeURIComponent(params.localId);
  const isNew = localIdParam === null;

  const [name, setName] = useState("");
  const [totalQuestions, setTotalQuestions] = useState(50);
  const [passingScore, setPassingScore] = useState(() => defaultPassingPoints(50));
  const [examDate, setExamDate] = useState("");
  const [usePartialCredit, setUsePartialCredit] = useState(false);
  const [allowMultiAnswer, setAllowMultiAnswer] = useState(false);
  const [sections, setSections] = useState<string[]>([]);
  const [sectionQrData, setSectionQrData] = useState<Record<string, string>>({});
  const [allSections, setAllSections] = useState<string[]>([]);
  const [answerKey, setAnswerKey] = useState<AnswerKeyMap>({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      try {
        const supabase = createClient();
        const sectionRows = await fetchSections(supabase);
        setAllSections(sectionRows.map((s) => s.name));

        if (localIdParam) {
          const subject = await fetchSubject(supabase, localIdParam);
          if (subject) {
            setName(subject.name);
            setTotalQuestions(subject.total_questions);
            setPassingScore(subject.passing_score);
            setSections(subject.section_names ?? []);
            setAnswerKey(subject.answer_key ?? {});
            setSectionQrData(subject.section_qr_data ?? {});
            setExamDate(subject.exam_date ?? "");
            setUsePartialCredit(subject.use_partial_credit);
            const hasMulti = Object.values(subject.answer_key ?? {}).some((v) => Array.isArray(v));
            setAllowMultiAnswer(hasMulti);
          }
        } else {
          const defaults: AnswerKeyMap = {};
          for (let i = 1; i <= 50; i++) defaults[String(i)] = "A";
          setAnswerKey(defaults);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to load.");
      } finally {
        setLoading(false);
      }
    }
    void load();
  }, [localIdParam]);

  function resizeKey(count: number) {
    setTotalQuestions(count);
    setPassingScore((prev) => {
      const pct = passingPercent(prev, totalQuestions);
      return defaultPassingPoints(count) === prev ? prev : Math.max(1, Math.round((count * pct) / 100));
    });
    setAnswerKey((prev) => {
      const next: AnswerKeyMap = {};
      for (let i = 1; i <= count; i++) {
        next[String(i)] = prev[String(i)] ?? "A";
      }
      return next;
    });
  }

  function toggleSection(section: string) {
    setSections((prev) =>
      prev.includes(section) ? prev.filter((s) => s !== section) : [...prev, section],
    );
  }

  async function save() {
    setSaving(true);
    setError(null);
    try {
      const supabase = createClient();
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) throw new Error("Sign in required.");
      const existing = await fetchSubjects(supabase);
      const localId = localIdParam ?? generateSubjectLocalId(existing);
      const now = new Date().toISOString();

      await upsertSubject(supabase, user.id, {
        local_id: localId,
        name: name.trim(),
        answer_key: answerKey,
        total_questions: totalQuestions,
        section_names: sections,
        section_qr_data: sectionQrData,
        exam_date: examDate || null,
        passing_score: passingScore,
        use_partial_credit: usePartialCredit,
        updated_at: now,
      });

      router.push("/dashboard/prepare/answer-keys");
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed.");
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return <PageSkeleton rows={5} />;
  }

  return (
    <>
      <div className="mb-4">
        <Link href="/dashboard/prepare/answer-keys" className="text-sm font-bold text-emerald-700 hover:underline">
          ← Answer keys
        </Link>
        <h1 className="mt-2 text-2xl font-extrabold text-slate-800">
          {isNew ? "New answer key" : "Edit answer key"}
        </h1>
      </div>

      <div className="grid gap-4 lg:grid-cols-[320px_1fr]">
        <Card title="Subject details">
          <div className="space-y-3">
            <div>
              <Label htmlFor="name">Subject name</Label>
              <Input id="name" value={name} onChange={(e) => setName(e.target.value)} required />
            </div>
            <div>
              <Label htmlFor="items">Item count</Label>
              <Select
                id="items"
                value={String(totalQuestions)}
                onChange={(e) => resizeKey(parseInt(e.target.value, 10))}
              >
                {ITEM_COUNTS.map((n) => (
                  <option key={n} value={n}>
                    {n} items
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <Label htmlFor="pass">Minimum score to pass (points)</Label>
              <Input
                id="pass"
                type="number"
                min={1}
                max={totalQuestions}
                value={passingScore}
                onChange={(e) => setPassingScore(parseInt(e.target.value, 10) || 1)}
              />
              <p className="mt-1 text-xs text-slate-500">
                {formatPassingLabel(passingScore, totalQuestions)} — same as the phone app
              </p>
            </div>
            <div>
              <Label htmlFor="exam">Exam date</Label>
              <Input id="exam" type="date" value={examDate} onChange={(e) => setExamDate(e.target.value)} />
            </div>
            <label className="flex items-center gap-2 text-sm font-semibold text-slate-700">
              <input
                type="checkbox"
                checked={usePartialCredit}
                onChange={(e) => setUsePartialCredit(e.target.checked)}
              />
              Partial credit
            </label>
            <label className="flex items-center gap-2 text-sm font-semibold text-slate-700">
              <input
                type="checkbox"
                checked={allowMultiAnswer}
                onChange={(e) => setAllowMultiAnswer(e.target.checked)}
              />
              Allow two correct answers per item
            </label>
            <div>
              <Label>Sections</Label>
              <div className="mt-2 flex flex-wrap gap-2">
                {allSections.length === 0 ? (
                  <p className="text-xs text-slate-500">Import a roster first.</p>
                ) : (
                  allSections.map((section) => (
                    <button
                      key={section}
                      type="button"
                      onClick={() => toggleSection(section)}
                      className={`rounded-full px-3 py-1 text-xs font-bold ${
                        sections.includes(section)
                          ? "bg-emerald-500 text-white"
                          : "bg-slate-100 text-slate-600"
                      }`}
                    >
                      {section}
                    </button>
                  ))
                )}
              </div>
            </div>
            {error ? <p className="text-sm font-semibold text-red-600">{error}</p> : null}
            <Button type="button" className="w-full" disabled={saving || !name.trim()} onClick={() => void save()}>
              {saving ? "Saving…" : "Save answer key"}
            </Button>
          </div>
        </Card>

        <Card
          title="Answer key"
          subtitle={
            allowMultiAnswer
              ? "Tap for primary answer; tap again for optional second acceptable answer"
              : "Tap a letter to set the correct option"
          }
        >
          <div className="grid max-h-[70vh] gap-2 overflow-y-auto sm:grid-cols-2 lg:grid-cols-3">
            {Array.from({ length: totalQuestions }, (_, i) => i + 1).map((q) => {
              const key = String(q);
              const answers = getQuestionAnswers(answerKey, key);
              return (
                <div key={q} className="rounded-xl border border-slate-200 px-2 py-1.5">
                  <div className="mb-1 flex items-center justify-between">
                    <span className="text-xs font-extrabold text-slate-500">{q}</span>
                    <span className="text-[10px] font-bold text-emerald-700">
                      {formatCorrectAnswer(answerKey[key])}
                    </span>
                  </div>
                  <div className="flex items-center gap-1">
                    {["A", "B", "C", "D", "E"].map((letter) => (
                      <button
                        key={letter}
                        type="button"
                        onClick={() =>
                          setAnswerKey((prev) => toggleQuestionAnswer(prev, key, letter, allowMultiAnswer))
                        }
                        className={`h-8 w-8 rounded-lg text-xs font-extrabold ${
                          isAnswerSelected(answerKey, key, letter)
                            ? answers.indexOf(letter) === 1
                              ? "bg-amber-500 text-white"
                              : "bg-emerald-500 text-white"
                            : "bg-slate-100 text-slate-600"
                        }`}
                      >
                        {letter}
                      </button>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </Card>
      </div>
    </>
  );
}
