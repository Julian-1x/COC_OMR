/** Cloud password rules — must match Laravel Password::defaults(). */
export const PASSWORD_MIN_LENGTH = 8;

export const PASSWORD_REQUIREMENT_HINT =
  "At least 8 characters, with upper and lowercase letters, a number, and a symbol (e.g. !@#$)";

export type PasswordRequirementId =
  | "length"
  | "lowercase"
  | "uppercase"
  | "number"
  | "symbol";

export type PasswordRequirement = {
  id: PasswordRequirementId;
  label: string;
};

export const PASSWORD_REQUIREMENTS: PasswordRequirement[] = [
  { id: "length", label: "Minimum of 8 characters" },
  { id: "lowercase", label: "At least 1 lowercase letter (a-z)" },
  { id: "uppercase", label: "At least 1 uppercase letter (A-Z)" },
  { id: "number", label: "At least 1 number" },
  {
    id: "symbol",
    label: "At least 1 special character (e.g. ! @ # $ %)",
  },
];

const lowercaseRe = /[a-z]/;
const uppercaseRe = /[A-Z]/
const digitRe = /[0-9]/
const symbolRe = /[^A-Za-z0-9]/;

export function passwordMeets(id: PasswordRequirementId, password: string): boolean {
  switch (id) {
    case "length":
      return password.length >= PASSWORD_MIN_LENGTH;
    case "lowercase":
      return lowercaseRe.test(password);
    case "uppercase":
      return uppercaseRe.test(password);
    case "number":
      return digitRe.test(password);
    case "symbol":
      return symbolRe.test(password);
    default:
      return false;
  }
}

/** Null when valid; otherwise a teacher-facing error. */
export function passwordValidationError(password: string): string | null {
  for (const requirement of PASSWORD_REQUIREMENTS) {
    if (!passwordMeets(requirement.id, password)) {
      switch (requirement.id) {
        case "length":
          return `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`;
        case "lowercase":
          return "Password must include at least one lowercase letter.";
        case "uppercase":
          return "Password must include at least one uppercase letter.";
        case "number":
          return "Password must include at least one number.";
        case "symbol":
          return "Password must include at least one special character (e.g. !@#$).";
      }
    }
  }
  return null;
}

export function isValidPassword(password: string): boolean {
  return passwordValidationError(password) === null;
}
