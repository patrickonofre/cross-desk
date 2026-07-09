#!/usr/bin/env node
// check-i18n-parity.mjs — bilingual release gate for the marketing site.
// Adapted from mac-metrics-view/scripts/check-i18n-parity.mjs (same logic,
// this repo's paths). Asserts:
//   (a) the pt and en dictionaries in docs/i18n.js have identical key sets;
//   (b) every data-i18n / data-i18n-alt key referenced in docs/index.html
//       exists in BOTH pt and en.
// Exits non-zero on any missing or mismatched key. Unused dictionary keys are
// reported as info only (not fatal).
//
// Usage: node scripts/check-i18n-parity.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const require = createRequire(import.meta.url);
const { STRINGS } = require(join(root, "docs/i18n.js"));
const html = readFileSync(join(root, "docs/index.html"), "utf8");

const ptKeys = new Set(Object.keys(STRINGS.pt));
const enKeys = new Set(Object.keys(STRINGS.en));

const referenced = new Set();
for (const m of html.matchAll(/data-i18n(?:-alt)?="([^"]+)"/g)) {
  referenced.add(m[1]);
}

const errors = [];

for (const k of ptKeys) if (!enKeys.has(k)) errors.push(`key "${k}" in pt but missing from en`);
for (const k of enKeys) if (!ptKeys.has(k)) errors.push(`key "${k}" in en but missing from pt`);

for (const k of referenced) {
  if (!ptKeys.has(k)) errors.push(`index.html references "${k}" — missing from pt`);
  if (!enKeys.has(k)) errors.push(`index.html references "${k}" — missing from en`);
}

const unused = [...ptKeys].filter((k) => !referenced.has(k));

console.log(
  `i18n: ${ptKeys.size} pt keys, ${enKeys.size} en keys, ${referenced.size} referenced in index.html`,
);
if (unused.length) console.log(`  (info) ${unused.length} dictionary keys not referenced in markup: ${unused.join(", ")}`);

if (errors.length) {
  console.error(`✗ i18n parity FAILED (${errors.length}):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
console.log("✓ i18n parity OK — pt/en key sets identical and every referenced key resolves in both.");
