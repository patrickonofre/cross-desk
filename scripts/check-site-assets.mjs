#!/usr/bin/env node
// check-site-assets.mjs — asset gate for the CrossDesk marketing site.
// Simpler than mac-metrics-view's version: this site has no popover
// screenshots (SVG placeholders inline in docs/index.html instead — see
// .specs/features/site-produto/design.md). Only checks the app icon:
//   • file exists
//   • valid PNG
//   • matches the manifest's pixel size
//   • under its byte budget
//
// Usage: node scripts/check-site-assets.mjs
import { readFileSync, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(
  readFileSync(join(root, "scripts/site-assets-manifest.json"), "utf8"),
);
const assetsDir = join(root, manifest.assetsDir);

const failures = [];
const fail = (m) => failures.push(m);

function pngSize(path) {
  const buf = readFileSync(path);
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buf.length < 24 || !buf.subarray(0, 8).equals(sig)) return null;
  if (buf.subarray(12, 16).toString("ascii") !== "IHDR") return null;
  return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
}

const iconPath = join(assetsDir, manifest.icon.file);
if (!existsSync(iconPath)) {
  fail(`MISSING: ${manifest.assetsDir}/${manifest.icon.file}`);
} else {
  const kb = statSync(iconPath).size / 1024;
  if (kb > manifest.byteBudgetKB.icon) {
    fail(`OVER BUDGET: ${manifest.icon.file} is ${kb.toFixed(0)}KB (budget ${manifest.byteBudgetKB.icon}KB)`);
  }
  const size = pngSize(iconPath);
  if (!size) {
    fail(`NOT A VALID PNG: ${manifest.icon.file}`);
  } else if (size[0] !== manifest.icon.width || size[1] !== manifest.icon.height) {
    fail(`BAD DIMENSIONS: ${manifest.icon.file} is ${size[0]}x${size[1]}, expected ${manifest.icon.width}x${manifest.icon.height}`);
  }
}

if (failures.length) {
  console.error(`✗ site-assets check FAILED (${failures.length}):`);
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log("✓ site-assets OK — app icon present, valid, and within budget.");
