import type { SupabaseClient } from "@supabase/supabase-js";
import { fetchCloudLastUpdated, fetchDashboardStats } from "@/lib/api/data";

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

async function tableDiagnostic(
  supabase: SupabaseClient,
  table: "sections" | "students" | "subjects" | "scan_results",
) {
  const { count, error: countError } = await supabase
    .from(table)
    .select("*", { count: "exact", head: true });
  if (countError) throw countError;

  const { data, error: sampleError } = await supabase
    .from(table)
    .select("updated_at")
    .order("updated_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (sampleError) throw sampleError;

  return {
    table,
    count: count ?? 0,
    latestUpdated: data?.updated_at ? String(data.updated_at) : null,
  };
}

export async function fetchSyncDiagnostics(
  supabase: SupabaseClient,
  user: { id: string; email?: string | null },
  profile: { school_name?: string | null; role?: string } | null,
): Promise<SyncDiagnostic> {
  const hints: string[] = [];
  const [stats, lastCloudUpdate, ...tableSamples] = await Promise.all([
    fetchDashboardStats(supabase),
    fetchCloudLastUpdated(supabase),
    tableDiagnostic(supabase, "sections"),
    tableDiagnostic(supabase, "students"),
    tableDiagnostic(supabase, "subjects"),
    tableDiagnostic(supabase, "scan_results"),
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
