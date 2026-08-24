/**
 * Stage 5: Typecheck — validate operation arities, return types,
 * and derived-operation dependencies.
 */
import type { Root, Content, Heading, Link, Emphasis } from "mdast";
import type { Diagnostic } from "../types.js";
import {
    detectConceptLink,
    headingName,
    nodeText,
    isTable,
    tableHeaders,
} from "../language/mdast-utils.js";
import { isOperationHeading, parseOperation } from "../language/concepts/operation.js";
import { resolveOperation, normaliseOperationKey } from "../language/expressions/index.js";

/**
 * Type-check a document: validate operation arities match their
 * test-case tables and that referenced operations exist in the registry.
 */
export function typecheckDocument(
    root: Root,
    filePath: string,
): readonly Diagnostic[] {
    const diagnostics: Diagnostic[] = [];
    const children = root.children;

    for (let i = 0; i < children.length; i++) {
        const node = children[i]!;
        if (node.type !== "heading") continue;
        const heading = node as Heading;

        if (!isOperationHeading(heading)) continue;

        const body = collectBody(children, i, heading.depth);
        const op = parseOperation(heading, body);

        if (op.testCases === null) continue;

        // Check that all test rows have the correct number of columns
        const expectedCols = op.testCases.headers.length;
        for (let rowIdx = 0; rowIdx < op.testCases.rows.length; rowIdx++) {
            const row = op.testCases.rows[rowIdx]!;
            if (row.cells.length !== expectedCols) {
                diagnostics.push({
                    stage: "typecheck",
                    severity: "error",
                    file: filePath,
                    line: op.line,
                    message: `Operation "${op.name}" test row ${rowIdx + 1} has ${row.cells.length} cells, expected ${expectedCols}`,
                    ruleId: "test-row-arity",
                });
            }
        }

        // Check that the operation's arity (inputs = headers - 1 for output)
        // matches the registry's arity if the operation is known.
        // We need the file path to build the operation key.
        const opAnchor = slugifyOperationName(op.name);
        const guessedKey = guessOperationKey(filePath, opAnchor);
        if (guessedKey) {
            const evaluator = resolveOperation(guessedKey);
            if (evaluator) {
                const inputCount = op.testCases.headers.length - 1;
                if (inputCount !== evaluator.arity) {
                    diagnostics.push({
                        stage: "typecheck",
                        severity: "error",
                        file: filePath,
                        line: op.line,
                        message: `Operation "${op.name}" test table has ${inputCount} input columns but evaluator expects ${evaluator.arity} arguments`,
                        ruleId: "operation-arity-mismatch",
                    });
                }
            }
        }

        // Check derived operations reference required operations
        if (op.marker === "derived") {
            diagnostics.push(...checkDerivedReferences(heading, body, filePath));
        }
    }

    return diagnostics;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function collectBody(
    children: readonly Content[],
    headingIndex: number,
    headingDepth: number,
): readonly Content[] {
    const body: Content[] = [];
    for (let j = headingIndex + 1; j < children.length; j++) {
        const node = children[j]!;
        if (node.type === "heading" && (node as Heading).depth <= headingDepth) break;
        body.push(node);
    }
    return body;
}

/**
 * Check that a derived operation's description references at least one
 * other operation (via a link).
 */
function checkDerivedReferences(
    heading: Heading,
    body: readonly Content[],
    filePath: string,
): readonly Diagnostic[] {
    // Look for links in the description paragraphs
    for (const node of body) {
        if (node.type === "heading") break; // Stop at next heading
        if (node.type === "paragraph") {
            if (containsOperationLink(node)) {
                return [];
            }
        }
    }
    return [
        {
            stage: "typecheck",
            severity: "warning",
            file: filePath,
            line: heading.position?.start.line,
            message: `Derived operation "${headingName(heading)}" does not reference the required operation(s) it is defined in terms of`,
            ruleId: "derived-missing-reference",
        },
    ];
}

function containsOperationLink(node: unknown): boolean {
    if (typeof node !== "object" || node === null) return false;
    const obj = node as Record<string, unknown>;
    if (obj["type"] === "link") {
        const url = (node as unknown as Link).url;
        return url.includes("#") || url.includes("operation");
    }
    const children = obj["children"];
    if (Array.isArray(children)) {
        for (const child of children) {
            if (containsOperationLink(child)) return true;
        }
    }
    return false;
}

function slugifyOperationName(name: string): string {
    return name
        .toLowerCase()
        .replace(/[^\w\s-]/g, "")
        .replace(/\s+/g, "-") + "-operation";
}

/**
 * Guess the full operation key from the file path and anchor.
 *
 * For a file like `.../expressions/boolean.md`, the key would be
 * `expressions/boolean.md#not-operation`.
 */
function guessOperationKey(filePath: string, anchor: string): string | null {
    const normalised = filePath.replace(/\\/g, "/");
    const match = /(?:^|\/)(\w+\/[^/]+\.md)$/.exec(normalised);
    if (!match?.[1]) return null;
    return `${match[1]}#${anchor}`;
}
