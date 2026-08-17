/** Cloud password rules — must match Laravel Password::defaults(). */
export const PASSWORD_MIN_LENGTH = 8;

export const PASSWORD_REQUIREMENT_HINT =
  "At least 8 characters, with a letter, a number, and a symbol (e.g. !@#$)";

const letterRe = /[A-Za-z]/;
const digitRe = /[0-9]/;
const symbolRe = /[^A-Za-z0-9]/;

/** Null when valid; otherwise a teacher-facing error. */
export function passwordValidationError(password: string): string | null {
  if (password.length < PASSWORD_MIN_LENGTH) {
    return `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`;
  }
  if (!letterRe.test(password)) {
    return "Password must include at least one letter.";
  }
  if (!digitRe.test(password)) {
    return "Password must include at least one number.";
  }
  if (!symbolRe.test(password)) {
    return "Password must include at least one special character (e.g. !@#$).";
  }
  return null;
}

export function isValidPassword(password: string): boolean {
  return passwordValidationError(password) === null;
}
