# Deliverable: Format-matched Chapters 1–4

## Primary file

**[COC_OMR_Chapters_1_4_REVISED.docx](../COC_OMR_Chapters_1_4_REVISED.docx)**

Contains revised Chapters 1–3 (aligned to the real COC OMR system) plus Chapter 4 (OMR content, Chapter 4 PDF used only as section skeleton). Tables are real Word tables with borders—not plain paragraphs.

## Format specification (from original Ch1–3 PDF)

See [FORMAT_SPEC.md](FORMAT_SPEC.md).

Measured rules applied:

| Rule | Value used in DOCX |
|------|--------------------|
| Page | A4, 1" margins |
| Header | `Cagayan de Oro College \| College of Information Technology Education`, Times New Roman Bold 12 |
| Body | Times New Roman 12, Exactly 27.6 pt line spacing, 0.5" first-line indent |
| Chapter titles | Centered, Bold 12, ALL CAPS |
| Section headings | Left, Bold 12 |
| Figure captions | Centered, Arial 11 |
| Lists | 18 pt left indent |
| Tables | Table Grid, Times New Roman 12, bold header row, single borders |
| Page numbers | Centered footer |

Exact embedded PDF font file names remain **NEEDS VERIFICATION** beyond serif/sans; Times New Roman is the mapped institutional serif.

## Source content

- [chapter1_3_camera_ready.md](chapter1_3_camera_ready.md) — revised Ch1–3 without editorial change-log
- [chapter4_camera_ready.md](chapter4_camera_ready.md) — OMR Chapter 4 with placeholders for unmeasured metrics
- Rebuild: `powershell -File build_thesis_docx.ps1`

## What you still paste into the full thesis

This DOCX is **chapters body only** (not title page, approval sheet, TOC, or appendices). Copy into your master manuscript, or replace Chapters 1–4 there.

## Chapter 4 placeholders

Do not invent numbers. Replace `[Insert …]` cells after you encode ISO/SUS/test logs, or delete those numeric tables if unmeasured.
