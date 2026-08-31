import { describe, expect, it } from "vitest";
import { normalizePersonName, normalizePersonNameFromParts } from "@/lib/person-name";

describe("normalizePersonName", () => {
  it("title-cases plain names", () => {
    expect(normalizePersonName("maria santos")).toBe("Maria Santos");
    expect(normalizePersonName("  ALEXANDER   JULIAN   BALABA  ")).toBe(
      "Alexander Julian Balaba",
    );
  });

  it("reorders Last, First to First Last", () => {
    expect(normalizePersonName("Santos, Maria")).toBe("Maria Santos");
    expect(normalizePersonName("Balaba, Alexander Julian")).toBe("Alexander Julian Balaba");
  });

  it("lowercases name particles", () => {
    expect(normalizePersonName("MARIA DE LA CRUZ")).toBe("Maria de la Cruz");
  });
});

describe("normalizePersonNameFromParts", () => {
  it("combines first and last into normalized full name", () => {
    expect(normalizePersonNameFromParts("maria", "santos")).toBe("Maria Santos");
    expect(normalizePersonNameFromParts("ALEXANDER", "BALABA")).toBe("Alexander Balaba");
  });

  it("returns empty when either part is missing", () => {
    expect(normalizePersonNameFromParts("", "Santos")).toBe("");
    expect(normalizePersonNameFromParts("Maria", "  ")).toBe("");
  });
});
