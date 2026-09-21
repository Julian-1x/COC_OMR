import fs from "fs";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const pdfjs = require("pdfjs-dist/legacy/build/pdf.mjs");

const pdfPath = "D:\\DOWNLOADS\\OPTICAL-MARK-RECOGNITION-OMR-PAPER (1).pdf";
const data = new Uint8Array(fs.readFileSync(pdfPath));
const doc = await pdfjs.getDocument({ data, useSystemFonts: true }).promise;

const out = [];

// Inspect fonts on page 7 (CHAPTER 1 body) and page 32 (tables)
for (const pnum of [7, 8, 9, 31, 32, 38]) {
  const page = await doc.getPage(pnum);
  const viewport = page.getViewport({ scale: 1 });
  const content = await page.getTextContent({ includeMarkedContent: true });
  const styles = content.styles;

  out.push(`\n======== PAGE ${pnum} ${viewport.width}x${viewport.height} ========`);
  out.push("STYLES:");
  for (const [id, st] of Object.entries(styles)) {
    out.push(
      `  ${id} family=${st.fontFamily} ascent=${st.ascent} descent=${st.descent} vertical=${st.vertical}`,
    );
  }

  // Sort items by y desc then x
  const items = content.items
    .filter((i) => i.str && i.str.trim())
    .map((i) => {
      const t = i.transform;
      return {
        str: i.str,
        x: +t[4].toFixed(2),
        y: +t[5].toFixed(2),
        size: +Math.hypot(t[2], t[3]).toFixed(2),
        font: i.fontName,
        width: +(i.width || 0).toFixed(2),
      };
    })
    .sort((a, b) => b.y - a.y || a.x - b.x);

  // Group into lines by y bucket
  const lines = [];
  for (const it of items) {
    const last = lines[lines.length - 1];
    if (last && Math.abs(last.y - it.y) < 1.5) {
      last.parts.push(it);
      last.text += it.str;
    } else {
      lines.push({ y: it.y, parts: [it], text: it.str, x: it.x, size: it.size, font: it.font });
    }
  }

  out.push("LINES (top 35):");
  for (const ln of lines.slice(0, 35)) {
    const fonts = [...new Set(ln.parts.map((p) => `${p.font}@${p.size}`))].join(",");
    const xs = ln.parts.map((p) => p.x);
    out.push(
      `  y=${ln.y.toFixed(1)} x0=${Math.min(...xs).toFixed(1)} sz=${ln.size} fonts=${fonts} | ${ln.text.slice(0, 110)}`,
    );
  }

  // line spacing between consecutive body lines (x0 around 72)
  const body = lines.filter((l) => l.x < 90 && l.size >= 11.5 && l.size <= 12.5);
  const gaps = [];
  for (let i = 0; i < body.length - 1; i++) {
    const g = body[i].y - body[i + 1].y;
    if (g > 5 && g < 40) gaps.push(+g.toFixed(2));
  }
  const gapHist = {};
  for (const g of gaps) gapHist[g] = (gapHist[g] || 0) + 1;
  out.push("BODY_GAPS: " + JSON.stringify(gapHist));

  // first-line indent detection: paragraphs where first line x > 72+10
  const bodyLines = lines.filter((l) => l.size >= 11.5 && l.size <= 12.5);
  const indents = bodyLines
    .filter((l) => l.x > 85 && l.x < 130)
    .slice(0, 15)
    .map((l) => `x=${l.x.toFixed(1)} | ${l.text.slice(0, 60)}`);
  out.push("POSSIBLE_INDENTS:\n  " + indents.join("\n  "));
}

// Also dump raw font names from PDF objects via page commonObjs if available
const page7 = await doc.getPage(7);
try {
  const opList = await page7.getOperatorList();
  out.push("\nOPS count=" + opList.fnArray.length);
} catch (e) {
  out.push("opList err " + e.message);
}

fs.writeFileSync("format_detail.txt", out.join("\n"), "utf8");
console.log(out.join("\n"));
