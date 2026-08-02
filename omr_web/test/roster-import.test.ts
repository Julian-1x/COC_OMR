import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { parseXlsxBuffer, previewImportRows } from "@/lib/import/roster";

/** Official PHINMA / COC Class_List_Report columns. */
const OFFICIAL_HEADERS = [
  "SESSION NAME",
  "CAMPUS",
  "STUDENT ID",
  "STUDENT NAME",
  "GENDER",
  "COLLEGE",
  "COURSE",
  "SUBJECT",
  "SECTION",
  "EMAIL",
] as const;

describe("roster import official Class_List_Report format", () => {
  it("keeps only student id, student name, and section from grid data", () => {
    const preview = previewImportRows([
      [...OFFICIAL_HEADERS],
      [
        "SY 26-27 SEM I",
        "Carmen Campus",
        "02-2024-12345",
        "Juan Dela Cruz",
        "Male",
        "CIT",
        "BSIT",
        "ITE 101",
        "BSIT-1A",
        "juan@example.com",
      ],
      [
        "SY 26-27 SEM I",
        "Carmen Campus",
        "02-2024-12346",
        "Maria Santos",
        "Female",
        "CIT",
        "BSIT",
        "ITE 101",
        "BSIT-1A",
        "maria@example.com",
      ],
    ]);

    expect(preview.errors).toEqual([]);
    expect(preview.rows).toEqual([
      {
        schoolId: "02-2024-12345",
        name: "Juan Dela Cruz",
        section: "BSIT-1A",
      },
      {
        schoolId: "02-2024-12346",
        name: "Maria Santos",
        section: "BSIT-1A",
      },
    ]);
  });

  it("does not treat COURSE as section", () => {
    const preview = previewImportRows([
      ["STUDENT ID", "STUDENT NAME", "COURSE", "SECTION"],
      ["02-2024-1", "Alex Cruz", "BSIT", "BSIT-1A"],
    ]);
    expect(preview.rows[0]?.section).toBe("BSIT-1A");
  });

  it("imports the real Class_List_Report-3.xlsx fixture", () => {
    const bytes = readFileSync(
      resolve(__dirname, "fixtures/Class_List_Report-3.xlsx"),
    );
    const raw = parseXlsxBuffer(
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
    );
    expect(raw[0]?.map(String)).toEqual([...OFFICIAL_HEADERS]);

    const preview = previewImportRows(raw);
    expect(preview.errors).toEqual([]);
    expect(preview.rows.length).toBe(42);
    expect(preview.rows[0]).toMatchObject({
      schoolId: "02-2324-01002",
      name: "ADAJAR, JAYCKOUZZ EMANN DAGAWASAN",
      section: "COC-FA-ME2-02",
    });
  });
});
