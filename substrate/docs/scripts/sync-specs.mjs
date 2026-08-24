#!/usr/bin/env node
/*
 * Copy ../specs/**\/*.md into src/content/docs/specs/ so Starlight
 * can render them as doc pages. We inject minimal frontmatter
 * (title + description) derived from the first H1 and first
 * paragraph of each file.
 *
 * Run via `npm run sync`. Output is gitignored (see .gitignore).
 */
import { mkdir, readdir, readFile, writeFile, rm, stat } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SPEC_SRC = resolve(__dirname, "../../specs");
const SPEC_DST = resolve(__dirname, "../src/content/docs/specs");

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(full)));
    } else if (entry.isFile() && entry.name.endsWith(".md")) {
      files.push(full);
    }
  }
  return files;
}

function extractTitleAndLede(md) {
  const lines = md.split(/\r?\n/);
  let title = null;
  let lede = null;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!title && line.startsWith("# ")) {
      title = line.replace(/^#\s+/, "").trim();
      continue;
    }
    if (title && !lede) {
      const t = line.trim();
      if (t === "" || t.startsWith("#")) continue;
      lede = t.replace(/[`*_]/g, "");
      break;
    }
  }
  return { title, lede };
}

function toFrontmatter({ title, lede, source }) {
  const safe = (s) =>
    (s || "")
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"')
      .slice(0, 220);
  const lines = ["---"];
  lines.push(`title: "${safe(title)}"`);
  if (lede) lines.push(`description: "${safe(lede)}"`);
  lines.push(`editUrl: false`);
  lines.push(`# synced from ${source}`);
  lines.push("---", "");
  return lines.join("\n");
}

async function main() {
  if (!existsSync(SPEC_SRC)) {
    console.error(`sync-specs: source not found: ${SPEC_SRC}`);
    process.exit(1);
  }
  if (existsSync(SPEC_DST)) await rm(SPEC_DST, { recursive: true, force: true });
  await mkdir(SPEC_DST, { recursive: true });

  const files = await walk(SPEC_SRC);
  let count = 0;
  for (const file of files) {
    const rel = relative(SPEC_SRC, file);
    const dst = join(SPEC_DST, rel);
    await mkdir(dirname(dst), { recursive: true });

    const raw = await readFile(file, "utf8");
    // If the file already has frontmatter (starts with ---), preserve it.
    let out;
    if (raw.startsWith("---\n") || raw.startsWith("---\r\n")) {
      out = raw;
    } else {
      const { title, lede } = extractTitleAndLede(raw);
      const fmTitle = title || rel.replace(/\.md$/, "").split(/[\\/]/).pop();
      const fm = toFrontmatter({
        title: fmTitle,
        lede,
        source: `specs/${rel.replace(/\\/g, "/")}`,
      });
      // Strip the first H1 since Starlight renders title from frontmatter.
      const stripped = title
        ? raw.replace(/^#\s+.*\r?\n/, "")
        : raw;
      out = fm + stripped;
    }
    await writeFile(dst, out, "utf8");
    count++;
  }
  console.log(`sync-specs: copied ${count} file(s) into ${relative(process.cwd(), SPEC_DST)}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
