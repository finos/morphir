/**
 * Stage 7: Test — execute every "Test cases" section embedded in the
 * document. A section is detected by the convention from
 * `specs/language/concepts/test-case.md`: a heading whose sole inline
 * content is a link (or reference link) targeting `test-case.md`.
 *
 * Column headers in test-case tables must be backtick-delimited parameter
 * names (e.g. `` `value` ``, `` `left` ``) matching the operation's
 * Inputs/Outputs signature. The signature is parsed from the `#### Inputs`
 * and `#### Outputs` sections that appear between the operation heading and
 * the test cases heading.
 *
 * When a signature is present, columns are dispatched by name (column order
 * is free). When no signature is found (e.g. type-class instance tests that
 * reference their signature via a cross-file link), arity-based positional
 * splitting is used as a fallback, requiring natural column order.
 *
 * See specs/backlog/spec-implementation-alignment.md decisions 1–3, 8.
 */
import type {
    Root,
    Content,
    Heading,
    Table,
    TableRow,
    TableCell,
    Link,
    LinkReference,
    List,
    ListItem,
    Definition,
    InlineCode,
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
} from "../language/mdast-utils.js";
import {
    resolveOperation,
    normaliseOperationKey,
    parseLiteral,
    parseCellHeuristic,
    typeNameToParserKey,
} from "../language/expressions/index.js";
import {
    parsePipeline,
    evaluatePipeline,
    parseDatasetTable,
} from "../language/dataflow/pipeline-parser.js";

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

const TOLERANCE = 1e-9;

interface TestCase {
    readonly inputs: readonly Value[];
    readonly outputs: readonly Value[];
    readonly label: string;
}

export function runTestCases(
    root: Root,
    filePath: string,
): readonly Diagnostic[] {
    const diagnostics: Diagnostic[] = [];
    const children = root.children;
    const definitions = collectDefinitions(root);

    // Track the most recent heading *index* at each depth (index 0–6 for depths 1–6).
    const headingIdxByDepth: Array<number | null> = [null, null, null, null, null, null, null];

    for (let i = 0; i < children.length; i++) {
        const node = children[i]!;
        if (node.type !== "heading") continue;
        const heading = node as Heading;

        for (let d = heading.depth; d <= 6; d++) headingIdxByDepth[d] = null;

        if (isTestCasesHeading(heading, definitions)) {
            const parentIdx =
                heading.depth >= 2 ? headingIdxByDepth[heading.depth - 1] : null;
            const line = heading.position?.start.line;

            if (parentIdx === null) {
                diagnostics.push({
                    stage: "test",
                    severity: "warning",
                    file: filePath,
                    ...(line !== undefined ? { line } : {}),
                    message: "Test cases section has no enclosing definition heading",
                    ruleId: "orphan-test-cases",
                });
                continue;
            }

            const parentHeading = children[parentIdx!] as Heading;
            // preamble: between parent heading and test cases heading
            const preamble = children.slice(parentIdx! + 1, i) as Content[];
            const body = collectBody(children, i, heading.depth);

            processSection(
                parentHeading,
                preamble,
                body,
                filePath,
                diagnostics,
                root,
                definitions,
            );
            continue;
        }

        headingIdxByDepth[heading.depth] = i;
    }

    return diagnostics;
}

// ---------------------------------------------------------------------------
// Section discovery helpers
// ---------------------------------------------------------------------------

/**
 * Like `detectConceptLink` from mdast-utils but also resolves reference-style
 * links via the document's definitions map. This handles headings like
 * `[Equal][eq-equal] [Operation][op]` where `[op]` is a linkReference.
 */
function detectConceptLinkResolved(
    heading: Heading,
    definitions: ReadonlyMap<string, string>,
): ReturnType<typeof detectConceptLink> {
    // Try the base implementation first (handles inline links).
    const kind = detectConceptLink(heading);
    if (kind !== null) return kind;
    // Fall back: check linkReference children by resolving their URL.
    for (const child of heading.children) {
        if (child.type === "linkReference") {
            const ref = child as LinkReference;
            const url = definitions.get(ref.identifier.toLowerCase());
            if (url === undefined) continue;
            // Re-use the same URL-matching logic via a synthetic Link node.
            const syntheticHeading: Heading = {
                type: "heading",
                depth: heading.depth,
                children: [{ type: "link", url, children: [] } as unknown as Link],
            };
            const resolved = detectConceptLink(syntheticHeading);
            if (resolved !== null) return resolved;
        }
    }
    return null;
}

function isTestCasesHeading(
    heading: Heading,
    definitions: ReadonlyMap<string, string>,
): boolean {
    const url = singleLinkTarget(heading, definitions);
    if (url !== null && /(?:^|\/)test-case\.md(?:#|$)/.test(url)) return true;
    return nodeText(heading).toLowerCase() === "test cases";
}

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
// Signature
// ---------------------------------------------------------------------------

interface SignatureParam {
    readonly name: string;
    readonly parserKey: string | null; // literal parser key, or null if unknown
}

interface OperationSignature {
    readonly inputs: readonly SignatureParam[];
    readonly outputs: readonly SignatureParam[];
}

/**
 * Parse an OperationSignature from the preamble (content between the
 * operation heading and the test cases heading). Returns null if no
 * Inputs or Outputs sections are found.
 */
function parseSignature(
    preamble: readonly Content[],
    definitions: ReadonlyMap<string, string>,
): OperationSignature | null {
    let inputs: SignatureParam[] | null = null;
    let outputs: SignatureParam[] | null = null;
    let i = 0;

    while (i < preamble.length) {
        const node = preamble[i]!;
        if (node.type === "heading") {
            const h = node as Heading;
            const text = nodeText(h).toLowerCase().trim();
            const depth = h.depth;
            const sectionBody: Content[] = [];
            i++;
            while (i < preamble.length) {
                const n = preamble[i]!;
                if (n.type === "heading" && (n as Heading).depth <= depth) break;
                sectionBody.push(n);
                i++;
            }
            if (text === "inputs") inputs = parseParamList(sectionBody, definitions);
            else if (text === "outputs") outputs = parseParamList(sectionBody, definitions);
        } else {
            i++;
        }
    }

    if (inputs === null && outputs === null) return null;
    return { inputs: inputs ?? [], outputs: outputs ?? [] };
}

function parseParamList(
    nodes: readonly Content[],
    definitions: ReadonlyMap<string, string>,
): SignatureParam[] {
    for (const node of nodes) {
        if (node.type === "list") {
            return (node as List).children.map((item) =>
                parseParamItem(item as ListItem, definitions),
            );
        }
    }
    return [];
}

function parseParamItem(
    item: ListItem,
    definitions: ReadonlyMap<string, string>,
): SignatureParam {
    // Expected structure in each paragraph of the list item:
    //   `paramName`: [TypeName][anchor]
    // We extract the name from the first inlineCode child, and the type
    // from the first link or linkReference in the item.
    let name = "";
    let parserKey: string | null = null;

    function walk(node: unknown): void {
        if (typeof node !== "object" || node === null) return;
        const obj = node as Record<string, unknown>;
        const t = obj["type"] as string | undefined;

        if (t === "inlineCode" && name === "") {
            name = (obj["value"] as string | undefined) ?? "";
        } else if (t === "link" && parserKey === null) {
            const linkText = nodeText(node).toLowerCase();
            parserKey = typeNameToParserKey(linkText);
        } else if (t === "linkReference" && parserKey === null) {
            const ref = obj as unknown as LinkReference;
            const resolved = definitions.get(ref.identifier.toLowerCase());
            if (resolved) {
                const key = normaliseOperationKey(resolved);
                if (key !== null) {
                    parserKey = key;
                } else {
                    // Try by link text
                    const linkText = nodeText(node).toLowerCase();
                    parserKey = typeNameToParserKey(linkText);
                }
            } else {
                const linkText = nodeText(node).toLowerCase();
                parserKey = typeNameToParserKey(linkText);
            }
        }

        const children = obj["children"];
        if (Array.isArray(children)) {
            for (const c of children) walk(c);
        }
    }

    walk(item);
    return { name, parserKey };
}

// ---------------------------------------------------------------------------
// Operation key resolution
// ---------------------------------------------------------------------------

/**
 * Resolve the registry key for an operation.
 *
 * Strategy (in order):
 * 1. Look for a non-concept link in the heading that resolves to a registry key.
 *    This handles type-class instance headings like `[Equal][eq-equal] [Operation][op]`
 *    where `eq-equal` resolves to `equality.md#equal-operation`.
 * 2. Fall back to slugifying the heading name + "-operation" and combining with
 *    the file path.
 */
function resolveOperationKey(
    heading: Heading,
    filePath: string,
    definitions: ReadonlyMap<string, string>,
): string | null {
    // Try each link/linkReference in the heading; skip the trailing [Operation] link.
    for (const child of heading.children) {
        let url: string | null = null;
        if (child.type === "link") {
            url = (child as Link).url;
        } else if (child.type === "linkReference") {
            const ref = child as LinkReference;
            url = definitions.get(ref.identifier.toLowerCase()) ?? null;
        }
        if (url === null) continue;
        // Skip concept-kind links (operation.md, type-class.md, …)
        if (/(?:^|\/)(?:operation|type-class|datatype|record|choice|decision-table|provenance|pipeline)\.md(?:#|$)/.test(url)) {
            continue;
        }
        // Resolve relative URL against the file's directory before normalising.
        const resolved = resolveRelativeUrl(url, filePath);
        const key = normaliseOperationKey(resolved);
        if (key !== null && resolveOperation(key) !== undefined) return key;
    }

    // Fallback: slug from heading name + file path
    const name = headingName(heading);
    const slug = `${slugify(name)}-operation`;
    return guessOperationKey(filePath, slug);
}

/**
 * Resolve a URL that may be relative (e.g. `equality.md#equal-operation`)
 * against the directory of the containing file so `normaliseOperationKey`
 * has enough path segments to work with.
 */
function resolveRelativeUrl(url: string, fromFile: string): string {
    if (url.startsWith("http") || url.startsWith("/")) return url;
    const hashIdx = url.indexOf("#");
    const filePart = hashIdx >= 0 ? url.slice(0, hashIdx) : url;
    const anchor = hashIdx >= 0 ? url.slice(hashIdx + 1) : null;
    if (filePart.includes("/")) return url; // already has a directory component
    // Prepend the directory of the containing file
    const dir = fromFile.replace(/\\/g, "/").replace(/[^/]+$/, "");
    const joined = dir + filePart;
    return anchor ? `${joined}#${anchor}` : joined;
}

function guessOperationKey(filePath: string, anchor: string): string | null {
    const normalised = filePath.replace(/\\/g, "/");
    const match = /(?:^|\/)(\w+\/[^/]+\.md)$/.exec(normalised);
    if (!match?.[1]) return null;
    return `${match[1]}#${anchor}`;
}

// ---------------------------------------------------------------------------
// Per-section processing
// ---------------------------------------------------------------------------

function processSection(
    parent: Heading,
    preamble: readonly Content[],
    body: readonly Content[],
    filePath: string,
    diagnostics: Diagnostic[],
    root: Root,
    definitions: ReadonlyMap<string, string>,
): void {
    const concept = detectConceptLinkResolved(parent, definitions);
    const name = headingName(parent);
    const line = parent.position?.start.line;
    const lineFields = line !== undefined ? { line } : {};

    if (concept === "pipeline") {
        processPipelineSection(root, body, filePath, definitions, diagnostics, line);
        return;
    }

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

    const key = resolveOperationKey(parent, filePath, definitions);
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

    // Parse the signature from the Inputs/Outputs sections in the preamble.
    const signature = parseSignature(preamble, definitions);

    const cases = parseTestCases(
        body,
        evaluator.arity,
        signature,
        filePath,
        line,
        name,
        diagnostics,
    );

    let passCount = 0;

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
        } else {
            passCount++;
        }
    }

    if (cases.length > 0) {
        diagnostics.push({
            stage: "test",
            severity: "info",
            file: filePath,
            ...lineFields,
            message: `Operation "${name}": ${passCount}/${cases.length} test case(s) passed`,
            ruleId: "test-pass",
        });
    }
}

// ---------------------------------------------------------------------------
// Pipeline test-case evaluation (unchanged)
// ---------------------------------------------------------------------------

function processPipelineSection(
    root: Root,
    body: readonly Content[],
    filePath: string,
    definitions: ReadonlyMap<string, string>,
    diagnostics: Diagnostic[],
    line: number | undefined,
): void {
    const lineFields = line !== undefined ? { line } : {};

    let pipeline: ReturnType<typeof parsePipeline>;
    try {
        pipeline = parsePipeline(root, definitions);
    } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        diagnostics.push({
            stage: "test",
            severity: "error",
            file: filePath,
            ...lineFields,
            message: `Failed to parse pipeline structure: ${msg}`,
            ruleId: "pipeline-parse-error",
        });
        return;
    }

    if (!pipeline) {
        diagnostics.push({
            stage: "test",
            severity: "warning",
            file: filePath,
            ...lineFields,
            message: "Pipeline is missing Input, Steps, or Output section; skipping test cases",
            ruleId: "pipeline-incomplete",
        });
        return;
    }

    const outputCols = pipeline.outputSchema.map((c) => c.name);
    const scenarios = parsePipelineScenarios(body);

    for (const scenario of scenarios) {
        let actualRows: ReturnType<typeof evaluatePipeline>;
        try {
            actualRows = evaluatePipeline(pipeline, scenario.inputRows);
        } catch (err) {
            const msg = err instanceof Error ? err.message : String(err);
            diagnostics.push({
                stage: "test",
                severity: "error",
                file: filePath,
                ...lineFields,
                message: `Pipeline scenario "${scenario.name}": evaluation error — ${msg}`,
                ruleId: "test-error",
            });
            continue;
        }

        if (actualRows.length !== scenario.expectedRows.length) {
            diagnostics.push({
                stage: "test",
                severity: "error",
                file: filePath,
                ...lineFields,
                message: `Pipeline scenario "${scenario.name}": expected ${scenario.expectedRows.length} row(s), got ${actualRows.length}`,
                ruleId: "test-failure",
            });
            continue;
        }

        let scenarioPassed = true;
        for (let rowIdx = 0; rowIdx < actualRows.length; rowIdx++) {
            const actualRow = actualRows[rowIdx]!;
            const expectedRow = scenario.expectedRows[rowIdx]!;
            for (const col of outputCols) {
                const actual = actualRow[col];
                const expected = expectedRow[col];
                if (!valuesEqual(actual as Value, expected as Value)) {
                    scenarioPassed = false;
                    diagnostics.push({
                        stage: "test",
                        severity: "error",
                        file: filePath,
                        ...lineFields,
                        message: `Pipeline scenario "${scenario.name}" row ${rowIdx + 1}, column "${col}": expected ${formatValue(expected as Value)}, got ${formatValue(actual as Value)}`,
                        ruleId: "test-failure",
                    });
                }
            }
        }

        if (scenarioPassed) {
            const rowCount = actualRows.length;
            diagnostics.push({
                stage: "test",
                severity: "info",
                file: filePath,
                ...lineFields,
                message: `Pipeline scenario "${scenario.name}": passed (${rowCount} row${rowCount === 1 ? "" : "s"})`,
                ruleId: "test-pass",
            });
        }
    }
}

interface PipelineScenario {
    readonly name: string;
    readonly inputRows: ReturnType<typeof parseDatasetTable>;
    readonly expectedRows: ReturnType<typeof parseDatasetTable>;
}

function parsePipelineScenarios(body: readonly Content[]): PipelineScenario[] {
    const scenarios: PipelineScenario[] = [];
    let i = 0;
    while (i < body.length) {
        const node = body[i]!;
        if (node.type !== "heading") { i++; continue; }
        const scenarioHeading = node as Heading;
        const scenarioName = nodeText(scenarioHeading);
        const subDepth = scenarioHeading.depth + 1;
        const scenarioBody: Content[] = [];
        i++;
        while (i < body.length) {
            const n = body[i]!;
            if (n.type === "heading" && (n as Heading).depth <= scenarioHeading.depth) break;
            scenarioBody.push(n);
            i++;
        }
        const scenario = parsePipelineScenario(scenarioName, scenarioBody, subDepth);
        if (scenario) scenarios.push(scenario);
    }
    return scenarios;
}

function parsePipelineScenario(
    name: string,
    body: Content[],
    sectionDepth: number,
): PipelineScenario | null {
    let inputTable: Table | null = null;
    let outputTable: Table | null = null;
    let i = 0;
    while (i < body.length) {
        const node = body[i]!;
        if (node.type === "heading" && (node as Heading).depth === sectionDepth) {
            const text = nodeText(node as Heading).toLowerCase();
            const sectionBody: Content[] = [];
            i++;
            while (i < body.length) {
                const n = body[i]!;
                if (n.type === "heading" && (n as Heading).depth <= sectionDepth) break;
                sectionBody.push(n);
                i++;
            }
            if (text === "inputs") inputTable = findTable(sectionBody);
            else if (text === "expected outputs") outputTable = findTable(sectionBody);
        } else {
            i++;
        }
    }
    if (!inputTable || !outputTable) return null;
    return {
        name,
        inputRows: parseDatasetTable(inputTable),
        expectedRows: parseDatasetTable(outputTable),
    };
}

function findTable(nodes: Content[]): Table | null {
    for (const n of nodes) {
        if (isTable(n)) return n as Table;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Test case parsing — named columns + signature
// ---------------------------------------------------------------------------

function parseTestCases(
    body: readonly Content[],
    arity: number,
    signature: OperationSignature | null,
    filePath: string,
    line: number | undefined,
    opName: string,
    diagnostics: Diagnostic[],
): readonly TestCase[] {
    for (const node of body) {
        if (node.type === "heading") {
            return parseScenarioForm(body, (node as Heading).depth, arity, filePath, line, opName, diagnostics);
        }
        if (isTable(node)) {
            return parseTableForm(node as Table, arity, signature);
        }
    }
    return [];
}

/**
 * Parse a test-case table. When named columns are present and a signature
 * is available, dispatch columns by name. Otherwise use positional splitting.
 */
function parseTableForm(
    table: Table,
    arity: number,
    signature: OperationSignature | null,
): readonly TestCase[] {
    const headerRow = table.children[0];
    if (!headerRow) return [];

    // Extract column info: name (with backtick stripped) + whether it was backtick-delimited
    const columns = headerRow.children.map((cell) => extractColumnInfo(cell));
    const hasNamedColumns = columns.some((c) => c.isNamed);

    if (hasNamedColumns && signature !== null) {
        return parseTableNamed(table, columns, signature);
    }

    // Positional fallback: first `arity` columns = inputs, rest = outputs
    const cases: TestCase[] = [];
    for (let i = 1; i < table.children.length; i++) {
        const row = table.children[i]!;
        const cells = rawCellStrings(row);
        const inputs = cells.slice(0, arity).map((raw, colIdx) => {
            const parserKey = signature?.inputs[colIdx]?.parserKey ?? null;
            return parseCell(raw, parserKey);
        });
        const outputs = cells.slice(arity).map((raw) => {
            const outputIdx = 0;
            const parserKey = signature?.outputs[outputIdx]?.parserKey ?? null;
            return parseCell(raw, parserKey);
        });
        cases.push({ inputs, outputs, label: `row ${i}` });
    }
    return cases;
}

interface ColumnInfo {
    readonly name: string;   // parameter name (backtick stripped)
    readonly isNamed: boolean; // was the header backtick-delimited in source
}

function extractColumnInfo(cell: TableCell): ColumnInfo {
    // Check if the cell's paragraph has an inlineCode child (backtick-delimited)
    for (const child of cell.children) {
        if (child.type === "inlineCode") {
            return { name: (child as InlineCode).value.trim(), isNamed: true };
        }
    }
    // Plain text header
    const name = nodeText(cell).replace(/^`|`$/g, "").trim();
    return { name, isNamed: false };
}

function parseTableNamed(
    table: Table,
    columns: ColumnInfo[],
    signature: OperationSignature,
): readonly TestCase[] {
    // Build index: parameter name → { kind: "input"|"output", index: number, parserKey }
    const colMap = new Map<
        string,
        { kind: "input" | "output"; idx: number; parserKey: string | null }
    >();
    for (let i = 0; i < signature.inputs.length; i++) {
        const p = signature.inputs[i]!;
        colMap.set(p.name, { kind: "input", idx: i, parserKey: p.parserKey });
    }
    for (let i = 0; i < signature.outputs.length; i++) {
        const p = signature.outputs[i]!;
        colMap.set(p.name, { kind: "output", idx: i, parserKey: p.parserKey });
    }

    const cases: TestCase[] = [];
    for (let rowIdx = 1; rowIdx < table.children.length; rowIdx++) {
        const row = table.children[rowIdx]!;
        const cells = rawCellStrings(row);
        const inputs: Value[] = new Array(signature.inputs.length).fill(null) as Value[];
        const outputs: Value[] = new Array(signature.outputs.length).fill(null) as Value[];

        for (let colIdx = 0; colIdx < columns.length; colIdx++) {
            const col = columns[colIdx]!;
            const binding = colMap.get(col.name);
            if (!binding) continue; // unknown column — skip silently
            const raw = cells[colIdx] ?? "";
            const val = parseCell(raw, binding.parserKey);
            if (binding.kind === "input") inputs[binding.idx] = val;
            else outputs[binding.idx] = val;
        }

        cases.push({
            inputs: inputs as readonly Value[],
            outputs: outputs as readonly Value[],
            label: `row ${rowIdx}`,
        });
    }
    return cases;
}

function rawCellStrings(row: TableRow): string[] {
    return row.children.map((cell) => {
        // Check for inlineCode child first (preserves quoted strings etc.)
        for (const child of cell.children) {
            if (child.type === "inlineCode") {
                return (child as InlineCode).value.trim();
            }
        }
        return nodeText(cell).replace(/^`|`$/g, "").trim();
    });
}

function parseCell(raw: string, parserKey: string | null): Value {
    if (parserKey !== null) {
        const result = parseLiteral(parserKey, raw);
        if (result !== null) return result;
    }
    return parseCellHeuristic(raw);
}

// ---------------------------------------------------------------------------
// Scenario form (unchanged from original, with minor tweaks for signature)
// ---------------------------------------------------------------------------

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
            if (n.type === "heading" && (n as Heading).depth <= scenarioDepth) break;
            scenarioBody.push(n);
            i++;
        }
        const tc = parseScenario(scenarioBody, scenarioDepth + 1, arity, scenarioName, filePath, line, opName, diagnostics);
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
            else if (text === "expected outputs") current = { kind: "outputs", nodes: [] };
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

    const inputs = extractScenarioValues(inputsSection, subDepth + 1, arity, "input", scenarioName, opName, filePath, line, diagnostics);
    const outputs = extractScenarioValues(outputsSection, subDepth + 1, 1, "output", scenarioName, opName, filePath, line, diagnostics);

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
        for (const n of section) {
            if (n.type === "paragraph") {
                return [parseCellHeuristic(nodeText(n))];
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

    const values: Value[] = [];
    let i = 0;
    while (i < section.length) {
        const n = section[i]!;
        if (n.type !== "heading" || (n as Heading).depth !== nameDepth) { i++; continue; }
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
            if (x.type === "paragraph") { val = parseCellHeuristic(nodeText(x)); break; }
            if (isTable(x)) { sawTable = true; break; }
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
