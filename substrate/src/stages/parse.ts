/**
 * Stage 1: Parse — read a markdown file and convert it to an MDAST tree
 * via unified / remark-parse / remark-gfm.
 */
import { readFile } from "node:fs/promises";
import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import type { Root, Heading } from "mdast";
import type { Diagnostic } from "../types.js";
import type { DocumentKind, SubstrateDocument } from "../language/ast.js";
import { nodeText, detectConceptLink, headingName } from "../language/mdast-utils.js";

/**
 * Parse a markdown file into a SubstrateDocument.
 *
 * Returns the parsed document and any diagnostics (e.g., empty file).
 */
export async function parseFile(
    filePath: string,
): Promise<{ readonly doc: SubstrateDocument; readonly diagnostics: readonly Diagnostic[] }> {
    const diagnostics: Diagnostic[] = [];

    let source: string;
    try {
        source = await readFile(filePath, "utf8");
    } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        return {
            doc: emptyDoc(filePath),
            diagnostics: [{ stage: "parse", severity: "error", file: filePath, message: `Cannot read file: ${message}` }],
        };
    }

    if (source.trim().length === 0) {
        return {
            doc: emptyDoc(filePath),
            diagnostics: [{ stage: "parse", severity: "warning", file: filePath, message: "File is empty" }],
        };
    }

    const processor = unified().use(remarkParse).use(remarkGfm);
    const root: Root = processor.parse(source);

    const title = extractTitle(root);
    const kind = detectDocumentKind(root);

    if (title === "") {
        diagnostics.push({
            stage: "parse",
            severity: "warning",
            file: filePath,
            message: "No h1 heading found; document title is empty",
        });
    }

    return { doc: { filePath, root, title, kind }, diagnostics };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function extractTitle(root: Root): string {
    const first = root.children[0];
    if (first && first.type === "heading" && (first as Heading).depth === 1) {
        return headingName(first as Heading) || nodeText(first);
    }
    return "";
}

function detectDocumentKind(root: Root): DocumentKind {
    const first = root.children[0];
    if (!first || first.type !== "heading" || (first as Heading).depth !== 1) {
        return { type: "unknown" };
    }

    const heading = first as Heading;
    const concept = detectConceptLink(heading);
    const name = headingName(heading) || nodeText(heading);

    if (concept === "type") return { type: "type", name };
    if (concept === "type-class") return { type: "type-class", name };
    if (concept !== null) return { type: "concept", concept, name };

    // No concept link → assume user module or plain document
    return { type: "user-module", name };
}

function emptyDoc(filePath: string): SubstrateDocument {
    return {
        filePath,
        root: { type: "root", children: [] },
        title: "",
        kind: { type: "unknown" },
    };
}
