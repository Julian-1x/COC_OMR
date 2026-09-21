import { cn } from "@/lib/utils";
import type { ButtonHTMLAttributes } from "react";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "md" | "lg";

const variants: Record<Variant, string> = {
  primary:
    "bg-emerald-500 text-white hover:bg-emerald-600 shadow-sm disabled:bg-emerald-300",
  secondary:
    "border border-emerald-200 bg-white text-emerald-800 hover:bg-emerald-50",
  ghost: "text-emerald-800 hover:bg-emerald-50",
  danger: "bg-red-600 text-white hover:bg-red-700",
};

const sizes: Record<Size, string> = {
  md: "min-h-11 px-4 text-sm",
  lg: "min-h-12 px-5 text-base shadow-md",
};

/** Shared look for Link CTAs that match Button size=lg primary. */
export const primaryActionClassName =
  "inline-flex min-h-12 items-center justify-center gap-2 rounded-2xl bg-emerald-500 px-5 text-base font-extrabold text-white shadow-md transition hover:bg-emerald-600";

export const secondaryActionClassName =
  "inline-flex min-h-12 items-center justify-center gap-2 rounded-2xl border border-emerald-200 bg-white px-5 text-base font-extrabold text-emerald-800 transition hover:bg-emerald-50";

export function Button({
  className,
  variant = "primary",
  size = "md",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  size?: Size;
}) {
  return (
    <button
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-2xl font-extrabold transition disabled:cursor-not-allowed",
        variants[variant],
        sizes[size],
        className,
      )}
      {...props}
    />
  );
}
