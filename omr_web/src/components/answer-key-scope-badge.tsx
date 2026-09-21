import { answerKeyScopeOf, type AnswerKeyScopeInput } from "@/lib/omr/answer-key-scope";
import { cn } from "@/lib/utils";

export function AnswerKeyScopeBadge({
  subject,
  className,
  showSubtitle = false,
}: {
  subject: AnswerKeyScopeInput;
  className?: string;
  showSubtitle?: boolean;
}) {
  const scope = answerKeyScopeOf(subject);
  const tone =
    scope.kind === "shared"
      ? "bg-emerald-100 text-emerald-900 ring-emerald-200"
      : scope.kind === "sectionOnly"
        ? "bg-amber-100 text-amber-950 ring-amber-200"
        : "bg-slate-100 text-slate-700 ring-slate-200";

  return (
    <div className={cn("min-w-0", className)}>
      <span
        className={cn(
          "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold ring-1 ring-inset",
          tone,
        )}
      >
        {scope.badgeLabel}
      </span>
      {showSubtitle ? (
        <p className="mt-1 text-xs leading-snug text-slate-500">{scope.listSubtitle}</p>
      ) : null}
    </div>
  );
}
