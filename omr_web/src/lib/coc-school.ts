/** Canonical school identity for this COC deployment. */
export const COC_SCHOOL_NAME = "Cagayan de Oro College";

/** COC academic departments shown on registration. */
export const COC_DEPARTMENTS = [
  "COE",
  "SCCJ",
  "CMA",
  "CIT",
  "CEA",
  "CAHS",
] as const;

export type CocDepartment = (typeof COC_DEPARTMENTS)[number];

export function isCocDepartment(value: string): value is CocDepartment {
  return (COC_DEPARTMENTS as readonly string[]).includes(value);
}
