import type { ApiClient, ApiUser } from "@/lib/api/laravel-client";
import {
  fetchCloudLastUpdated,
  fetchDashboardStats,
  fetchScanResults,
  fetchSections,
  fetchStudents,
  fetchSubjects,
} from "@/lib/api/data";

export type SyncDiagnostic = {
  ok: boolean;
  userId: string;
  email: string | null;
  schoolName: string | null;
  role: string | null;
  stats: Awaited<ReturnType<typeof fetchDashboardStats>>;
  lastCloudUpdate: string | null;
  tableSamples: {
    table: string;
    count: number;
    latestUpdated: string | null;
  }[];
  hints: string[];
};

function latestUpdated<T extends { updated_at?: string }>(rows: T[]): string | null {
  if (rows.length === 0) return null;
  const sorted = [...rows].sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)));
  return sorted[0]?.updated_at ? String(sorted[0].updated_at) : null;
}

async function tableDiagnostic(
  api: ApiClient,
  table: "sections" | "students" | "subjects" | "scan_results",
) {
  if (table === "sections") {
    const rows = await fetchSections(api);
    return { table, count: rows.length, latestUpdated: latestUpdated(rows) };
  }
  if (table === "students") {
    const rows = await fetchStudents(api);
    return { table, count: rows.length, latestUpdated: latestUpdated(rows) };
  }
  if (table === "subjects") {
    const rows = await fetchSubjects(api);
    return { table, count: rows.length, latestUpdated: latestUpdated(rows) };
  }
  const rows = await fetchScanResults(api);
  return { table, count: rows.length, latestUpdated: latestUpdated(rows) };
}

export async function fetchSyncDiagnostics(
  api: ApiClient,
  user: Pick<ApiUser, "id" | "email">,
  profile: { school_name?: string | null; role?: string } | null,
): Promise<SyncDiagnostic> {
  const hints: string[] = [];
  const [stats, lastCloudUpdate, ...tableSamples] = await Promise.all([
    fetchDashboardStats(api),
    fetchCloudLastUpdated(api),
    tableDiagnostic(api, "sections"),
    tableDiagnostic(api, "students"),
    tableDiagnostic(api, "subjects"),
    tableDiagnostic(api, "scan_results"),
  ]);

  if (stats.sectionCount === 0 && stats.studentCount === 0 && stats.subjectCount === 0) {
    hints.push("Cloud is empty for this account. On your phone: Settings → Sync Now (Wi‑Fi on).");
    hints.push(`Make sure the phone app is signed in as ${user.email ?? "this same email"}.`);
  } else if (stats.sectionCount > 0 && stats.studentCount === 0) {
    hints.push("Sections exist but no students in cloud. Re-run Sync Now on the phone.");
  }

  if (!lastCloudUpdate) {
    hints.push("No updated_at timestamps found yet — data may not have synced.");
  }

  return {
    ok: stats.studentCount > 0 || stats.subjectCount > 0 || stats.scanCount > 0,
    userId: user.id,
    email: user.email ?? null,
    schoolName: profile?.school_name ?? null,
    role: profile?.role ?? null,
    stats,
    lastCloudUpdate,
    tableSamples,
    hints,
  };
}
