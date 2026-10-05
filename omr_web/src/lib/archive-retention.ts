/** Soft-archived classes/students are permanently deleted after this many months. */
export const ARCHIVE_RETENTION_MONTHS = 4;

export function archiveDeleteAfter(archivedAtIso: string | null | undefined): Date | null {
  if (!archivedAtIso) return null;
  const archived = new Date(archivedAtIso);
  if (Number.isNaN(archived.getTime())) return null;
  const out = new Date(archived);
  out.setMonth(out.getMonth() + ARCHIVE_RETENTION_MONTHS);
  return out;
}

export function archiveRetentionLabel(archivedAtIso: string | null | undefined): string | null {
  const deleteAfter = archiveDeleteAfter(archivedAtIso);
  if (!deleteAfter) return null;
  const ms = deleteAfter.getTime() - Date.now();
  if (ms <= 0) return "Due for permanent delete";
  const days = Math.ceil(ms / (24 * 60 * 60 * 1000));
  if (days <= 1) return "Deletes tomorrow if not restored";
  if (days < 45) return `Deletes in ${days} days if not restored`;
  const months = Math.max(1, Math.round(days / 30));
  return `Deletes in ~${months} month${months === 1 ? "" : "s"} if not restored`;
}
