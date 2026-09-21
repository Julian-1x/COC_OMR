import fs from "fs";
import path from "path";
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const pdfjs = require("pdfjs-dist/legacy/build/pdf.mjs");

const pdfPath =
  process.argv[2] ||
  "D:\\DOWNLOADS\\OPTICAL-MARK-RECOGNITION-OMR-PAPER (1).pdf";

const data = new Uint8Array(fs.readFileSync(pdfPath));
const doc = await pdfjs.getDocument({ data, useSystemFonts: true }).promise;

const out = [];
out.push(`PAGES=${doc.numPages}`);

const fontHist = new Map();
const sizeHist = new Map();
const samples = [];

function keyFont(name, size) {
  return `${name}|${size.toFixed(1)}`;
}

for (let p = 1; p <= Math.min(doc.numPages, 40); p++) {
  const page = await doc.getPage(p);
  const viewport = page.getViewport({ scale: 1 });
  const content = await page.getTextContent();
  const styles = content.styles || {};

  out.push(
    `\n=== PAGE ${p} size=${viewport.width.toFixed(1)}x${viewport.height.toFixed(1)} items=${content.items.length} ===`,
  );

  // header candidates: top 8% of page
  const topY = viewport.height * 0.92;
  const bottomY = viewport.height * 0.08;

  for (const item of content.items) {
    if (!item.str || !item.str.trim()) continue;
    const tx = item.transform;
    const x = tx[4];
    const y = tx[5];
    const fontSize = Math.hypot(tx[2], tx[3]) || Math.hypot(tx[0], tx[1]);
    const style = styles[item.fontName] || {};
    const family = style.fontFamily || item.fontName || "?";
    const fontName = style.ascent ? item.fontName : item.fontName;
    const fk = keyFont(fontName, fontSize);
    fontHist.set(fk, (fontHist.get(fk) || 0) + 1);
    sizeHist.set(fontSize.toFixed(1), (sizeHist.get(fontSize.toFixed(1)) || 0) + item.str.length);

    const t = item.str.trim();
    const interesting =
      /^(CHAPTER\s+\d+|THE PROBLEM|Introduction|Statement of the Problem|METHODOLOGY|Research Design|Technology Stack|Database Design|Component|Local|Central|Assessment is an important|Cagayan de Oro College)/i.test(
        t,
      ) || t.length > 80;

    if (interesting || y > topY || y < bottomY) {
      samples.push({
        p,
        x: +x.toFixed(1),
        y: +y.toFixed(1),
        size: +fontSize.toFixed(2),
        font: fontName,
        family,
        text: t.slice(0, 140),
        region: y > topY ? "HEADER?" : y < bottomY ? "FOOTER?" : "BODY",
      });
    }
  }
}

out.push("\n=== FONT FREQUENCY (name|size -> count) ===");
[...fontHist.entries()]
  .sort((a, b) => b[1] - a[1])
  .slice(0, 40)
  .forEach(([k, v]) => out.push(`${v}\t${k}`));

out.push("\n=== SIZE BY CHAR COUNT ===");
[...sizeHist.entries()]
  .sort((a, b) => b[1] - a[1])
  .forEach(([k, v]) => out.push(`${v}\t${k}pt`));

out.push("\n=== INTERESTING SAMPLES ===");
for (const s of samples.slice(0, 200)) {
  out.push(
    `p${s.p} ${s.region} x=${s.x} y=${s.y} sz=${s.size} font=${s.font} fam=${s.family} | ${s.text}`,
  );
}

const dest = path.join(
  path.dirname(pdfPath.includes("DOWNLOADS") ? process.cwd() : process.cwd()),
  "format_from_pdf.txt",
);
const localDest = path.resolve("format_from_pdf.txt");
fs.writeFileSync(localDest, out.join("\n"), "utf8");
console.log(`Wrote ${localDest}`);
console.log(out.slice(0, 80).join("\n"));
