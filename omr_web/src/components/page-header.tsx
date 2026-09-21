import { cn } from "@/lib/utils";
import type { ReactNode } from "react";

/** One strong page title; keep supporting text short. */
export function PageHeader({
  title,
  description,
  actions,
  className,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "desk-enter mb-5 flex flex-wrap items-end justify-between gap-3",
        className,
      )}
    >
      <div className="min-w-0">
        <h1 className="text-2xl font-extrabold tracking-tight text-slate-800 sm:text-3xl">
          {title}
        </h1>
        {description ? (
          <p className="mt-1 max-w-xl text-sm text-slate-500">{description}</p>
        ) : null}
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}
