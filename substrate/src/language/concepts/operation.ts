/**
 * Operation concept — corresponds to `specs/language/concepts/operation.md`.
 *
 * Detects `### Name [Operation](../concepts/operation.md)` headings,
 * extracts the Required/Derived marker, and parses the test-case table.
 */
import type { Content, Heading, Emphasis, Link, Table } from "mdast";
import type { OperationNode, TestCaseTable, TestCaseRow, Value } from "../ast.js";
import {
    detectConceptLink,
    headingName,
    nodeText,
    isHeading,
    isTable,
    tableHeaders,
    rowCells,
    parseCellValue,
} from "../mdast-utils.js";

/** Returns true when the heading declares an Operation. */
export function isOperationHeading(heading: Heading): boolean {
    return detectConceptLink(heading) === "operation";
}

/**
 * Parse an operation from its heading and the content nodes that follow
 * it (up to the next sibling heading at the same or higher level).
 */
export function parseOperation(
    heading: Heading,
    body: readonly Content[],
): OperationNode {
    const name = headingName(heading);
    const marker = detectMarker(body);
    const testCases = findTestCaseTable(heading.depth, body);

    return {
        name,
        marker,
        testCases,
        line: heading.position?.start.line,
    };
}

// ---------------------------------------------------------------------------
// Marker detection
// ---------------------------------------------------------------------------

type Marker = "required" | "derived" | "none";

/**
 * Scan body nodes for an italic paragraph starting with
 * `_[Required](...)_` or `_[Derived](...)_`.
 */
function detectMarker(body: readonly Content[]): Marker {
    for (const node of body) {
        if (node.type !== "paragraph") continue;
        const para = node as { children: readonly Content[] };
        const first = para.children[0];
        if (!first) continue;

        // The marker is typically: _[Required](../concepts/operation.md#required)._
        // In MDAST this is an Emphasis containing a Link.
        if (first.type === "emphasis") {
            const emphChildren = (first as Emphasis).children;
            const link = emphChildren.find((c) => c.type === "link") as Link | undefined;
            if (link) {
                const text = nodeText(link).toLowerCase();
                if (text === "required") return "required";
                if (text === "derived") return "derived";
            }
        }
    }
    return "none";
}

// ---------------------------------------------------------------------------
// Test-case table extraction
// ---------------------------------------------------------------------------

/**
 * Find the test-case table within an operation's body.
 *
 * Looks for a heading containing "test cases" (case-insensitive) followed
 * by a Table node.
 */
function findTestCaseTable(
    operationDepth: number,
    body: readonly Content[],
): TestCaseTable | null {
    let inTestCases = false;

    for (const node of body) {
        if (node.type === "heading") {
            const h = node as Heading;
            // A sibling or higher heading exits the operation scope.
            if (h.depth <= operationDepth) break;
            const text = nodeText(h).toLowerCase();
            inTestCases = text === "test cases";
            continue;
        }

        if (inTestCases && isTable(node)) {
            return parseTestCaseTable(node);
        }
    }
    return null;
}

/** Parse a markdown Table into a TestCaseTable. */
export function parseTestCaseTable(table: Table): TestCaseTable {
    const headers = tableHeaders(table).map((h) => h.replace(/^`|`$/g, "").trim());
    const rows: TestCaseRow[] = [];

    for (let i = 1; i < table.children.length; i++) {
        const row = table.children[i];
        if (!row) continue;
        const rawCells = rowCells(row);
        const cells = rawCells.map((c) => parseCellValue(c));
        rows.push({ cells });
    }

    return { headers, rows };
}
