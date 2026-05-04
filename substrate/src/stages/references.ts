/**
 * Stage 4: References — verify that every internal link resolves to
 * an existing file and anchor.
 */
import { stat } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import type { Root, Definition } from "mdast";
import type { Diagnostic } from "../types.js";
import { collectLinks, collectAnchors } from "../language/mdast-utils.js";
import type { LinkRef } from "../language/mdast-utils.js";

/**
 * Check all internal links in the document.
 *
 * `knownFiles` maps absolute paths to their set of heading anchors.
 * If not provided, files are checked on disk (slower).
 */
export async function checkReferences(
    root: Root,
    filePath: string,
    knownFiles?: ReadonlyMap<string, ReadonlySet<string>>,
): Promise<readonly Diagnostic[]> {
    const diagnostics: Diagnostic[] = [];
    const baseDir = dirname(resolve(filePath));

    // Build anchor map for the current file
    const selfAnchors = collectAnchors(root);

    // Collect link definitions (reference-style) for resolution
    const definitions = new Map<string, string>();
    for (const node of root.children) {
        if (node.type === "definition") {
            const def = node as Definition;
            definitions.set(def.identifier, def.url);
        }
    }

    const links = collectLinks(root);

    for (const link of links) {
        const url = resolveLinkUrl(link, definitions);
        if (url === null) {
            diagnostics.push({
                stage: "references",
                severity: "error",
                file: filePath,
                ...(link.line !== undefined ? { line: link.line } : {}),
                ...(link.column !== undefined ? { column: link.column } : {}),
                message: `Undefined link reference: [${link.kind === "linkReference" ? link.identifier : link.text}]`,
                ruleId: "undefined-reference",
            });
            continue;
        }

        // Skip external URLs and mailto
        if (/^https?:\/\//.test(url) || url.startsWith("mailto:")) continue;

        // Parse file path and anchor
        const hashIdx = url.indexOf("#");
        const filePart = hashIdx >= 0 ? url.slice(0, hashIdx) : url;
        const anchor = hashIdx >= 0 ? url.slice(hashIdx + 1) : null;

        // Same-file anchor reference
        if (filePart === "") {
            if (anchor !== null && !selfAnchors.has(anchor)) {
                diagnostics.push({
                    stage: "references",
                    severity: "error",
                    file: filePath,
                    ...(link.line !== undefined ? { line: link.line } : {}),
                    ...(link.column !== undefined ? { column: link.column } : {}),
                    message: `Anchor "#${anchor}" not found in current file`,
                    ruleId: "broken-anchor",
                });
            }
            continue;
        }

        // Resolve the target file path
        const targetPath = resolve(baseDir, filePart);

        // Check file existence
        if (knownFiles) {
            if (!knownFiles.has(targetPath)) {
                // Allow directories (they won't be in knownFiles but may exist)
                const exists = await fileExists(targetPath);
                if (!exists) {
                    diagnostics.push({
                        stage: "references",
                        severity: "error",
                        file: filePath,
                        ...(link.line !== undefined ? { line: link.line } : {}),
                        ...(link.column !== undefined ? { column: link.column } : {}),
                        message: `Link target not found: ${filePart}`,
                        ruleId: "broken-link",
                    });
                    continue;
                }
            }

            // Check anchor in known file
            if (anchor !== null) {
                const targetAnchors = knownFiles.get(targetPath);
                if (targetAnchors && !targetAnchors.has(anchor)) {
                    diagnostics.push({
                        stage: "references",
                        severity: "error",
                        file: filePath,
                        ...(link.line !== undefined ? { line: link.line } : {}),
                        ...(link.column !== undefined ? { column: link.column } : {}),
                        message: `Anchor "#${anchor}" not found in ${filePart}`,
                        ruleId: "broken-anchor",
                    });
                }
            }
        } else {
            // Fall back to disk check
            const exists = await fileExists(targetPath);
            if (!exists) {
                diagnostics.push({
                    stage: "references",
                    severity: "error",
                    file: filePath,
                    ...(link.line !== undefined ? { line: link.line } : {}),
                    ...(link.column !== undefined ? { column: link.column } : {}),
                    message: `Link target not found: ${filePart}`,
                    ruleId: "broken-link",
                });
            }
        }
    }

    return diagnostics;
}

/**
 * Return the effective URL of a link — either its inline URL or the
 * URL of the definition it references. Returns null if the reference
 * is undefined.
 */
function resolveLinkUrl(
    link: LinkRef,
    definitions: ReadonlyMap<string, string>,
): string | null {
    if (link.kind === "link") return link.url;
    const def = definitions.get(link.identifier);
    return def ?? null;
}

async function fileExists(path: string): Promise<boolean> {
    try {
        await stat(path);
        return true;
    } catch {
        return false;
    }
}
