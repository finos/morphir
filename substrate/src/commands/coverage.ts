/**
 * `substrate coverage` — analyse one or more substrate documents and report
 * how they relate to the language specification.
 *
 * See specs/tools/cli/coverage.md for the full specification.
 */
import { readFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root, Link, LinkReference, Definition } from "mdast";
import { verify } from "../pipeline.js";
import { listMarkdownFiles, locatePackage } from "../package/corpus.js";
import type { Diagnostic } from "../types.js";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface StructuralCoverage {
    /** Operations whose test cases ran and passed. */
    readonly evaluable: readonly string[];
    /** Operations whose test cases ran but produced failures. */
    readonly failing: readonly string[];
    /** Operations found in spec but with no registered evaluator. */
    readonly parsedOnly: readonly string[];
    /** Concepts skipped because no evaluator exists for the concept kind. */
    readonly skipped: readonly string[];
}

export interface RecognitionMetrics {
    readonly parsedPct: number;
    readonly typecheckedPct: number;
    readonly evaluablePct: number;
}

export interface FileCoverage {
    readonly file: string;
    readonly structural: StructuralCoverage;
    readonly narrative: readonly string[];
    readonly divergence: {
        readonly claimedButUnused: readonly string[];
        readonly usedButUnclaimed: readonly string[];
    };
    readonly recognition: RecognitionMetrics;
}

export interface CoverageAggregate {
    readonly totalNormativeAnchors: number;
    readonly reachedAnchors: readonly string[];
    readonly pct: number;
}

export interface CoverageResult {
    readonly files: readonly FileCoverage[];
    readonly aggregate: CoverageAggregate;
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

export interface CoverageOptions {
    readonly format?: "text" | "json" | "markdown";
    readonly against?: string;
}

export async function coverage(
    cwd: string,
    paths: readonly string[],
    opts: CoverageOptions = {},
): Promise<CoverageResult> {
    // Resolve input files.
    const files = await resolveInputFiles(cwd, paths);

    // Locate the spec corpus root for normative anchor counting.
    const specRoot = await findSpecRoot(cwd);

    const normativeAnchors = specRoot !== null
        ? await countNormativeAnchors(specRoot)
        : 0;

    // Analyse each file.
    const fileCoverages: FileCoverage[] = [];
    for (const file of files) {
        const fc = await analyseFile(file);
        fileCoverages.push(fc);
    }

    // Aggregate.
    const allReached = new Set<string>();
    for (const fc of fileCoverages) {
        for (const a of fc.structural.evaluable) allReached.add(a);
        for (const a of fc.structural.failing) allReached.add(a);
    }
    const reachedAnchors = [...allReached].sort();
    const pct = normativeAnchors > 0
        ? Math.round((reachedAnchors.length / normativeAnchors) * 1000) / 10
        : 0;

    return {
        files: fileCoverages,
        aggregate: { totalNormativeAnchors: normativeAnchors, reachedAnchors, pct },
    };
}

// ---------------------------------------------------------------------------
// File resolution
// ---------------------------------------------------------------------------

async function resolveInputFiles(cwd: string, paths: readonly string[]): Promise<string[]> {
    if (paths.length === 0) {
        try {
            const pkg = await locatePackage(cwd);
            return [...await listMarkdownFiles(pkg.root)];
        } catch {
            return [];
        }
    }

    const files: string[] = [];
    for (const p of paths) {
        const abs = resolve(cwd, p);
        const mds = await listMarkdownFiles(abs).catch(() =>
            abs.endsWith(".md") ? [abs] as string[] : [] as string[],
        );
        files.push(...mds);
    }
    return files;
}

// ---------------------------------------------------------------------------
// Per-file analysis
// ---------------------------------------------------------------------------

async function analyseFile(file: string): Promise<FileCoverage> {
    const result = await verify(file);

    // Extract structural coverage from test-stage diagnostics.
    const testDiags = result.stages
        .find((s) => s.stage === "test")
        ?.diagnostics ?? [];

    const evaluable: string[] = [];
    const failing: string[] = [];
    const parsedOnly: string[] = [];
    const skipped: string[] = [];

    for (const d of testDiags) {
        const anchor = extractAnchor(d, file);
        if (d.ruleId === "test-pass" && anchor) evaluable.push(anchor);
        else if (d.ruleId === "test-failure" && anchor) {
            if (!failing.includes(anchor)) failing.push(anchor);
        } else if (d.ruleId === "no-evaluator" && anchor) parsedOnly.push(anchor);
        else if (d.ruleId === "no-evaluator-for-concept" && anchor) skipped.push(anchor);
    }

    // Extract narrative coverage from prose links.
    const narrative = await extractNarrativeAnchors(file);

    // Compute divergence.
    const evaluableSet = new Set([...evaluable, ...failing]);
    const narrativeSet = new Set(narrative);
    const claimedButUnused = [...narrativeSet].filter((a) => !evaluableSet.has(a));
    const usedButUnclaimed = [...evaluableSet].filter((a) => !narrativeSet.has(a));

    // Recognition metrics (heuristic based on operation counts).
    const totalOps = evaluable.length + failing.length + parsedOnly.length + skipped.length;
    const evaluablePct = totalOps > 0
        ? Math.round(((evaluable.length + failing.length) / totalOps) * 100)
        : 0;
    // Typechecked includes parsed-only operations that the typechecker visited.
    const typecheckedPct = totalOps > 0
        ? Math.round(((evaluable.length + failing.length + parsedOnly.length) / totalOps) * 100)
        : 0;
    const parsedPct = typecheckedPct; // same heuristic at this stage

    return {
        file,
        structural: { evaluable, failing, parsedOnly, skipped },
        narrative,
        divergence: { claimedButUnused, usedButUnclaimed },
        recognition: { parsedPct, typecheckedPct, evaluablePct },
    };
}

function extractAnchor(d: Diagnostic, filePath: string): string | null {
    const opMatch = d.message.match(/^Operation "([^"]+)"/);
    if (!opMatch) return null;
    const name = opMatch[1]!;
    const slug = slugify(name) + "-operation";
    const relFile = deriveRelativeSpecPath(filePath);
    return relFile ? `${relFile}#${slug}` : null;
}

function deriveRelativeSpecPath(filePath: string): string | null {
    const normalised = filePath.replace(/\\/g, "/");
    const match = /(?:^|\/)(\w+\/[^/]+\.md)$/.exec(normalised);
    return match?.[1] ?? null;
}

function slugify(text: string): string {
    return text
        .toLowerCase()
        .replace(/[^\w\s-]/g, "")
        .replace(/\s+/g, "-")
        .replace(/-+/g, "-")
        .replace(/^-|-$/g, "");
}

// ---------------------------------------------------------------------------
// Narrative coverage — links to spec sections
// ---------------------------------------------------------------------------

async function extractNarrativeAnchors(file: string): Promise<string[]> {
    let source: string;
    try {
        source = await readFile(file, "utf8");
    } catch {
        return [];
    }

    const root = unified().use(remarkParse).use(remarkGfm).parse(source) as Root;
    const defs = collectDefinitions(root);
    const anchors = new Set<string>();

    walkLinks(root, defs, (url) => {
        const anchor = urlToSpecAnchor(url);
        if (anchor) anchors.add(anchor);
    });

    return [...anchors].sort();
}

function collectDefinitions(root: Root): Map<string, string> {
    const out = new Map<string, string>();
    for (const n of root.children) {
        if (n.type === "definition") {
            const d = n as Definition;
            out.set(d.identifier.toLowerCase(), d.url);
        }
    }
    return out;
}

function walkLinks(
    node: unknown,
    defs: ReadonlyMap<string, string>,
    onUrl: (url: string) => void,
): void {
    if (typeof node !== "object" || node === null) return;
    const obj = node as Record<string, unknown>;
    if (obj["type"] === "link") {
        onUrl((obj as unknown as Link).url);
    } else if (obj["type"] === "linkReference") {
        const ref = obj as unknown as LinkReference;
        const url = defs.get(ref.identifier.toLowerCase());
        if (url) onUrl(url);
    }
    const children = obj["children"];
    if (Array.isArray(children)) {
        for (const c of children) walkLinks(c, defs, onUrl);
    }
}

function urlToSpecAnchor(url: string): string | null {
    if (/^https?:\/\//.test(url) || url.startsWith("mailto:")) return null;
    const hashIdx = url.indexOf("#");
    const filePart = hashIdx >= 0 ? url.slice(0, hashIdx) : url;
    const anchor = hashIdx >= 0 ? url.slice(hashIdx + 1) : null;
    if (!filePart.endsWith(".md")) return null;
    if (!filePart.includes("expressions/") && !filePart.includes("concepts/")) return null;
    const segments = filePart.split("/").filter(Boolean);
    if (segments.length < 2) return null;
    const specFile = `${segments[segments.length - 2]}/${segments[segments.length - 1]}`;
    return anchor ? `${specFile}#${anchor}` : specFile;
}

// ---------------------------------------------------------------------------
// Normative anchor counting
// ---------------------------------------------------------------------------

async function findSpecRoot(cwd: string): Promise<string | null> {
    // Walk up from cwd looking for a specs/language/expressions directory.
    let dir = cwd;
    for (let i = 0; i < 10; i++) {
        const candidate = resolve(dir, "specs/language/expressions");
        try {
            const files = await listMarkdownFiles(candidate);
            if (files.length > 0) return candidate;
        } catch { /* keep looking */ }
        const parent = dirname(dir);
        if (parent === dir) break;
        dir = parent;
    }
    return null;
}

async function countNormativeAnchors(expressionsDir: string): Promise<number> {
    const files = await listMarkdownFiles(expressionsDir).catch(() => [] as string[]);
    let count = 0;
    for (const file of files) {
        const source = await readFile(file, "utf8").catch(() => "");
        // Count headings that contain "[Operation](" — these are operation definitions.
        const matches = source.match(/\[Operation\]\(/g);
        if (matches) count += matches.length;
    }
    return count;
}

// ---------------------------------------------------------------------------
// Text output
// ---------------------------------------------------------------------------

export function reportCoverage(result: CoverageResult, format: string = "text"): string {
    if (format === "json") return formatJson(result);
    if (format === "markdown") return formatMarkdown(result);
    return formatText(result);
}

function formatText(result: CoverageResult): string {
    const lines: string[] = [];

    for (const fc of result.files) {
        lines.push(fc.file);
        lines.push(
            `  recognition          parsed ${fc.recognition.parsedPct}%  ` +
            `typechecked ${fc.recognition.typecheckedPct}%  ` +
            `evaluable ${fc.recognition.evaluablePct}%`,
        );
        const structural = fc.structural.evaluable.length + fc.structural.failing.length;
        lines.push(`  structural           ${structural} anchor(s) reached`);
        lines.push(`  narrative            ${fc.narrative.length} anchor(s) linked`);

        if (fc.divergence.claimedButUnused.length > 0) {
            const list = fc.divergence.claimedButUnused.slice(0, 3).join(", ");
            const extra = fc.divergence.claimedButUnused.length > 3
                ? ` +${fc.divergence.claimedButUnused.length - 3} more` : "";
            lines.push(`  claimed but unused   ${fc.divergence.claimedButUnused.length}  (${list}${extra})`);
        }
        if (fc.divergence.usedButUnclaimed.length > 0) {
            lines.push(
                `  used but unclaimed   ${fc.divergence.usedButUnclaimed.length}  ` +
                `(run with --format markdown for details)`,
            );
        }
        lines.push("");
    }

    const { aggregate } = result;
    const pctStr = aggregate.totalNormativeAnchors > 0
        ? `${aggregate.pct}%`
        : "n/a";
    lines.push(
        `language coverage (${result.files.length} file${result.files.length === 1 ? "" : "s"})`,
    );
    lines.push(
        `  structural / normative anchors    ${aggregate.reachedAnchors.length} / ` +
        `${aggregate.totalNormativeAnchors}   (${pctStr})`,
    );

    return lines.join("\n");
}

function formatJson(result: CoverageResult): string {
    const files = result.files.map((fc) => ({
        file: fc.file,
        structural: {
            evaluable: fc.structural.evaluable,
            failing: fc.structural.failing,
            parsedOnly: fc.structural.parsedOnly,
            skipped: fc.structural.skipped,
        },
        narrative: fc.narrative,
        divergence: fc.divergence,
        recognition: fc.recognition,
    }));
    return JSON.stringify(
        { files, aggregate: result.aggregate },
        null,
        2,
    );
}

function formatMarkdown(result: CoverageResult): string {
    const lines: string[] = ["# Coverage Report", ""];

    for (const fc of result.files) {
        lines.push(`## ${fc.file}`, "");
        lines.push(
            `| Metric | Value |`,
            `| ------ | ----- |`,
            `| Parsed | ${fc.recognition.parsedPct}% |`,
            `| Typechecked | ${fc.recognition.typecheckedPct}% |`,
            `| Evaluable | ${fc.recognition.evaluablePct}% |`,
            `| Structural anchors | ${fc.structural.evaluable.length + fc.structural.failing.length} |`,
            `| Narrative anchors | ${fc.narrative.length} |`,
            "",
        );
        if (fc.divergence.claimedButUnused.length > 0) {
            lines.push("### Claimed but unused", "");
            for (const a of fc.divergence.claimedButUnused) lines.push(`- \`${a}\``);
            lines.push("");
        }
        if (fc.divergence.usedButUnclaimed.length > 0) {
            lines.push("### Used but unclaimed", "");
            for (const a of fc.divergence.usedButUnclaimed) lines.push(`- \`${a}\``);
            lines.push("");
        }
    }

    const { aggregate } = result;
    lines.push("## Aggregate", "");
    lines.push(
        `**Structural / normative anchors:** ${aggregate.reachedAnchors.length} / ` +
        `${aggregate.totalNormativeAnchors} (${aggregate.pct}%)`,
        "",
    );

    return lines.join("\n");
}
