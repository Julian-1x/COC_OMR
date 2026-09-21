import { createRequire } from "module";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const require = createRequire(path.join(root, "paper_format_extract/package.json"));
const { createCanvas } = require("@napi-rs/canvas");

const GREEN_BG = "#064E3B";
const GREEN_DARK = "#065F46";
const GREEN_MID = "#047857";
const GREEN_LIME = "#34D399";
const GREEN_SCAN = "#10B981";
const WHITE = "#FFFFFF";

function roundRect(ctx, x, y, w, h, r) {
  const rr = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + rr, y);
  ctx.arcTo(x + w, y, x + w, y + h, rr);
  ctx.arcTo(x + w, y + h, x, y + h, rr);
  ctx.arcTo(x, y + h, x, y, rr);
  ctx.arcTo(x, y, x + w, y, rr);
  ctx.closePath();
}

function drawIcon(size, { withText = false } = {}) {
  const canvas = createCanvas(size, size);
  const ctx = canvas.getContext("2d");

  ctx.fillStyle = GREEN_BG;
  ctx.fillRect(0, 0, size, size);

  const pad = size * 0.12;
  const tile = size - pad * 2;
  const tileY = withText ? size * 0.1 : pad;
  const tileX = pad;
  const tileH = withText ? tile * 0.72 : tile;

  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.28)";
  ctx.shadowBlur = size * 0.04;
  ctx.shadowOffsetY = size * 0.015;
  ctx.fillStyle = WHITE;
  roundRect(ctx, tileX, tileY, tile, tileH, size * 0.12);
  ctx.fill();
  ctx.restore();

  ctx.fillStyle = WHITE;
  roundRect(ctx, tileX, tileY, tile, tileH, size * 0.12);
  ctx.fill();

  const inset = tile * 0.14;
  const sheetX = tileX + inset;
  const sheetY = tileY + inset;
  const sheetW = tile - inset * 2;
  const sheetH = tileH - inset * 2;
  ctx.strokeStyle = GREEN_DARK;
  ctx.lineWidth = Math.max(3, size * 0.012);
  ctx.lineJoin = "round";
  roundRect(ctx, sheetX, sheetY, sheetW, sheetH, size * 0.035);
  ctx.stroke();

  const cols = 4;
  const rows = 4;
  const gap = sheetW * 0.08;
  const usableW = sheetW - gap * 2;
  const usableH = sheetH - gap * 2;
  const cellW = usableW / cols;
  const cellH = usableH / rows;
  const diameter = Math.min(cellW, cellH) * 0.62;
  const filled = new Set(["0,0", "1,2", "2,1", "3,3"]);

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const cx = sheetX + gap + cellW * (c + 0.5);
      const cy = sheetY + gap + cellH * (r + 0.5);
      const key = `${r},${c}`;
      if (filled.has(key)) {
        ctx.fillStyle = GREEN_DARK;
        ctx.beginPath();
        ctx.arc(cx, cy, diameter / 2, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.strokeStyle = GREEN_MID;
        ctx.lineWidth = Math.max(2.5, size * 0.009);
        ctx.beginPath();
        ctx.arc(cx, cy, diameter / 2, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
  }

  const scanY = sheetY + sheetH * 0.52;
  ctx.save();
  ctx.strokeStyle = "rgba(16,185,129,0.28)";
  ctx.lineWidth = Math.max(8, size * 0.028);
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(sheetX + sheetW * 0.08, scanY);
  ctx.lineTo(sheetX + sheetW * 0.92, scanY);
  ctx.stroke();
  ctx.strokeStyle = GREEN_SCAN;
  ctx.lineWidth = Math.max(3, size * 0.012);
  ctx.beginPath();
  ctx.moveTo(sheetX + sheetW * 0.08, scanY);
  ctx.lineTo(sheetX + sheetW * 0.92, scanY);
  ctx.stroke();
  ctx.fillStyle = GREEN_LIME;
  ctx.beginPath();
  ctx.arc(sheetX + sheetW * 0.92, scanY, Math.max(3, size * 0.012), 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  if (withText) {
    ctx.fillStyle = "#ECFDF5";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const fontSize = Math.round(size * 0.11);
    ctx.font = `700 ${fontSize}px Segoe UI, Arial, sans-serif`;
    ctx.fillText("COC OMR", size / 2, tileY + tileH + (size - (tileY + tileH)) * 0.55);
  }

  return canvas.toBuffer("image/png");
}

const outIcon = path.join(root, "assets/app_icon.png");
const outSource = path.join(root, "assets/app_icon_source.png");
const outLogo = path.join(root, "assets/logo.png");

fs.writeFileSync(outIcon, drawIcon(1024, { withText: false }));
fs.writeFileSync(outSource, drawIcon(1024, { withText: false }));
fs.writeFileSync(outLogo, drawIcon(1024, { withText: true }));
console.log("Wrote", outIcon);
console.log("Wrote", outSource);
console.log("Wrote", outLogo);
