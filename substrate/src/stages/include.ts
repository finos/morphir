/**
 * Stage 2: Include — resolve document-inclusion headings recursively.
 *
 * An inclusion heading is a heading whose entire inline content is a
 * single link. The linked file is parsed and its content embedded,
 * with heading levels adjusted to nest under the inclusion heading.
 *
 * The sibling convention restricts inclusions to direct children of
 * the file's paired directory.
 */
import { readdir, stat } from "node:fs/promises";
import { resolve, dirname, basename, extname, sep, posix } from "node:path";
import type { Root, Content, Heading } from "mdast";
import type { Diagnostic } from "../types.js";
import { inclusionTarget, nodeText } from "../language/mdast-utils.js";
import { parseFile } from "./parse.js";

/**
 * Resolve all inclusion headings in the given root.
 *
 * Returns the expanded root, diagnostics, and the set of all files
 * that were included (for downstream stages).
 */
export async function resolveInclusions(
    root: Root,
    filePath: string,
    visited?: ReadonlySet<string>,
): Promise<{
    readonly root: Root;
    readonly diagnostics: readonly Diagnostic[];
    readonly includedFiles: ReadonlySet<string>;
}> {
    const absPath = resolve(filePath);
    const currentVisited = new Set(visited ?? []);
    if (currentVisited.has(absPath)) {
        return {
            root,
            diagnostics: [
                {
                    stage: "include",
                    severity: "error",
                    file: filePath,
                    message: `Circular inclusion detected: ${absPath}`,
                },
            ],
            includedFiles: new Set(),
        };
    }
    currentVisited.add(absPath);

    const diagnostics: Diagnostic[] = [];
    const includedFiles = new Set<string>();
    const newChildren: Content[] = [];

    for (const node of root.children) {
        if (node.type !== "heading") {
            newChildren.push(node);
            continue;
        }

        const heading = node as Heading;
        const target = inclusionTarget(heading);
        if (target === null || isExternalUrl(target)) {
            newChildren.push(node);
            continue;
        }

        // Validate sibling convention
        if (!isSiblingChild(filePath, target)) {
            // Not an inclusion; treat as a normal link heading
            newChildren.push(node);
            continue;
        }

        const targetPath = resolve(dirname(absPath), target);

        // Directory inclusion
        if (target.endsWith("/")) {
            const dirResult = await includeDirectory(
                targetPath,
                heading.depth,
                filePath,
                currentVisited,
            );
            diagnostics.push(...dirResult.diagnostics);
            for (const f of dirResult.includedFiles) includedFiles.add(f);
            // Keep the heading, then append included content
            newChildren.push(heading, ...dirResult.content);
            continue;
        }

        // File inclusion
        const fileResult = await includeFile(
            targetPath,
            heading.depth,
            filePath,
            currentVisited,
        );
        diagnostics.push(...fileResult.diagnostics);
        for (const f of fileResult.includedFiles) includedFiles.add(f);
        newChildren.push(heading, ...fileResult.content);
    }

    return {
        root: { ...root, children: newChildren },
        diagnostics,
        includedFiles,
    };
}

// ---------------------------------------------------------------------------
// File inclusion
// ---------------------------------------------------------------------------

async function includeFile(
    targetPath: string,
    parentDepth: number,
    sourceFile: string,
    visited: ReadonlySet<string>,
): Promise<{
    readonly content: readonly Content[];
    readonly diagnostics: readonly Diagnostic[];
    readonly includedFiles: ReadonlySet<string>;
}> {
    const diagnostics: Diagnostic[] = [];
    const included = new Set<string>();

    let targetStat;
    try {
        targetStat = await stat(targetPath);
    } catch {
        return {
            content: [],
            diagnostics: [
                {
                    stage: "include",
                    severity: "error",
                    file: sourceFile,
                    message: `Inclusion target not found: ${targetPath}`,
                },
            ],
            includedFiles: included,
        };
    }

    if (!targetStat.isFile()) {
        return {
            content: [],
            diagnostics: [
                {
                    stage: "include",
                    severity: "error",
                    file: sourceFile,
                    message: `Inclusion target is not a file: ${targetPath}`,
                },
            ],
            includedFiles: included,
        };
    }

    included.add(targetPath);
    const { doc, diagnostics: parseDiags } = await parseFile(targetPath);
    diagnostics.push(...parseDiags);

    // Recursively resolve inclusions in the target
    const { root: expanded, diagnostics: incDiags, includedFiles } = await resolveInclusions(
        doc.root,
        targetPath,
        visited,
    );
    diagnostics.push(...incDiags);
    for (const f of includedFiles) included.add(f);

    // Adjust heading levels: content appears nested under parentDepth
    const adjusted = adjustHeadingLevels(expanded.children, parentDepth);
    return { content: adjusted, diagnostics, includedFiles: included };
}

// ---------------------------------------------------------------------------
// Directory inclusion
// ---------------------------------------------------------------------------

async function includeDirectory(
    dirPath: string,
    parentDepth: number,
    sourceFile: string,
    visited: ReadonlySet<string>,
): Promise<{
    readonly content: readonly Content[];
    readonly diagnostics: readonly Diagnostic[];
    readonly includedFiles: ReadonlySet<string>;
}> {
    const diagnostics: Diagnostic[] = [];
    const included = new Set<string>();
    const content: Content[] = [];

    let entries: string[];
    try {
        const raw = await readdir(dirPath);
        entries = raw.filter((e) => extname(e) === ".md").sort();
    } catch {
        return {
            content: [],
            diagnostics: [
                {
                    stage: "include",
                    severity: "error",
                    file: sourceFile,
                    message: `Inclusion directory not found: ${dirPath}`,
                },
            ],
            includedFiles: included,
        };
    }

    for (const entry of entries) {
        const entryPath = resolve(dirPath, entry);
        const result = await includeFile(
            entryPath,
            parentDepth,
            sourceFile,
            visited,
        );
        diagnostics.push(...result.diagnostics);
        for (const f of result.includedFiles) included.add(f);
        content.push(...result.content);
    }

    return { content, diagnostics, includedFiles: included };
}

// ---------------------------------------------------------------------------
// Heading-level adjustment
// ---------------------------------------------------------------------------

/**
 * Adjust all heading depths in the content so that the first heading
 * becomes `parentDepth + 1` and deeper headings shift proportionally.
 */
function adjustHeadingLevels(
    content: readonly Content[],
    parentDepth: number,
): Content[] {
    // Find the minimum heading depth in the content
    let minDepth = 6;
    for (const node of content) {
        if (node.type === "heading") {
            const d = (node as Heading).depth;
            if (d < minDepth) minDepth = d;
        }
    }

    const shift = parentDepth + 1 - minDepth;
    if (shift === 0) return [...content];

    return content.map((node) => {
        if (node.type !== "heading") return node;
        const h = node as Heading;
        const newDepth = Math.min(6, Math.max(1, h.depth + shift));
        return { ...h, depth: newDepth as 1 | 2 | 3 | 4 | 5 | 6 };
    });
}

// ---------------------------------------------------------------------------
// Sibling convention check
// ---------------------------------------------------------------------------

/**
 * A file `foo.md` may include only direct children of `foo/`.
 * Returns true if `target` satisfies this rule.
 */
function isSiblingChild(sourceFile: string, target: string): boolean {
    const sourceStem = basename(sourceFile, extname(sourceFile));
    const normalised = target.replace(/\\/g, "/");
    const segments = normalised.split("/").filter((s) => s.length > 0);

    // Target must start with the sibling directory name
    if (segments.length === 0) return false;
    if (segments[0] !== sourceStem) return false;

    // Direct child: exactly sibling/child.md or sibling/child/
    // (one or two segments)
    return segments.length <= 3;
}

function isExternalUrl(url: string): boolean {
    return /^https?:\/\//.test(url) || url.startsWith("mailto:");
}
