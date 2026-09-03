#!/usr/bin/env bun
/**
 * Wraps a JavaScript widget source into a valid stupid-widgets `.widget` JSON envelope.
 *
 * Usage:
 *   bun make_widget.mjs --name "My Widget" --script ./my-widget.js [--color purple] [--glyph sun] [-o output.widget]
 *
 * The id defaults to a fresh random UUID. The script text is read from --script and
 * JSON-escaped for you, so you can pass raw JS without worrying about quote/newline escaping.
 */
import { randomUUID } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

function usage() {
  console.error(
    "Usage: bun make_widget.mjs --name <name> --script <file.js> [--color <color>] [--glyph <glyph>] [-o <output.widget>]"
  );
  process.exit(1);
}

const argv = process.argv.slice(2);
function flag(name) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : undefined;
}

const name = flag("name");
const scriptPath = flag("script");
const color = flag("color") ?? "purple";
const glyph = flag("glyph") ?? "sun";
const outArg = argv.indexOf("-o") >= 0 ? argv[argv.indexOf("-o") + 1] : flag("output");
const out = outArg ?? flag("o") ?? (name ? `${name.replace(/[^\w-]+/g, "-")}.widget` : undefined);

if (!name || !scriptPath || !out) usage();
if (!/^[\w ]+$/.test(name.trim())) {
  console.error("Name must be non-empty and contain no path separators or colons.");
  process.exit(1);
}

const source = readFileSync(scriptPath, "utf8");
const envelope = {
  id: randomUUID(),
  name: name.trim(),
  icon: { color, glyph },
  script: source,
  always_run_in_app: false,
  preview_family: "medium",
  share_sheet_inputs: [],
};

writeFileSync(out, JSON.stringify(envelope, null, 2) + "\n");
console.log(`Wrote ${out}`);