"use client";

import { useId, useState } from "react";
import { Input, Label } from "@/components/ui/input";
import {
  PASSWORD_REQUIREMENTS,
  passwordMeets,
  type PasswordRequirementId,
} from "@/lib/auth/password-rules";
import { cn } from "@/lib/utils";

type PasswordFieldProps = {
  id?: string;
  /** When empty, no label is rendered (caller may supply its own). */
  label?: string;
  value: string;
  onChange: (value: string) => void;
  autoComplete?: string;
  required?: boolean;
  disabled?: boolean;
  readOnly?: boolean;
  minLength?: number;
  /** Show live green/gray requirement checklist under the field. */
  showChecklist?: boolean;
  className?: string;
};

function EyeIcon({ open }: { open: boolean }) {
  if (open) {
    return (
      <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" aria-hidden>
        <path
          d="M3 3l18 18M10.6 10.7a2 2 0 002.8 2.8M9.9 5.1A9.8 9.8 0 0112 5c5 0 9.3 3.1 11 7.5a11.5 11.5 0 01-4.2 5.1M6.1 6.1A11.5 11.5 0 001 12.5C2.7 16.9 7 20 12 20c1.7 0 3.3-.3 4.8-1"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" aria-hidden>
      <path
        d="M1 12.5C2.7 8.1 7 5 12 5s9.3 3.1 11 7.5C21.3 16.9 17 20 12 20S2.7 16.9 1 12.5z"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
      <circle cx="12" cy="12.5" r="3" stroke="currentColor" strokeWidth="1.8" />
    </svg>
  );
}

function StatusIcon({ met }: { met: boolean }) {
  if (met) {
    return (
      <span className="mt-0.5 inline-flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-emerald-600 text-white">
        <svg viewBox="0 0 16 16" className="h-3 w-3" fill="none" aria-hidden>
          <path
            d="M3.5 8.5l3 3 6-7"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </span>
    );
  }
  return (
    <span className="mt-0.5 inline-flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full bg-slate-400 text-white">
      <svg viewBox="0 0 16 16" className="h-3 w-3" fill="none" aria-hidden>
        <path
          d="M5 5l6 6M11 5l-6 6"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        />
      </svg>
    </span>
  );
}

export function PasswordRequirementsChecklist({ password }: { password: string }) {
  return (
    <ul className="mt-2 space-y-1.5">
      {PASSWORD_REQUIREMENTS.map((requirement) => {
        const met = passwordMeets(requirement.id as PasswordRequirementId, password);
        return (
          <li key={requirement.id} className="flex items-start gap-2 text-sm text-slate-700">
            <StatusIcon met={met} />
            <span>{requirement.label}</span>
          </li>
        );
      })}
    </ul>
  );
}

/** Password input with show/hide eye and optional live checklist. */
export function PasswordField({
  id,
  label,
  value,
  onChange,
  autoComplete = "current-password",
  required,
  disabled,
  readOnly,
  minLength,
  showChecklist = false,
  className,
}: PasswordFieldProps) {
  const generatedId = useId();
  const fieldId = id ?? generatedId;
  const [visible, setVisible] = useState(false);
  const locked = Boolean(disabled || readOnly);

  return (
    <div className={cn(className)}>
      {label ? <Label htmlFor={fieldId}>{label}</Label> : null}
      <div className="relative">
        <Input
          id={fieldId}
          type={visible ? "text" : "password"}
          autoComplete={autoComplete}
          value={value}
          onChange={(e) => {
            if (locked) return;
            onChange(e.target.value);
          }}
          required={required}
          disabled={disabled}
          readOnly={readOnly}
          minLength={minLength}
          className={cn("pr-20", locked && "cursor-default bg-slate-100 text-slate-600")}
        />
        <div className="absolute inset-y-0 right-1 flex items-center gap-0.5">
          {!locked && value.length > 0 ? (
            <button
              type="button"
              onClick={() => onChange("")}
              className="rounded-full p-2 text-slate-400 hover:bg-slate-100 hover:text-slate-600"
              aria-label="Clear password"
              tabIndex={-1}
            >
              <svg viewBox="0 0 20 20" className="h-4 w-4" fill="currentColor" aria-hidden>
                <path
                  fillRule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zm2.47-10.53a.75.75 0 10-1.06-1.06L10 8.94 8.59 7.41a.75.75 0 10-1.06 1.06L8.94 10l-1.41 1.53a.75.75 0 101.06 1.06L10 11.06l1.41 1.53a.75.75 0 101.06-1.06L11.06 10l1.41-1.53z"
                  clipRule="evenodd"
                />
              </svg>
            </button>
          ) : null}
          <button
            type="button"
            onClick={() => setVisible((v) => !v)}
            disabled={locked}
            className="rounded-full p-2 text-slate-500 hover:bg-slate-100 hover:text-slate-700 disabled:cursor-not-allowed disabled:opacity-40"
            aria-label={visible ? "Hide password" : "Show password"}
          >
            <EyeIcon open={visible} />
          </button>
        </div>
      </div>
      {showChecklist ? <PasswordRequirementsChecklist password={value} /> : null}
    </div>
  );
}
