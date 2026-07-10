import type { DbSubject } from "@/lib/types/database";
import { getQuestionAnswers } from "@/lib/omr/answer-key";

const STORED_ANSWER_PATTERN = /[A-E]/gi;

/** Matches Flutter [parseStoredAnswerSelections]. */
export function parseStoredAnswerSelections(rawAnswer: string | null | undefined): string[] {
  if (!rawAnswer?.trim()) {
    return [];
  }
  const selections: string[] = [];
  for (const match of rawAnswer.toUpperCase().matchAll(STORED_ANSWER_PATTERN)) {
    const token = match[0];
    if (token && !selections.includes(token)) {
      selections.push(token);
    }
  }
  return selections;
}

export function calculateQuestionScoreFromSelections(
  subject: Pick<DbSubject, "answer_key" | "use_partial_credit">,
  question: number,
  selectedAnswers: Iterable<string>,
): number {
  const correctAnswers = getQuestionAnswers(subject.answer_key, String(question));
  if (correctAnswers.length === 0) {
    return 0;
  }

  const normalizedSelected = new Set(
    [...selectedAnswers].map((a) => a.trim().toUpperCase()).filter((a) => a.length > 0),
  );
  if (normalizedSelected.size === 0) {
    return 0;
  }

  const normalizedCorrect = new Set(correctAnswers.map((a) => a.toUpperCase()));
  let correctSelections = 0;
  let incorrectSelections = 0;
  for (const sel of normalizedSelected) {
    if (normalizedCorrect.has(sel)) {
      correctSelections++;
    } else {
      incorrectSelections++;
    }
  }

  if (!subject.use_partial_credit || correctAnswers.length === 1) {
    return correctSelections === normalizedCorrect.size && incorrectSelections === 0 ? 1 : 0;
  }

  const partialScore = (correctSelections - incorrectSelections) / correctAnswers.length;
  return Math.min(1, Math.max(0, partialScore));
}

export function calculateQuestionScore(
  subject: Pick<DbSubject, "answer_key" | "use_partial_credit">,
  question: number,
  storedAnswer: string | null | undefined,
): number {
  return calculateQuestionScoreFromSelections(
    subject,
    question,
    parseStoredAnswerSelections(storedAnswer),
  );
}

export function isFullyCorrect(
  subject: Pick<DbSubject, "answer_key" | "use_partial_credit">,
  question: number,
  storedAnswer: string | null | undefined,
): boolean {
  return calculateQuestionScore(subject, question, storedAnswer) >= 1;
}
