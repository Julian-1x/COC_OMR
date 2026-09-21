# FORMAT SPECIFICATION — Derived from Chapters 1–3 PDF

Source: `D:\DOWNLOADS\OPTICAL-MARK-RECOGNITION-OMR-PAPER (1).pdf`  
Method: pdf.js text + transform metrics (not assumed APA defaults)

## PAGE

| Property | Measured value |
|----------|----------------|
| Paper size | A4 — width **596 pt**, height **842 pt** (≈ 210 × 297 mm) |
| Left margin | **72 pt** (1.0 in) — body text x₀ = 72 |
| Right margin | **≈ 72 pt** (1.0 in) — inferred from page width and text wrap |
| Top content start | Body/header band ≈ **47 pt** from top (header baseline y ≈ 794.8) |
| Bottom | Page number baseline y ≈ **37.7–38.3** |
| Orientation | Portrait |

## HEADER

| Property | Value |
|----------|-------|
| Text | `Cagayan de Oro College \| College of Information Technology Education` |
| Position | Left, x = 72 |
| Font | Serif, **12 pt**, bold style (PDF font id `g_d0_f1`) |
| Mapped Word font | **Times New Roman** (serif; exact embedded PostScript name = NEEDS VERIFICATION beyond family=serif) |

## FOOTER / PAGE NUMBERS

| Property | Value |
|----------|-------|
| Position | Centered near bottom |
| Font | Serif, **12 pt**, regular (`g_d0_f2`) |
| Style | Roman numerals for front matter (II, III…); Arabic for body (1, 2, 3…) |

## FONTS (body document)

| Role | PDF id | Family | Size | Word mapping |
|------|--------|--------|------|--------------|
| Header / chapter title / section heading | `g_d0_f1` | serif | 12 pt | Times New Roman **Bold** |
| Body text | `g_d0_f2` | serif | 12 pt | Times New Roman Regular |
| Occasional hyphen/special glyph | `g_d0_f3` | sans-serif | 12 pt | Keep body as Times; specials incidental |
| Figure caption | `g_d0_f4` | sans-serif | **11 pt** | Arial or Calibri 11 — **NEEDS VERIFICATION** of exact face; size **11 pt** verified |
| Bullet glyph | `g_d0_f5` | sans-serif | **10 pt** | Symbol/bullet at 10 pt; following text 12 pt serif |

**Note:** Exact typeface name inside the PDF is obfuscated (`g_d0_f*`). Family is serif for body/headings. Times New Roman is the faithful institutional match; if the original .docx used a different serif (e.g., Liberation Serif), that is **NEEDS VERIFICATION**.

## PARAGRAPHS

| Property | Measured value |
|----------|----------------|
| Alignment | Left (not fully justified in PDF text positions) — **NEEDS VERIFICATION** if Word source was Justify |
| Font | 12 pt serif |
| Line spacing (within paragraph) | Baseline gap **27.6 pt** → Word **Exactly 27.6 pt** |
| First-line indent | **36 pt** (0.5 in) — first line at x = 108, continuation at x = 72 |
| Space before section heading → body | ≈ **39.6 pt** baseline gap (heading to first line) |
| Space between paragraphs | ≈ **39.6 pt** baseline gap (last line → next first line) ≈ one blank double-spaced line |
| Space after chapter title block | Chapter number → subtitle ≈ **13.8 pt**; subtitle → first section ≈ **27.6 pt** |

## HEADINGS HIERARCHY

Observed pattern (Chapters 1–3):

1. **CHAPTER n** — centered, Bold, 12 pt, ALL CAPS  
2. **CHAPTER TITLE** (e.g., `THE PROBLEM`, `METHODOLOGY`) — centered, Bold, 12 pt, ALL CAPS  
3. **Section heading** (e.g., `Introduction`, `Research Design`) — left, Bold, 12 pt, Title Case — **not** numbered as 1.1 / 1.2 in the body  
4. **Subsection** (e.g., `System Analysis`, `Functional Requirements`) — left, Bold, 12 pt, Title Case  

Chapter 4 in the OMR rewrite uses `4.1`, `4.1.1` numbering (from the Chapter 4 template). To stay visually consistent with Ch1–3 **typography**, keep Bold 12 pt serif, left-aligned; keep the `4.x` numbering from the Chapter 4 materials because that chapter’s content structure uses it.

## LISTS

| Type | Indent |
|------|--------|
| Numbered item first line | x ≈ **90** (18 pt from left margin) |
| Numbered item wrap line | x ≈ **108** (0.5 in) |
| Bullet first line | x ≈ **90**; bullet glyph ~10 pt |

## FIGURE CAPTIONS

- Example: `Figure 1. The IPO framework of the System`
- Size **11 pt**, sans-serif in PDF
- Appears centered under figure area

## TABLES (from Ch3 architecture / DB / tech stack)

Chapters 1–3 contain simple bordered data tables (Component/Description; Database/Technology/Purpose; Layer/Technology/Version). Exact border width in PDF is **NEEDS VERIFICATION** visually; structure is:

- Header row: Bold labels  
- Body: Regular 12 pt serif  
- Full grid borders (text is cell-separated in PDF)  
- Table sits within left/right margins  
- No fancy shading observed in text layer  

Chapter 4 must use **real Word tables** with borders (not paragraph mockups), matching this simple grid style.

## CHAPTER START

- New chapter begins on a new page (CHAPTER 1 starts at top of content page after front matter).
- Header repeats on every content page.

## WHAT WAS NOT VERIFIABLE FROM PDF ALONE

- Exact PostScript/TrueType font file name beyond serif/sans  
- Exact border stroke width in points  
- Whether body is Justified in the original Word file (PDF shows left-ragged or uneven spacing artifacts)  
- Gutter / mirror margins (none apparent)

---

This specification is the visual standard for the generated Chapters 1–4 Word document.
