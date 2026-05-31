/**
 * `substrate write interpretation` — embed a substrate YAML snippet into
 * a markdown document.
 *
 * Reads pure YAML from stdin, validates it through the same parser the
 * dev UI uses, stamps a fresh `last-interpreted-at` timestamp, and
 * writes the result back into the named section of the target markdown
 * file — replacing an existing `substrate:` fenced block if one is
 * present, or appending a new one as the section's last block
 * otherwise. The file's mtime is set equal to the embedded
 * `last-interpreted-at` so the dev UI's freshness check matches.
 *
 * See `specs/tools/cli/write.md` for behaviour.
 */
import { readFile, writeFile, utimes } from "node:fs/promises";
import { resolve } from "node:path";

import { parseSubstrate } from "../substrate/parse.js";
import type { ParseDiagnostic } from "../substrate/ast.js";
import { slugify } from "../language/mdast-utils.js";

export interface WriteInterpretationOptions {
    /** Absolute or cwd-relative path to the markdown file. */
    readonly file: string;
    /** Section anchor (slug) to write into. Leading `#` is tolerated. */
    readonly anchor: string;
    /** Raw YAML body, expected to start with the `substrate:` mapping. */
    readonly yaml: string;
}

export interface WriteInterpretationResult {
    readonly file: string;
    readonly anchor: string;
    readonly diagnostics: readonly ParseDiagnostic[];
    readonly action: "replaced" | "appended";
    readonly timestamp: Date;
}

export class WriteInterpretationError extends Error {
    constructor(
        message: string,
        readonly diagnostics: readonly ParseDiagnostic[] = [],
    ) {
        super(message);
        this.name = "WriteInterpretationError";
    }
}

export async function writeInterpretation(
    cwd: string,
    opts: WriteInterpretationOptions,
): Promise<WriteInterpretationResult> {
    const absFile = resolve(cwd, opts.file);
    const anchor = opts.anchor.replace(/^#/, "").trim();
    if (!anchor) {
        throw new WriteInterpretationError("anchor must not be empty");
    }

    // Validate the YAML through the shared parser.
    const parseCtx = { file: opts.file, sectionId: anchor };
    const parseResult = parseSubstrate(opts.yaml, parseCtx);
    const errors = parseResult.diagnostics.filter((d) => d.severity === "error");
    if (errors.length > 0 || !parseResult.module) {
        throw new WriteInterpretationError(
            `substrate YAML failed to parse (${errors.length} error(s))`,
            parseResult.diagnostics,
        );
    }

    // Stamp a fresh `last-interpreted-at` into the YAML text, replacing
    // any existing one. Operates on text rather than re-serialising the
    // parsed AST so author formatting (comments, key order, indentation)
    // is preserved.
    const now = new Date();
    const stampedYaml = stampLastInterpretedAt(opts.yaml, now);

    // Load the markdown file.
    let markdown: string;
    try {
        markdown = await readFile(absFile, "utf8");
    } catch (err) {
        throw new WriteInterpretationError(
            `cannot read ${absFile}: ${err instanceof Error ? err.message : String(err)}`,
        );
    }

    // Locate the section and either replace an existing substrate block
    // or append a new one.
    const { content, action } = embedBlock(markdown, anchor, stampedYaml);

    await writeFile(absFile, content, "utf8");
    // Align the file mtime with the embedded last-interpreted-at so the
    // dev viewer's staleness check reads "up to date".
    await utimes(absFile, now, now);

    return {
        file: absFile,
        anchor,
        diagnostics: parseResult.diagnostics,
        action,
        timestamp: now,
    };
}

/**
 * Replace (or insert) the `last-interpreted-at` entry directly under the
 * `substrate:` mapping. Indentation matches the existing children.
 */
function stampLastInterpretedAt(yaml: string, when: Date): string {
    const iso = when.toISOString();
    const lines = yaml.split(/\r?\n/);
    const substrateIdx = lines.findIndex((l) => /^\s*substrate\s*:\s*$/.test(l));
    if (substrateIdx === -1) {
        // No `substrate:` key — treat input as bare module body and
        // leave it alone (validation already passed). The downstream
        // viewer will still see no timestamp; emit a leading line.
        return `last-interpreted-at: "${iso}"\n${yaml}`;
    }

    // Indentation of children = leading whitespace of the first
    // non-blank line after `substrate:`. Default to two spaces.
    let childIndent = "  ";
    for (let i = substrateIdx + 1; i < lines.length; i++) {
        const l = lines[i] ?? "";
        if (l.trim() === "") continue;
        const m = /^(\s*)\S/.exec(l);
        if (m && m[1]) childIndent = m[1];
        break;
    }

    // Drop every existing `last-interpreted-at` line at that indent.
    const filtered: string[] = [];
    const existingRe = new RegExp(`^${childIndent}last-interpreted-at\\s*:`);
    for (const l of lines) {
        if (existingRe.test(l)) continue;
        filtered.push(l);
    }

    // Re-find substrate idx after filtering.
    const newSubstrateIdx = filtered.findIndex((l) =>
        /^\s*substrate\s*:\s*$/.test(l),
    );
    filtered.splice(
        newSubstrateIdx + 1,
        0,
        `${childIndent}last-interpreted-at: "${iso}"`,
    );
    return filtered.join("\n");
}

interface EmbedResult {
    readonly content: string;
    readonly action: "replaced" | "appended";
}

/**
 * Embed a substrate YAML snippet into the section identified by
 * `anchor`. Replaces an existing fenced block whose first non-blank
 * content line is `substrate:`; otherwise appends a fresh fenced block
 * as the section's last piece of content.
 */
function embedBlock(
    markdown: string,
    anchor: string,
    yamlBody: string,
): EmbedResult {
    const lines = markdown.split(/\r?\n/);
    const headings = collectHeadings(lines);

    const heading = headings.find((h) => h.slug === anchor);
    if (!heading) {
        throw new WriteInterpretationError(
            `section '#${anchor}' not found in markdown file`,
        );
    }

    // Section body spans from the line after the heading to either the
    // next heading of same-or-shallower depth, or EOF.
    const sectionStart = heading.line + 1;
    let sectionEnd = lines.length; // exclusive
    for (const h of headings) {
        if (h.line > heading.line && h.depth <= heading.depth) {
            sectionEnd = h.line;
            break;
        }
    }

    // Look for an existing `substrate:` fenced block inside the section.
    const existing = findSubstrateFence(lines, sectionStart, sectionEnd);
    const newBlockLines = renderFence(yamlBody);

    if (existing) {
        const before = lines.slice(0, existing.start);
        const after = lines.slice(existing.end + 1);
        return {
            content: [...before, ...newBlockLines, ...after].join("\n"),
            action: "replaced",
        };
    }

    // Append at the end of the section. Trim trailing blank lines from
    // the section, leave exactly one blank line before the fence, and
    // restore the trailing blank line(s) after.
    let appendAt = sectionEnd;
    while (
        appendAt > sectionStart &&
        (lines[appendAt - 1] ?? "").trim() === ""
    ) {
        appendAt--;
    }
    const before = lines.slice(0, appendAt);
    const after = lines.slice(appendAt);
    const insert: string[] = ["", ...newBlockLines];
    if (after.length === 0 || (after[0] ?? "").trim() !== "") {
        insert.push("");
    }
    return {
        content: [...before, ...insert, ...after].join("\n"),
        action: "appended",
    };
}

function renderFence(yamlBody: string): readonly string[] {
    const trimmed = yamlBody.replace(/\s+$/g, "");
    return ["```yaml", ...trimmed.split(/\r?\n/), "```"];
}

interface HeadingRef {
    readonly line: number;   // 0-based
    readonly depth: number;
    readonly slug: string;
}

/**
 * Collect ATX-style headings, skipping any lines that fall inside a
 * fenced code block so a `#` inside code is not mistaken for a heading.
 */
function collectHeadings(lines: readonly string[]): readonly HeadingRef[] {
    const out: HeadingRef[] = [];
    let inFence = false;
    let fenceMarker = "";
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i] ?? "";
        const fenceMatch = /^(\s*)(```+|~~~+)/.exec(line);
        if (fenceMatch) {
            const marker = fenceMatch[2] ?? "";
            if (!inFence) {
                inFence = true;
                fenceMarker = marker;
            } else if (marker.startsWith(fenceMarker[0] ?? "")) {
                inFence = false;
                fenceMarker = "";
            }
            continue;
        }
        if (inFence) continue;
        const h = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
        if (!h) continue;
        const depth = (h[1] ?? "").length;
        const text = (h[2] ?? "").trim();
        out.push({ line: i, depth, slug: slugify(stripInline(text)) });
    }
    return out;
}

function stripInline(text: string): string {
    // Strip markdown link syntax `[text](url)` → `text`, and inline
    // code fences. Matches the heuristic used by `mdast-utils.slugify`
    // callers which feed plain heading text.
    return text
        .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
        .replace(/`([^`]*)`/g, "$1");
}

interface FenceRange {
    readonly start: number; // line index of opening ```yaml
    readonly end: number;   // line index of closing ```
}

function findSubstrateFence(
    lines: readonly string[],
    from: number,
    to: number,
): FenceRange | null {
    let i = from;
    while (i < to) {
        const line = lines[i] ?? "";
        const open = /^(\s*)```\s*ya?ml\s*$/i.exec(line);
        if (!open) {
            i++;
            continue;
        }
        // Find the matching close fence.
        let j = i + 1;
        let firstContent: string | null = null;
        while (j < to) {
            const l = lines[j] ?? "";
            if (/^\s*```\s*$/.test(l)) break;
            if (firstContent === null && l.trim() !== "") firstContent = l;
            j++;
        }
        if (j >= to) {
            // Unterminated fence — give up.
            return null;
        }
        if (firstContent !== null && /^\s*substrate\s*:/.test(firstContent)) {
            return { start: i, end: j };
        }
        i = j + 1;
    }
    return null;
}

export async function readStdin(): Promise<string> {
    if (process.stdin.isTTY) return "";
    const chunks: Buffer[] = [];
    for await (const chunk of process.stdin) {
        chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    return Buffer.concat(chunks).toString("utf8");
}

export function formatDiagnostic(d: ParseDiagnostic): string {
    const sev = d.severity.toUpperCase();
    const pos = d.position ? ` ${d.position.line}:${d.position.col}` : "";
    const path =
        d.path && d.path.length > 0 ? ` (${d.path.join(".")})` : "";
    return `  ${sev}${pos}${path}: ${d.message}`;
}
