/**
 * Stage 6: Test — execute test-case tables found in the document
 * against the built-in operation evaluators.
 */
import type { Root, Content, Heading } from "mdast";
import type { Diagnostic } from "../types.js";
import type { TestCaseTable, Value } from "../language/ast.js";
import {
    isOperationHeading,
    parseOperation,
} from "../language/concepts/operation.js";
import { headingName } from "../language/mdast-utils.js";
import { resolveOperation } from "../language/expressions/index.js";

/** Floating-point comparison tolerance. */
const TOLERANCE = 1e-9;

/**
 * Run all test-case tables found in the document and return diagnostics
 * for failures.
 */
export function runTestCases(
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

        if (op.testCases === null || op.testCases.rows.length === 0) continue;

        // Build the operation key from the file path and operation name
        const anchor = slugifyOperationName(op.name);
        const key = guessOperationKey(filePath, anchor);
        if (key === null) continue;

        const evaluator = resolveOperation(key);
        if (!evaluator) {
            diagnostics.push({
                stage: "test",
                severity: "info",
                file: filePath,
                line: op.line,
                message: `Operation "${op.name}" has no registered evaluator; skipping test cases`,
                ruleId: "no-evaluator",
            });
            continue;
        }

        // Run each test-case row
        const inputCount = op.testCases.headers.length - 1;
        for (let rowIdx = 0; rowIdx < op.testCases.rows.length; rowIdx++) {
            const row = op.testCases.rows[rowIdx]!;
            const inputs = row.cells.slice(0, inputCount);
            const expected = row.cells[row.cells.length - 1];

            if (expected === undefined) continue;

            let actual: Value;
            try {
                actual = evaluator.evaluate(inputs);
            } catch (err: unknown) {
                const msg = err instanceof Error ? err.message : String(err);
                diagnostics.push({
                    stage: "test",
                    severity: "error",
                    file: filePath,
                    line: op.line,
                    message: `Operation "${op.name}" row ${rowIdx + 1}: evaluation error — ${msg}`,
                    ruleId: "test-error",
                });
                continue;
            }

            if (!valuesEqual(actual, expected)) {
                diagnostics.push({
                    stage: "test",
                    severity: "error",
                    file: filePath,
                    line: op.line,
                    message: `Operation "${op.name}" row ${rowIdx + 1}: expected ${formatValue(expected)}, got ${formatValue(actual)}`,
                    ruleId: "test-failure",
                });
            }
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

function valuesEqual(actual: Value, expected: Value): boolean {
    if (typeof actual === "number" && typeof expected === "number") {
        return Math.abs(actual - expected) <= TOLERANCE;
    }
    return actual === expected;
}

function formatValue(v: Value): string {
    return String(v);
}

function slugifyOperationName(name: string): string {
    return name
        .toLowerCase()
        .replace(/[^\w\s-]/g, "")
        .replace(/\s+/g, "-") + "-operation";
}

function guessOperationKey(filePath: string, anchor: string): string | null {
    const normalised = filePath.replace(/\\/g, "/");
    const match = /(?:^|\/)(\w+\/[^/]+\.md)$/.exec(normalised);
    if (!match?.[1]) return null;
    return `${match[1]}#${anchor}`;
}
