import { cn } from "@/lib/utils";
import type { ReactNode } from "react";

export function Card({
  children,
  className,
  title,
  subtitle,
}: {
  children: ReactNode;
  className?: string;
  title?: string;
  subtitle?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-2xl border border-slate-200 bg-white p-5 shadow-sm",
        className,
      )}
    >
      {title ? (
        <div className="mb-3">
          <h2 className="text-base font-extrabold text-slate-800">{title}</h2>
          {subtitle ? <p className="mt-0.5 text-sm text-slate-500">{subtitle}</p> : null}
        </div>
      ) : null}
      {children}
    </div>
  );
}

export function StatCard({
  label,
  value,
  hint,
  className,
}: {
  label: string;
  value: string | number;
  hint?: string;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "rounded-xl border border-emerald-100 bg-emerald-50/70 px-3 py-2.5 sm:px-4 sm:py-3",
        className,
      )}
    >
      <p className="text-[10px] font-bold uppercase tracking-wide text-emerald-800/70 sm:text-xs">
        {label}
      </p>
      <p className="mt-0.5 text-xl font-extrabold tabular-nums text-slate-800 sm:text-2xl">
        {value}
      </p>
      {hint ? <p className="mt-0.5 text-[11px] font-semibold text-amber-800">{hint}</p> : null}
    </div>
  );
}
