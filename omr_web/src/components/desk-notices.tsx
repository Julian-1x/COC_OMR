import Link from "next/link";
import { cn } from "@/lib/utils";

/** Sync reminder for prepare / classes / results. */
export function SyncLoopNotice({ className = "" }: { className?: string }) {
  return (
    <p
      className={cn(
        "desk-enter inline-flex flex-wrap items-center gap-x-1 rounded-xl border border-emerald-100 bg-emerald-50/80 px-3 py-2 text-sm text-emerald-950",
        className,
      )}
    >
      After changes, tap <strong>Sync Now</strong> on the phone (Wi‑Fi).{" "}
      <Link href="/dashboard/settings" className="font-semibold text-emerald-800 underline-offset-2 hover:underline">
        Sync help
      </Link>
    </p>
  );
}

/** Results that still need phone review. */
export function PendingReviewNotice({
  count,
  className = "",
}: {
  count: number;
  className?: string;
}) {
  if (count <= 0) return null;
  return (
    <div
      className={cn(
        "desk-enter rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-950",
        className,
      )}
    >
      <strong>
        {count} scan{count === 1 ? "" : "s"} need Review on the phone
      </strong>{" "}
      before grades are final.
    </div>
  );
}
