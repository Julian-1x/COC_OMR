import type { DbScanResult, DbStudent, DbSubject } from "@/lib/types/database";
import { liveSectionsForSubject } from "@/lib/omr/answer-key-scope";
import { gradedLatestPerStudent } from "@/lib/omr/item-analysis";
import { scanPassed } from "@/lib/omr/passing-score";
import {
  classRosterHref,
  omrIdsHref,
  printSheetsHref,
} from "@/lib/prepare-links";

export type ClassSnapshot = {
  sectionName: string;
  studentCount: number;
  gradedCount: number;
  pendingCount: number;
  averagePercent: number | null;
  passRate: number | null;
  failCount: number;
};

export type AttentionItem = {
  id: string;
  label: string;
  href: string;
  tone: "amber" | "red" | "slate";
};

export type ExamTarget = {
  subjectLocalId: string;
  subjectName: string;
  sectionName: string;
};

function passingPoints(scan: DbScanResult, subjects: DbSubject[]): number {
  const subject = subjects.find(
    (s) => s.local_id === scan.subject_local_id || s.name === scan.subject_name,
  );
  return subject?.passing_score ?? Math.round(scan.total_questions * 0.6);
}

/** Latest scan per student (approved preferred for metrics). */
export function buildClassSnapshots(
  sections: { name: string }[],
  students: DbStudent[],
  scans: DbScanResult[],
  subjects: DbSubject[],
): ClassSnapshot[] {
  const bySection = new Map<string, DbStudent[]>();
  for (const student of students) {
    const key = student.section_name?.trim();
    if (!key) continue;
    const list = bySection.get(key) ?? [];
    list.push(student);
    bySection.set(key, list);
  }

  const latest = gradedLatestPerStudent(scans.filter((s) => !s.needs_review));
  const pending = scans.filter((s) => s.needs_review);

  return sections
    .map((section) => {
      const roster = bySection.get(section.name) ?? [];
      const rosterIds = new Set(roster.map((s) => s.omr_id));
      const sectionLatest = latest.filter((scan) => {
        const student = students.find((s) => s.omr_id === scan.student_omr_id);
        return student?.section_name === section.name || rosterIds.has(scan.student_omr_id);
      });
      const sectionPending = pending.filter((scan) => {
        const student = students.find((s) => s.omr_id === scan.student_omr_id);
        return student?.section_name === section.name;
      }).length;

      let averagePercent: number | null = null;
      let passRate: number | null = null;
      let failCount = 0;
      if (sectionLatest.length > 0) {
        const pctSum = sectionLatest.reduce((sum, scan) => {
          if (scan.total_questions <= 0) return sum;
          return sum + (scan.score / scan.total_questions) * 100;
        }, 0);
        averagePercent = Math.round(pctSum / sectionLatest.length);
        const passed = sectionLatest.filter((scan) =>
          scanPassed(scan.score, scan.total_questions, passingPoints(scan, subjects)),
        ).length;
        failCount = sectionLatest.length - passed;
        passRate = Math.round((passed / sectionLatest.length) * 100);
      }

      return {
        sectionName: section.name,
        studentCount: roster.length,
        gradedCount: sectionLatest.length,
        pendingCount: sectionPending,
        averagePercent,
        passRate,
        failCount,
      };
    })
    .sort((a, b) => a.sectionName.localeCompare(b.sectionName));
}

export function buildAttentionItems(input: {
  pendingReview: number;
  sections: { name: string }[];
  students: DbStudent[];
  subjects: DbSubject[];
}): AttentionItem[] {
  const { pendingReview, sections, students, subjects } = input;
  const items: AttentionItem[] = [];
  const activeNames = sections.map((s) => s.name);
  const studentsBySection = new Map<string, number>();
  for (const student of students) {
    const key = student.section_name?.trim();
    if (!key) continue;
    studentsBySection.set(key, (studentsBySection.get(key) ?? 0) + 1);
  }

  if (pendingReview > 0) {
    items.push({
      id: "pending",
      label: `${pendingReview} scan${pendingReview === 1 ? "" : "s"} need Review on the phone`,
      href: "/dashboard/results?review=pending",
      tone: "amber",
    });
  }

  const emptyRosters = sections.filter((s) => (studentsBySection.get(s.name) ?? 0) === 0);
  for (const section of emptyRosters.slice(0, 3)) {
    items.push({
      id: `empty-${section.name}`,
      label: `${section.name} has no students`,
      href: "/dashboard/prepare/import",
      tone: "amber",
    });
  }

  const unassigned = subjects.filter(
    (s) => !s.section_names || s.section_names.length === 0,
  );
  for (const subject of unassigned.slice(0, 2)) {
    items.push({
      id: `key-${subject.local_id}`,
      label: `${subject.name} has no section linked`,
      href: `/dashboard/prepare/answer-keys/${encodeURIComponent(subject.local_id)}`,
      tone: "red",
    });
  }

  const sectionsWithKey = new Set<string>();
  for (const subject of subjects) {
    for (const name of liveSectionsForSubject(subject, activeNames)) {
      sectionsWithKey.add(name);
    }
  }
  const withoutKey = sections.filter(
    (s) => (studentsBySection.get(s.name) ?? 0) > 0 && !sectionsWithKey.has(s.name),
  );
  for (const section of withoutKey.slice(0, 3)) {
    items.push({
      id: `nokey-${section.name}`,
      label: `${section.name} has no answer key`,
      href: "/dashboard/prepare/answer-keys",
      tone: "amber",
    });
  }

  return items;
}

/** Prefer a printable subject+section with the fewest graded sheets (exam not done yet). */
export function suggestExamTarget(
  subjects: DbSubject[],
  activeSectionNames: string[],
  scans: DbScanResult[],
  students: DbStudent[],
): ExamTarget | null {
  const studentMap = new Map(students.map((s) => [s.omr_id, s]));
  const graded = gradedLatestPerStudent(scans.filter((s) => !s.needs_review));

  type Candidate = ExamTarget & { graded: number };
  const candidates: Candidate[] = [];

  for (const subject of subjects) {
    for (const sectionName of liveSectionsForSubject(subject, activeSectionNames)) {
      const gradedForPair = graded.filter((scan) => {
        if (scan.subject_local_id !== subject.local_id && scan.subject_name !== subject.name) {
          return false;
        }
        return studentMap.get(scan.student_omr_id)?.section_name === sectionName;
      }).length;
      candidates.push({
        subjectLocalId: subject.local_id,
        subjectName: subject.name,
        sectionName,
        graded: gradedForPair,
      });
    }
  }

  if (candidates.length === 0) return null;
  candidates.sort((a, b) => a.graded - b.graded || a.subjectName.localeCompare(b.subjectName));
  const best = candidates[0];
  return {
    subjectLocalId: best.subjectLocalId,
    subjectName: best.subjectName,
    sectionName: best.sectionName,
  };
}

export function examActionLinks(target: ExamTarget) {
  return {
    print: printSheetsHref(target.subjectLocalId, target.sectionName),
    omrIds: omrIdsHref(target.sectionName),
    results: `/dashboard/results?section=${encodeURIComponent(target.sectionName)}&subject=${encodeURIComponent(target.subjectLocalId)}`,
    analysis: `/dashboard/results/analysis?subject=${encodeURIComponent(target.subjectLocalId)}&section=${encodeURIComponent(target.sectionName)}`,
    roster: classRosterHref(target.sectionName),
  };
}
