/**
 * Utility functions for traversing and extracting data from MDAST nodes.
 *
 * These mirror the shared markdown conventions described in
 * `specs/language.md` (links as enrichment, heading hierarchy,
 * reference-style definitions, document inclusion).
 */
import type {
    Content,
    Heading,
    Link,
    List,
    ListItem,
    PhrasingContent,
    Root,
    Table,
    TableCell,
    TableRow,
    Text,
    InlineCode,
} from "mdast";
import type { ConceptKind, Value } from "./ast.js";

// ---------------------------------------------------------------------------
// Text extraction
// ---------------------------------------------------------------------------

/** Extract plain text from an MDAST node tree, concatenating all text/code values. */
export function nodeText(node: unknown): string {
    const parts: string[] = [];
    function walk(n: unknown): void {
        if (typeof n !== "object" || n === null) return;
        const obj = n as Record<string, unknown>;
        if (typeof obj["value"] === "string") {
            parts.push(obj["value"]);
        }
        const children = obj["children"];
        if (Array.isArray(children)) {
            for (const child of children) {
                walk(child);
            }
        }
    }
    walk(node);
    return parts.join("").trim();
}

// ---------------------------------------------------------------------------
// Heading helpers
// ---------------------------------------------------------------------------

/** Type guard: is this node a Heading at the given depth (or any depth)? */
export function isHeading(node: Content, depth?: number): node is Heading {
    if (node.type !== "heading") return false;
    return depth === undefined || (node as Heading).depth === depth;
}

/**
 * Detect the concept kind declared by a heading's trailing link.
 *
 * Pattern: `# Name [Type](../concepts/type.md)`
 * The concept kind is derived from the link URL's file stem.
 */
export function detectConceptLink(heading: Heading): ConceptKind | null {
    const children = heading.children;
    if (children.length === 0) return null;

    // Look for a Link child whose URL points to a known concept file
    for (const child of children) {
        if (child.type === "link") {
            const kind = conceptKindFromUrl((child as Link).url);
            if (kind !== null) return kind;
        }
    }
    return null;
}

const CONCEPT_STEMS: ReadonlyMap<string, ConceptKind> = new Map([
    ["type.md", "type"],
    ["type-class.md", "type-class"],
    ["operation.md", "operation"],
    ["record.md", "record"],
    ["choice.md", "choice"],
    ["decision-table.md", "decision-table"],
    ["provenance.md", "provenance"],
]);

function conceptKindFromUrl(url: string): ConceptKind | null {
    // Strip anchor
    const base = url.split("#")[0] ?? "";
    // Extract filename
    const segments = base.split("/");
    const filename = segments[segments.length - 1] ?? "";
    return CONCEPT_STEMS.get(filename) ?? null;
}

/**
 * Extract the name portion of a heading that has a concept link.
 *
 * `# Boolean [Type](../concepts/type.md)` → `"Boolean"`
 */
export function headingName(heading: Heading): string {
    const parts: string[] = [];
    for (const child of heading.children) {
        if (child.type === "link") {
            // Stop before the concept link
            const linkText = nodeText(child);
            if (conceptKindFromUrl((child as Link).url) !== null) {
                break;
            }
            parts.push(linkText);
        } else {
            parts.push(nodeText(child));
        }
    }
    return parts.join("").trim();
}

// ---------------------------------------------------------------------------
// Inclusion heading detection
// ---------------------------------------------------------------------------

/**
 * Check if a heading is an inclusion heading: its entire inline content
 * is a single link.
 *
 * Returns the link URL if it is an inclusion heading, null otherwise.
 */
export function inclusionTarget(heading: Heading): string | null {
    const children = heading.children;
    if (children.length !== 1) return null;
    const only = children[0];
    if (only === undefined || only.type !== "link") return null;
    return (only as Link).url;
}

// ---------------------------------------------------------------------------
// GFM anchor slugification
// ---------------------------------------------------------------------------

/**
 * Convert heading text to a GFM-compatible anchor slug.
 *
 * Lowercases, replaces spaces with hyphens, strips non-alphanumeric
 * characters (except hyphens).
 */
export function slugify(text: string): string {
    return text
        .toLowerCase()
        .replace(/[^\w\s-]/g, "")
        .replace(/\s+/g, "-")
        .replace(/-+/g, "-")
        .replace(/^-|-$/g, "");
}

// ---------------------------------------------------------------------------
// Table helpers
// ---------------------------------------------------------------------------

/** Type guard for Table nodes. */
export function isTable(node: Content): node is Table {
    return node.type === "table";
}

/** Type guard for List nodes. */
export function isList(node: Content): node is List {
    return node.type === "list";
}

/** Extract header texts from a table's first row. */
export function tableHeaders(table: Table): readonly string[] {
    const headerRow = table.children[0];
    if (!headerRow) return [];
    return headerRow.children.map((cell) =>
        nodeText(cell).replace(/^`|`$/g, "").trim(),
    );
}

/** Extract cell values from a table row (text, parsed to Value). */
export function rowCells(row: TableRow): readonly string[] {
    return row.children.map((cell) =>
        nodeText(cell).replace(/^`|`$/g, "").trim(),
    );
}

/**
 * Parse a raw cell string into a typed Value.
 *
 * Recognises booleans, numbers, and falls back to string.
 */
export function parseCellValue(raw: string): Value {
    if (raw === "true") return true;
    if (raw === "false") return false;
    const num = Number(raw);
    if (!isNaN(num) && raw !== "") return num;
    return raw;
}

// ---------------------------------------------------------------------------
// Link collection
// ---------------------------------------------------------------------------

/**
 * Recursively collect every link-like node from an MDAST tree — both
 * inline `link` nodes and reference-style `linkReference` nodes.
 *
 * Reference-style links are returned with their `identifier` so callers
 * can resolve them via the document's `definition` nodes.
 */
export function collectLinks(node: Root | Content): readonly LinkRef[] {
    const links: LinkRef[] = [];
    function walk(n: unknown): void {
        if (typeof n !== "object" || n === null) return;
        const obj = n as Record<string, unknown>;
        if (obj["type"] === "link") {
            const link = n as unknown as Link;
            links.push({
                kind: "link",
                url: link.url,
                text: nodeText(link),
                ...(link.position?.start.line !== undefined ? { line: link.position.start.line } : {}),
                ...(link.position?.start.column !== undefined ? { column: link.position.start.column } : {}),
            });
        } else if (obj["type"] === "linkReference") {
            const identifier =
                typeof obj["identifier"] === "string" ? (obj["identifier"] as string) : "";
            const position = obj["position"] as
                | { start?: { line?: number; column?: number } }
                | undefined;
            links.push({
                kind: "linkReference",
                identifier,
                text: nodeText(n),
                ...(position?.start?.line !== undefined ? { line: position.start.line } : {}),
                ...(position?.start?.column !== undefined ? { column: position.start.column } : {}),
            });
        }
        const children = obj["children"];
        if (Array.isArray(children)) {
            for (const child of children) {
                walk(child);
            }
        }
    }
    walk(node);
    return links;
}

export type LinkRef =
    | {
          readonly kind: "link";
          readonly url: string;
          readonly text: string;
          readonly line?: number | undefined;
          readonly column?: number | undefined;
      }
    | {
          readonly kind: "linkReference";
          readonly identifier: string;
          readonly text: string;
          readonly line?: number | undefined;
          readonly column?: number | undefined;
      };

// ---------------------------------------------------------------------------
// Heading collection for anchor building
// ---------------------------------------------------------------------------

/** Collect all headings from a Root and return their slugified anchors. */
export function collectAnchors(root: Root): ReadonlySet<string> {
    const anchors = new Set<string>();
    for (const node of root.children) {
        if (node.type === "heading") {
            const text = nodeText(node);
            anchors.add(slugify(text));
        }
    }
    return anchors;
}
