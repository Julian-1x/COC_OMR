import type { AnswerKeyMap } from "@/lib/types/database";

export function getQuestionAnswers(key: AnswerKeyMap, question: string): string[] {
  const value = key[question];
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

export function isAnswerSelected(key: AnswerKeyMap, question: string, letter: string): boolean {
  return getQuestionAnswers(key, question).includes(letter);
}

export function toggleQuestionAnswer(
  key: AnswerKeyMap,
  question: string,
  letter: string,
  allowMulti: boolean,
): AnswerKeyMap {
  const current = getQuestionAnswers(key, question);
  if (!allowMulti) {
    return { ...key, [question]: letter };
  }
  if (current.includes(letter)) {
    const next = current.filter((a) => a !== letter);
    return { ...key, [question]: next.length === 1 ? next[0] : next.length ? next : letter };
  }
  if (current.length >= 2) {
    return { ...key, [question]: [current[0], letter] };
  }
  return { ...key, [question]: current.length ? [current[0], letter] : letter };
}

export function formatCorrectAnswer(value: string | string[] | undefined): string {
  if (!value) return "?";
  return Array.isArray(value) ? value.join(" or ") : value;
}
