/**
 * Stage 6: Test — execute every "Test cases" section embedded in the
 * document. A section is detected by the convention from
 * `specs/language/concepts/test-case.md`: a heading whose sole inline
 * content is a link (or reference link) targeting `test-case.md`.
 *
 * The section may use either Table Form or Scenario Form. Both forms
 * are normalised into `{ inputs, outputs }` cases and dispatched to
 * the enclosing definition's evaluator. Only operations carry built-in
 * evaluators today; sections under pipelines, selects, decision trees,
 * etc. produce a warning diagnostic and are skipped.
 */
import type {
    Root,
    Content,
    Heading,
    Table,
    Link,
    LinkReference,
    Definition,
} from "mdast";
import type { Diagnostic } from "../types.js";
import type { Value } from "../language/ast.js";
import {
    detectConceptLink,
    headingName,
    nodeText,
    slugify,
    isTable,
    rowCells,
    parseCellValue,
} from "../language/mdast-utils.js";
import { resolveOperation } from "../language/expressions/index.js";

/** Floating-point comparison tolerance. */
const TOLERANCE = 1e-9;

/** A single test case normalised from either surface form. */
interface TestCase {
    readonly inputs: readonly Value[];
    readonly outputs: readonly Value[];
    readonly label: string;
}

/**
 * Run all test-case sections found in the document and return
 * diagnostics for failures, evaluation errors, and unsupported sites.
 */
export function runTestCases(
    root: Root,
    filePath: string,
): readonly Diagnostic[] {
    const diagnostics: Diagnostic[] = [];
    const children = root.children;
    const definitions = collectDefinitions(root);

    // Track the most recent heading at each depth so a Test cases
    // heading at depth N can find its enclosing definition at N-1.
    const headingByDepth: (Heading | null)[] = [null, null, null, null, null, null, null];

    for (let i = 0; i < children.length; i++) {
        const node = children[i]!;
        if (node.type !== "heading") continue;
        const heading = node as Heading;

        // Any heading invalidates the stack at its own depth and below.
        for (let d = heading.depth; d <= 6; d++) headingByDepth[d] = null;

        if (isTestCasesHeading(heading, definitions)) {
            const parent =
                heading.depth >= 2 ? headingByDepth[heading.depth - 1] : null;
            const line = heading.position?.start.line;

            if (!parent) {
                diagnostics.push({
                    stage: "test",
                    severity: "warning",
                    file: filePath,
                    ...(line !== undefined ? { line } : {}),
                    message:
                        "Test cases section has no enclosing definition heading",
                    ruleId: "orphan-test-cases",
                });
                continue;
            }

            const body = collectBody(children, i, heading.depth);
            processSection(parent, body, filePath, diagnostics);
            continue;
        }

        headingByDepth[heading.depth] = heading;
    }

    return diagnostics;
}

// ---------------------------------------------------------------------------
// Section discovery
// ---------------------------------------------------------------------------

/**
 * A heading is a test-cases section heading when its single inline
 * child is a (reference) link whose URL targets `test-case.md`.
 *
 * As a backward-compatibility fallback, a heading whose plain text is
 * exactly "Test cases" is also accepted — this preserves the older
 * convention used in early fixtures and existing operation specs.
 */
function isTestCasesHeading(
    heading: Heading,
    definitions: ReadonlyMap<string, string>,
): boolean {
    const url = singleLinkTarget(heading, definitions);
    if (url !== null && /(?:^|\/)test-case\.md(?:#|$)/.test(url)) return true;
    return nodeText(heading).toLowerCase() === "test cases";
}

/**
 * If the heading's content is exactly one inline link (either an
 * inline `link` or a `linkReference` resolved against the document's
 * link definitions), return its URL; otherwise null.
 */
function singleLinkTarget(
    heading: Heading,
    definitions: ReadonlyMap<string, string>,
): string | null {
    const kids = heading.children;
    if (kids.length !== 1) return null;
    const only = kids[0]!;
    if (only.type === "link") return (only as Link).url;
    if (only.type === "linkReference") {
        const ref = only as LinkReference;
        return definitions.get(ref.identifier.toLowerCase()) ?? null;
    }
    return null;
}

/** Index every `[id]: url` definition in the document by identifier. */
function collectDefinitions(root: Root): ReadonlyMap<string, string> {
    const out = new Map<string, string>();
    for (const node of root.children) {
        if (node.type === "definition") {
            const def = node as Definition;
            out.set(def.identifier.toLowerCase(), def.url);
        }
    }
    return out;
}

// ---------------------------------------------------------------------------
// Per-section processing
// ---------------------------------------------------------------------------

function processSection(
    parent: Heading,
    body: readonly Content[],
    filePath: string,
    diagnostics: Diagnostic[],
): void {
    const concept = detectConceptLink(parent);
    const name = headingName(parent);
    const line = parent.position?.start.line;
    const lineFields = line !== undefined ? { line } : {};

    if (concept !== "operation") {
        const kind = concept ?? "definition";
        diagnostics.push({
            stage: "test",
            severity: "warning",
            file: filePath,
            ...lineFields,
            message: `Test cases under ${kind} "${name}": no evaluator available for this concept; skipping`,
            ruleId: "no-evaluator-for-concept",
        });
        return;
    }

    const key = guessOperationKey(filePath, `${slugify(name)}-operation`);
    const evaluator = key !== null ? resolveOperation(key) : undefined;
    if (!evaluator) {
        diagnostics.push({
            stage: "test",
            severity: "warning",
            file: filePath,
            ...lineFields,
            message: `Operation "${name}" has no registered evaluator; skipping test cases`,
            ruleId: "no-evaluator",
        });
        return;
    }

    const cases = parseTestCases(
        body,
        evaluator.arity,
        filePath,
        line,
        name,
        diagnostics,
    );

    for (const tc of cases) {
        if (tc.inputs.length !== evaluator.arity) {
            diagnostics.push({
                stage: "test",
                severity: "error",
                file: filePath,
                ...lineFields,
                message: `Operation "${name}" ${tc.label}: arity mismatch — expected ${evaluator.arity} input(s), got ${tc.inputs.length}`,
                ruleId: "test-error",
            });
            continue;
        }
        if (tc.outputs.length === 0) {
            diagnostics.push({
                stage: "test",
                severity: "error",
                file: filePath,
                ...lineFields,
                message: `Operation "${name}" ${tc.label}: no expected output`,
                ruleId: "test-error",
            });
            continue;
        }

        let actual: Value;
        try {
            actual = evaluator.evaluate(tc.inputs);
        } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            diagnostics.push({
                stage: "test",
                severity: "error",
                file: filePath,
                ...lineFields,
                message: `Operation "${name}" ${tc.label}: evaluation error — ${msg}`,
                ruleId: "test-error",
            });
            continue;
        }

        // Operations have one declared output; compare against the
        // first expected-output column. Extra output columns are not
        // meaningful for single-result operations and are ignored.
        const expected = tc.outputs[0]!;
        if (!valuesEqual(actual, expected)) {
            diagnostics.push({
                stage: "test",
                severity: "error",
                file: filePath,
                ...lineFields,
                message: `Operation "${name}" ${tc.label}: expected ${formatValue(expected)}, got ${formatValue(actual)}`,
                ruleId: "test-failure",
            });
        }
    }
}

// ---------------------------------------------------------------------------
// Form detection and parsing
// ---------------------------------------------------------------------------

function parseTestCases(
    body: readonly Content[],
    arity: number,
    filePath: string,
    line: number | undefined,
    opName: string,
    diagnostics: Diagnostic[],
): readonly TestCase[] {
    // Walk the body until we see either the first table (Table Form)
    // or the first sub-heading (Scenario Form). Whichever comes first
    // determines the form.
    for (const node of body) {
        if (node.type === "heading") {
            const depth = (node as Heading).depth;
            return parseScenarioForm(
                body,
                depth,
                arity,
                filePath,
                line,
                opName,
                diagnostics,
            );
        }
        if (isTable(node)) {
            return parseTableForm(node as Table, arity);
        }
    }
    return [];
}

function parseTableForm(table: Table, arity: number): readonly TestCase[] {
    const cases: TestCase[] = [];
    for (let i = 1; i < table.children.length; i++) {
        const row = table.children[i];
        if (!row) continue;
        const cells = rowCells(row).map(parseCellValue);
        const inputs = cells.slice(0, arity);
        const outputs = cells.slice(arity);
        cases.push({ inputs, outputs, label: `row ${i}` });
    }
    return cases;
}

function parseScenarioForm(
    body: readonly Content[],
    scenarioDepth: number,
    arity: number,
    filePath: string,
    line: number | undefined,
    opName: string,
    diagnostics: Diagnostic[],
): readonly TestCase[] {
    const cases: TestCase[] = [];
    let i = 0;
    while (i < body.length) {
        const node = body[i]!;
        if (node.type !== "heading" || (node as Heading).depth !== scenarioDepth) {
            i++;
            continue;
        }
        const scenarioHeading = node as Heading;
        const scenarioName = nodeText(scenarioHeading);
        const scenarioBody: Content[] = [];
        i++;
        while (i < body.length) {
            const n = body[i]!;
            if (
                n.type === "heading" &&
                (n as Heading).depth <= scenarioDepth
            ) {
                break;
            }
            scenarioBody.push(n);
            i++;
        }
        const tc = parseScenario(
            scenarioBody,
            scenarioDepth + 1,
            arity,
            scenarioName,
            filePath,
            line,
            opName,
            diagnostics,
        );
        if (tc) cases.push(tc);
    }
    return cases;
}

function parseScenario(
    body: readonly Content[],
    subDepth: number,
    arity: number,
    scenarioName: string,
    filePath: string,
    line: number | undefined,
    opName: string,
    diagnostics: Diagnostic[],
): TestCase | null {
    const lineFields = line !== undefined ? { line } : {};

    let inputsSection: Content[] | null = null;
    let outputsSection: Content[] | null = null;
    let current: { kind: "inputs" | "outputs"; nodes: Content[] } | null = null;

    const flush = (): void => {
        if (!current) return;
        if (current.kind === "inputs") inputsSection = current.nodes;
        else outputsSection = current.nodes;
    };

    for (const n of body) {
        if (n.type === "heading" && (n as Heading).depth === subDepth) {
            flush();
            const text = nodeText(n).toLowerCase();
            if (text === "inputs") current = { kind: "inputs", nodes: [] };
            else if (text === "expected outputs")
                current = { kind: "outputs", nodes: [] };
            else current = null;
            continue;
        }
        if (current) current.nodes.push(n);
    }
    flush();

    if (!inputsSection || !outputsSection) {
        diagnostics.push({
            stage: "test",
            severity: "warning",
            file: filePath,
            ...lineFields,
            message: `Operation "${opName}" scenario "${scenarioName}": missing "Inputs" or "Expected outputs" section`,
            ruleId: "test-error",
        });
        return null;
    }

    const inputs = extractScenarioValues(
        inputsSection,
        subDepth + 1,
        arity,
        "input",
        scenarioName,
        opName,
        filePath,
        line,
        diagnostics,
    );
    const outputs = extractScenarioValues(
        outputsSection,
        subDepth + 1,
        1,
        "output",
        scenarioName,
        opName,
        filePath,
        line,
        diagnostics,
    );

    if (inputs === null || outputs === null) return null;

    return { inputs, outputs, label: `scenario "${scenarioName}"` };
}

function extractScenarioValues(
    section: readonly Content[],
    nameDepth: number,
    expectedArity: number,
    kind: "input" | "output",
    scenarioName: string,
    opName: string,
    filePath: string,
    line: number | undefined,
    diagnostics: Diagnostic[],
): readonly Value[] | null {
    const lineFields = line !== undefined ? { line } : {};

    if (expectedArity === 1) {
        // Arity-1: section body holds a single value directly. We
        // recognise a paragraph (inline code or plain text). Tables
        // would mean a dataset, which we cannot evaluate today.
        for (const n of section) {
            if (n.type === "paragraph") {
                return [parseCellValue(nodeText(n))];
            }
            if (isTable(n)) {
                diagnostics.push({
                    stage: "test",
                    severity: "warning",
                    file: filePath,
                    ...lineFields,
                    message: `Operation "${opName}" scenario "${scenarioName}": dataset ${kind} is not supported for operation evaluation; skipping`,
                    ruleId: "test-unsupported",
                });
                return null;
            }
        }
        diagnostics.push({
            stage: "test",
            severity: "warning",
            file: filePath,
            ...lineFields,
            message: `Operation "${opName}" scenario "${scenarioName}": no ${kind} value found`,
            ruleId: "test-error",
        });
        return null;
    }

    // Arity > 1: each value lives under its own named sub-sub-heading.
    const values: Value[] = [];
    let i = 0;
    while (i < section.length) {
        const n = section[i]!;
        if (n.type !== "heading" || (n as Heading).depth !== nameDepth) {
            i++;
            continue;
        }
        const inner: Content[] = [];
        i++;
        while (i < section.length) {
            const m = section[i]!;
            if (m.type === "heading" && (m as Heading).depth <= nameDepth) break;
            inner.push(m);
            i++;
        }
        let val: Value | null = null;
        let sawTable = false;
        for (const x of inner) {
            if (x.type === "paragraph") {
                val = parseCellValue(nodeText(x));
                break;
            }
            if (isTable(x)) {
                sawTable = true;
                break;
            }
        }
        if (sawTable) {
            diagnostics.push({
                stage: "test",
                severity: "warning",
                file: filePath,
                ...lineFields,
                message: `Operation "${opName}" scenario "${scenarioName}": dataset ${kind} is not supported for operation evaluation; skipping`,
                ruleId: "test-unsupported",
            });
            return null;
        }
        if (val === null) {
            diagnostics.push({
                stage: "test",
                severity: "warning",
                file: filePath,
                ...lineFields,
                message: `Operation "${opName}" scenario "${scenarioName}": ${kind} subsection has no value`,
                ruleId: "test-error",
            });
            return null;
        }
        values.push(val);
    }
    return values;
}

// ---------------------------------------------------------------------------
// Misc helpers
// ---------------------------------------------------------------------------

function collectBody(
    children: readonly Content[],
    headingIndex: number,
    headingDepth: number,
): readonly Content[] {
    const body: Content[] = [];
    for (let j = headingIndex + 1; j < children.length; j++) {
        const node = children[j]!;
        if (
            node.type === "heading" &&
            (node as Heading).depth <= headingDepth
        ) {
            break;
        }
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

function guessOperationKey(filePath: string, anchor: string): string | null {
    const normalised = filePath.replace(/\\/g, "/");
    const match = /(?:^|\/)(\w+\/[^/]+\.md)$/.exec(normalised);
    if (!match?.[1]) return null;
    return `${match[1]}#${anchor}`;
}
