/**
 * `substrate refactor rename` — rename a file or section, or move a section
 * between files, updating all cross-project references automatically.
 *
 * Operations (determined by argument shape):
 *   file.md → other.md          rename file on disk
 *   file.md#old → file.md#new   rename section (changes heading text + anchor)
 *   file.md#sec → other.md      move section to another file (prompts or uses [below])
 *   file.md#sec → other.md#par  move section, insert after #par in target
 */
import { readdir, readFile, stat, writeFile, rename as fsRename } from "node:fs/promises";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root, Heading } from "mdast";
import { nodeText, slugify } from "../language/mdast-utils.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface Ref {
    filePath: string;
    anchor: string | null;
}

interface SectionInfo {
    slug: string;
    headingIdx: number;
    /** Exclusive end index into root.children (the start of the next peer/ancestor heading). */
    subtreeEnd: number;
    depth: number;
    text: string;
}

type RefTransform = (
    absFile: string,
    anchor: string | null,
) => { file: string; anchor: string | null } | null;

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

export async function rename(cwd: string, fromArg: string, toArg: string): Promise<void> {
    const from = parseRef(fromArg, cwd);
    const to = parseRef(toArg, cwd);

    if (from.anchor === null) {
        if (to.anchor !== null) {
            throw new Error(
                `"from" is a file reference but "to" is a section reference. ` +
                    `When renaming a file both arguments must be file paths.`,
            );
        }
        await doRenameFile(cwd, from.filePath, to.filePath);
    } else if (from.filePath === to.filePath) {
        if (to.anchor === null) {
            throw new Error(
                `When renaming a section in the same file, specify the new name ` +
                    `as an anchor in "to": e.g. "${toArg}#new-section-name".`,
            );
        }
        await doRenameSection(cwd, from.filePath, from.anchor, to.anchor);
    } else {
        // Move section to another file.
        // Parent anchor comes from to#anchor if supplied, otherwise prompt.
        await doMoveSection(cwd, from.filePath, from.anchor, to.filePath, to.anchor ?? undefined);
    }
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseRef(raw: string, cwd: string): Ref {
    const hashIdx = raw.indexOf("#");
    const rawPath = hashIdx >= 0 ? raw.slice(0, hashIdx) : raw;
    const anchor = hashIdx >= 0 ? (raw.slice(hashIdx + 1) || null) : null;
    const filePath = isAbsolute(rawPath) ? resolve(rawPath) : resolve(cwd, rawPath);
    return { filePath, anchor };
}

// ---------------------------------------------------------------------------
// Markdown helpers
// ---------------------------------------------------------------------------

function parseMarkdown(source: string): Root {
    return unified().use(remarkParse).use(remarkGfm).parse(source) as Root;
}

function buildSections(root: Root): Map<string, SectionInfo> {
    const sections = new Map<string, SectionInfo>();
    const slugCounts = new Map<string, number>();
    const all: SectionInfo[] = [];

    for (let i = 0; i < root.children.length; i++) {
        const node = root.children[i]!;
        if (node.type !== "heading") continue;
        const heading = node as Heading;
        const text = nodeText(heading);
        const baseSlug = slugify(text);
        const count = slugCounts.get(baseSlug) ?? 0;
        const slug = count === 0 ? baseSlug : `${baseSlug}-${count + 1}`;
        slugCounts.set(baseSlug, count + 1);

        const info: SectionInfo = {
            slug,
            headingIdx: i,
            subtreeEnd: root.children.length,
            depth: heading.depth,
            text,
        };
        all.push(info);
        sections.set(slug, info);
    }

    for (let s = 0; s < all.length; s++) {
        const sec = all[s]!;
        for (let t = s + 1; t < all.length; t++) {
            if (all[t]!.depth <= sec.depth) {
                (sec as { subtreeEnd: number }).subtreeEnd = all[t]!.headingIdx;
                break;
            }
        }
    }

    return sections;
}

// ---------------------------------------------------------------------------
// Operation: rename file
// ---------------------------------------------------------------------------

async function doRenameFile(cwd: string, fromPath: string, toPath: string): Promise<void> {
    if (fromPath === toPath) {
        throw new Error(`Source and destination are the same file: ${fromPath}`);
    }
    const root = await findProjectRoot(cwd);

    await fsRename(fromPath, toPath);
    console.log(`  Renamed ${relative(root, fromPath)} → ${relative(root, toPath)}`);

    const allFiles = await walkMarkdownFiles(root);
    const updated = await updateAllRefs(allFiles, (absFile, anchor) => {
        if (absFile !== fromPath) return null;
        return { file: toPath, anchor };
    });
    for (const f of updated) console.log(`  Updated ${relative(root, f)}`);
    console.log(`✓ Done (${updated.length} file${updated.length === 1 ? "" : "s"} updated)`);
}

// ---------------------------------------------------------------------------
// Operation: rename section (same file)
// ---------------------------------------------------------------------------

async function doRenameSection(
    cwd: string,
    filePath: string,
    oldAnchor: string,
    newAnchorArg: string,
): Promise<void> {
    const projectRoot = await findProjectRoot(cwd);
    const source = await readFile(filePath, "utf8");
    const root = parseMarkdown(source);
    const sections = buildSections(root);

    const sec = sections.get(oldAnchor);
    if (!sec) throw new Error(`Section "#${oldAnchor}" not found in ${filePath}`);

    const newHeadingText = anchorToText(newAnchorArg);
    const newAnchor = slugify(newHeadingText);

    if (newAnchor === oldAnchor) {
        throw new Error(`"${newAnchorArg}" produces the same anchor "#${newAnchor}" — nothing to do.`);
    }
    if (sections.has(newAnchor)) {
        throw new Error(
            `A section with anchor "#${newAnchor}" already exists in ${filePath}.`,
        );
    }

    // Replace heading text in raw source using character offsets.
    const headingNode = root.children[sec.headingIdx] as Heading;
    const startOff = headingNode.position!.start.offset!;
    const endOff = headingNode.position!.end.offset!;
    const newHeadingRaw = "#".repeat(sec.depth) + " " + newHeadingText;
    const newSource = source.slice(0, startOff) + newHeadingRaw + source.slice(endOff);
    await writeFile(filePath, newSource, "utf8");
    console.log(`  Renamed #${oldAnchor} → #${newAnchor} in ${relative(projectRoot, filePath)}`);

    const allFiles = await walkMarkdownFiles(projectRoot);
    const updated = await updateAllRefs(allFiles, (absFile, anchor) => {
        if (absFile !== filePath || anchor !== oldAnchor) return null;
        return { file: filePath, anchor: newAnchor };
    });
    for (const f of updated) console.log(`  Updated ${relative(projectRoot, f)}`);
    console.log(`✓ Done (${updated.length} file${updated.length === 1 ? "" : "s"} updated)`);
}

// ---------------------------------------------------------------------------
// Operation: move section to another file
// ---------------------------------------------------------------------------

async function doMoveSection(
    cwd: string,
    fromFile: string,
    sectionAnchor: string,
    toFile: string,
    parentAnchorArg: string | undefined,
): Promise<void> {
    const projectRoot = await findProjectRoot(cwd);

    const sourceText = await readFile(fromFile, "utf8");
    const sourceRoot = parseMarkdown(sourceText);
    const sourceSections = buildSections(sourceRoot);

    const sec = sourceSections.get(sectionAnchor);
    if (!sec) throw new Error(`Section "#${sectionAnchor}" not found in ${fromFile}`);

    const targetText = await readFile(toFile, "utf8");
    const targetRoot = parseMarkdown(targetText);
    const targetSections = buildSections(targetRoot);

    // Collect all anchors in the moved subtree (the section + all its descendants).
    const movedAnchors = new Set<string>();
    for (const [slug, info] of sourceSections) {
        if (info.headingIdx >= sec.headingIdx && info.headingIdx < sec.subtreeEnd) {
            movedAnchors.add(slug);
        }
    }

    // Check for anchor collisions in the target file.
    for (const slug of movedAnchors) {
        if (targetSections.has(slug)) {
            throw new Error(
                `Section "#${slug}" already exists in ${relative(projectRoot, toFile)}. ` +
                    `Rename the conflicting section first before moving.`,
            );
        }
    }

    // Resolve parent anchor: explicit (from to#anchor) → interactive prompt.
    let parentAnchor: string | null;
    if (parentAnchorArg !== undefined) {
        parentAnchor = parentAnchorArg;
        if (!targetSections.has(parentAnchor)) {
            throw new Error(
                `Section "#${parentAnchor}" not found in ${relative(projectRoot, toFile)}.`,
            );
        }
    } else {
        parentAnchor = await promptSelectParent(
            relative(projectRoot, toFile),
            [...targetSections.values()],
        );
        // promptSelectParent throws on cancellation.
    }

    // Extract section raw text from source using character offsets.
    const secStart = sourceRoot.children[sec.headingIdx]!.position!.start.offset!;
    const secEnd =
        sec.subtreeEnd < sourceRoot.children.length
            ? sourceRoot.children[sec.subtreeEnd]!.position!.start.offset!
            : sourceText.length;
    const sectionText = sourceText.slice(secStart, secEnd).trimEnd();

    // Build new source (section removed).
    const beforeSec = sourceText.slice(0, secStart).trimEnd();
    const afterSec = sourceText.slice(secEnd).trimStart();
    const newSourceText = normalizeBlankLines(
        beforeSec === "" ? afterSec : beforeSec + "\n\n" + afterSec,
    );

    // Determine insertion offset in target.
    let insertOffset: number;
    if (parentAnchor === null) {
        insertOffset = targetText.length;
    } else {
        const parentSec = targetSections.get(parentAnchor)!;
        insertOffset =
            parentSec.subtreeEnd < targetRoot.children.length
                ? targetRoot.children[parentSec.subtreeEnd]!.position!.start.offset!
                : targetText.length;
    }

    // Build new target (section inserted).
    const beforeInsert = targetText.slice(0, insertOffset).trimEnd();
    const afterInsert = targetText.slice(insertOffset).trimStart();
    const newTargetText = normalizeBlankLines(
        (beforeInsert ? beforeInsert + "\n\n" : "") +
            sectionText +
            (afterInsert ? "\n\n" + afterInsert : ""),
    );

    await writeFile(fromFile, newSourceText, "utf8");
    await writeFile(toFile, newTargetText, "utf8");
    console.log(
        `  Moved #${sectionAnchor} from ${relative(projectRoot, fromFile)} ` +
            `to ${relative(projectRoot, toFile)}`,
    );

    const allFiles = await walkMarkdownFiles(projectRoot);
    const updated = await updateAllRefs(allFiles, (absFile, anchor) => {
        if (absFile === fromFile && anchor !== null && movedAnchors.has(anchor)) {
            return { file: toFile, anchor };
        }
        return null;
    });
    for (const f of updated) console.log(`  Updated ${relative(projectRoot, f)}`);
    console.log(`✓ Done (${updated.length} file${updated.length === 1 ? "" : "s"} updated)`);
}

// ---------------------------------------------------------------------------
// Interactive section selector
// ---------------------------------------------------------------------------

async function promptSelectParent(
    toFileLabel: string,
    sections: readonly SectionInfo[],
): Promise<string | null> {
    if (!process.stdin.isTTY) {
        throw new Error(
            "stdin is not a TTY — cannot show interactive prompt.\n" +
                "Supply the parent section anchor as the third argument to skip the prompt,\n" +
                'or pass "root" to append at the end of the file.',
        );
    }

    const options: Array<{ label: string; anchor: string | null }> = [
        { label: "(root — append at end of file)", anchor: null },
        ...sections.map((s) => ({
            label: "  ".repeat(s.depth - 1) + "#".repeat(s.depth) + " " + s.text,
            anchor: s.slug,
        })),
    ];

    process.stderr.write(
        `\nSelect section to append below in ${toFileLabel} (↑↓ to move, Enter to confirm):\n\n`,
    );

    return new Promise<string | null>((res, rej) => {
        let selected = 0;
        let drawn = false;

        const render = () => {
            if (drawn) process.stderr.write(`\x1B[${options.length}A`);
            drawn = true;
            for (let i = 0; i < options.length; i++) {
                const marker = i === selected ? "▶ " : "  ";
                process.stderr.write(`\x1B[2K${marker}${options[i]!.label}\n`);
            }
        };

        const cleanup = () => {
            try { process.stdin.setRawMode(false); } catch { /* ignore */ }
            process.stdin.pause();
            process.stdin.removeListener("data", onData);
        };

        const onData = (chunk: Buffer) => {
            const key = chunk.toString();
            if (key === "\x1B[A") {
                if (selected > 0) selected--;
            } else if (key === "\x1B[B") {
                if (selected < options.length - 1) selected++;
            } else if (key === "\r" || key === "\n") {
                cleanup();
                process.stderr.write("\n");
                res(options[selected]!.anchor);
                return;
            } else if (key === "\x03") {
                cleanup();
                process.stderr.write("\n");
                rej(new Error("Cancelled."));
                return;
            } else if (key === "\x1B") {
                cleanup();
                process.stderr.write("\n");
                rej(new Error("Cancelled."));
                return;
            }
            render();
        };

        try {
            process.stdin.setRawMode(true);
        } catch (e) {
            rej(new Error("Cannot set raw mode on stdin: " + String(e)));
            return;
        }
        process.stdin.resume();
        process.stdin.on("data", onData);
        render();
    });
}

// ---------------------------------------------------------------------------
// Project root discovery and markdown file walking
// ---------------------------------------------------------------------------

const WALK_SKIP = new Set([".git", "node_modules", "dist"]);

/**
 * Walk up from `dir` to find the nearest `.git` directory, which is treated
 * as the project root. Falls back to `dir` itself if none is found.
 * This avoids depending on `substrate.json` which may live in a parent and
 * would cause `listMarkdownFiles` to skip the current subtree as vendored.
 */
async function findProjectRoot(dir: string): Promise<string> {
    let current = resolve(dir);
    while (true) {
        try {
            const s = await stat(join(current, ".git"));
            if (s.isDirectory()) return current;
        } catch { /* not found at this level */ }
        const parent = dirname(current);
        if (parent === current) return resolve(dir);
        current = parent;
    }
}

/** Recursively collect all `.md` files under `root`, skipping common non-source dirs. */
async function walkMarkdownFiles(root: string): Promise<readonly string[]> {
    const out: string[] = [];
    async function walk(dir: string): Promise<void> {
        let entries;
        try { entries = await readdir(dir, { withFileTypes: true }); } catch { return; }
        for (const entry of entries) {
            const full = join(dir, entry.name);
            if (entry.isDirectory()) {
                if (!WALK_SKIP.has(entry.name)) await walk(full);
            } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".md")) {
                out.push(full);
            }
        }
    }
    await walk(resolve(root));
    return out.sort((a, b) => a.localeCompare(b));
}

// ---------------------------------------------------------------------------
// Reference update utilities
// ---------------------------------------------------------------------------

async function updateAllRefs(files: readonly string[], transform: RefTransform): Promise<string[]> {
    const updated: string[] = [];
    for (const f of files) {
        let source: string;
        try {
            source = await readFile(f, "utf8");
        } catch {
            continue;
        }
        const newSource = rewriteLinksInSource(source, f, transform);
        if (newSource !== source) {
            await writeFile(f, newSource, "utf8");
            updated.push(f);
        }
    }
    return updated;
}

function rewriteLinksInSource(source: string, fromFile: string, transform: RefTransform): string {
    let result = source;

    // Inline links: [text](url) or [text](url "title")
    result = result.replace(
        /\[([^\]]*)\]\((\S+?)((?:\s+"[^"]*")?)\)/g,
        (match, text: string, rawUrl: string, title: string) => {
            const newUrl = maybeTransformUrl(rawUrl, fromFile, transform);
            return newUrl !== null ? `[${text}](${newUrl}${title})` : match;
        },
    );

    // Reference definitions: [id]: url optional-title
    result = result.replace(
        /^(\[[^\]]*\]:\s+)(\S+)((?:\s+"[^"]*")?)/gm,
        (match, prefix: string, rawUrl: string, title: string) => {
            const newUrl = maybeTransformUrl(rawUrl, fromFile, transform);
            return newUrl !== null ? `${prefix}${newUrl}${title}` : match;
        },
    );

    return result;
}

function maybeTransformUrl(rawUrl: string, fromFile: string, transform: RefTransform): string | null {
    if (/^https?:\/\//.test(rawUrl) || rawUrl.startsWith("mailto:")) return null;

    const hashIdx = rawUrl.indexOf("#");
    const filePart = hashIdx >= 0 ? rawUrl.slice(0, hashIdx) : rawUrl;
    const anchor = hashIdx >= 0 ? (rawUrl.slice(hashIdx + 1) || null) : null;

    let absFile: string;
    if (filePart === "") {
        absFile = fromFile;
    } else if (filePart.startsWith("/")) {
        absFile = resolve(filePart);
    } else {
        absFile = resolve(dirname(fromFile), filePart);
    }

    const result = transform(absFile, anchor);
    if (result === null) return null;

    let newFilePart: string;
    if (result.file === fromFile) {
        newFilePart = "";
    } else {
        newFilePart = relative(dirname(fromFile), result.file).replace(/\\/g, "/");
    }

    const anchorPart = result.anchor !== null ? `#${result.anchor}` : "";
    const newUrl = newFilePart + anchorPart;
    return newUrl || null;
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

/** Derive a heading text string from an anchor slug (hyphens → spaces, first letter capitalised). */
function anchorToText(anchor: string): string {
    const words = anchor.split("-");
    if (words.length === 0) return anchor;
    words[0] = words[0]!.charAt(0).toUpperCase() + words[0]!.slice(1);
    return words.join(" ");
}

/** Collapse 3+ consecutive newlines to 2 and ensure a single trailing newline. */
function normalizeBlankLines(s: string): string {
    return s.replace(/\n{3,}/g, "\n\n").replace(/^\n+/, "").trimEnd() + "\n";
}
