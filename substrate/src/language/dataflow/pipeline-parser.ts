/**
 * Pipeline parser and evaluator.
 *
 * Parses the Input / Steps / Output sections of a pipeline document into
 * a `ParsedPipeline` structure, then provides `evaluatePipeline` to run
 * that pipeline against a dataset of input rows.
 *
 * Also exports `parseDatasetCellValue` which extends the shared
 * `parseCellValue` with the substrate string-literal convention:
 * a cell value written as `"text"` (double-quote delimited) is
 * interpreted as the string `text` — the same stripping that
 * `parse-expr.ts` applies to string literals in expression trees.
 */
import type { Root, Content, Heading, List, ListItem, Paragraph, InlineCode, Link, LinkReference } from "mdast";
import type { Expr, Value } from "../ast.js";
import { parseCellValue, rowCells } from "../mdast-utils.js";
import { parseExprList } from "../expressions/parse-expr.js";
import { evalExpr } from "../expressions/eval-expr.js";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface SchemaColumn {
    readonly name: string;
}

export interface OutputColumn {
    readonly name: string;
    readonly expr: Expr;
}

export interface SelectStep {
    readonly kind: "select";
    readonly columns: readonly OutputColumn[];
}

export type PipelineStep = SelectStep;

export interface ParsedPipeline {
    readonly inputSchema: readonly SchemaColumn[];
    readonly steps: readonly PipelineStep[];
    readonly outputSchema: readonly SchemaColumn[];
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/**
 * Parse the Input / Steps / Output sections from a pipeline document root.
 * Returns null if any required section is missing.
 */
export function parsePipeline(
    root: Root,
    definitions: ReadonlyMap<string, string>,
): ParsedPipeline | null {
    const inputBody = findSection(root, "input");
    const stepsBody = findSection(root, "steps");
    const outputBody = findSection(root, "output");

    if (!inputBody || !stepsBody || !outputBody) return null;

    const inputSchema = parseSchemaSection(inputBody);
    const steps = parseStepsSection(stepsBody, definitions);
    const outputSchema = parseSchemaSection(outputBody);

    return { inputSchema, steps, outputSchema };
}

/** Find the body nodes of the first h2 section whose heading text matches `name` (case-insensitive). */
function findSection(root: Root, name: string): Content[] | null {
    const children = root.children;
    for (let i = 0; i < children.length; i++) {
        const node = children[i]!;
        if (node.type !== "heading") continue;
        const h = node as Heading;
        if (h.depth !== 2) continue;
        if (headingText(h).toLowerCase() !== name) continue;

        const body: Content[] = [];
        for (let j = i + 1; j < children.length; j++) {
            const n = children[j]!;
            if (n.type === "heading" && (n as Heading).depth <= 2) break;
            body.push(n);
        }
        return body;
    }
    return null;
}

/** Extract schema columns from the body of an Input or Output section. */
function parseSchemaSection(body: Content[]): SchemaColumn[] {
    const columns: SchemaColumn[] = [];
    for (const node of body) {
        if (node.type !== "list") continue;
        for (const item of (node as List).children) {
            const para = firstParagraph(item as ListItem);
            if (!para) continue;
            const name = firstInlineCode(para);
            if (name) columns.push({ name });
        }
    }
    return columns;
}

/** Parse the ordered Steps list into PipelineStep objects. */
function parseStepsSection(
    body: Content[],
    definitions: ReadonlyMap<string, string>,
): PipelineStep[] {
    const steps: PipelineStep[] = [];
    for (const node of body) {
        if (node.type !== "list") continue;
        for (const item of (node as List).children) {
            const step = parseStep(item as ListItem, definitions);
            if (step) steps.push(step);
        }
    }
    return steps;
}

function parseStep(
    item: ListItem,
    definitions: ReadonlyMap<string, string>,
): PipelineStep | null {
    const para = firstParagraph(item);
    if (!para) return null;

    // Detect the step kind from the first link in the paragraph.
    for (const child of para.children) {
        let url: string | null = null;
        if (child.type === "link") {
            url = (child as Link).url;
        } else if (child.type === "linkReference") {
            url = definitions.get((child as LinkReference).identifier.toLowerCase()) ?? null;
        }
        if (url !== null && /(?:^|\/)select\.md(?:#|$)/.test(url)) {
            return parseSelectStep(item, definitions);
        }
    }
    return null;
}

function parseSelectStep(
    item: ListItem,
    definitions: ReadonlyMap<string, string>,
): SelectStep | null {
    const colList = firstNestedList(item);
    if (!colList) return null;

    const columns: OutputColumn[] = [];
    for (const child of colList.children) {
        const col = parseOutputColumn(child as ListItem, definitions);
        if (col) columns.push(col);
    }
    return { kind: "select", columns };
}

function parseOutputColumn(
    item: ListItem,
    definitions: ReadonlyMap<string, string>,
): OutputColumn | null {
    const para = firstParagraph(item);
    if (!para) return null;

    const name = firstInlineCode(para);
    if (!name) return null;

    const exprList = firstNestedList(item);
    if (!exprList) return null;

    let expr: Expr;
    try {
        expr = parseExprList(exprList, definitions);
    } catch {
        return null;
    }
    return { name, expr };
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

export type DataRow = Readonly<Record<string, Value>>;

/**
 * Evaluate a parsed pipeline against an array of input rows.
 * Each step's output becomes the next step's input.
 */
export function evaluatePipeline(
    pipeline: ParsedPipeline,
    inputRows: readonly DataRow[],
): DataRow[] {
    let rows: DataRow[] = [...inputRows];
    for (const step of pipeline.steps) {
        rows = evaluateStep(step, rows);
    }
    return rows;
}

function evaluateStep(step: PipelineStep, rows: readonly DataRow[]): DataRow[] {
    if (step.kind === "select") return evaluateSelect(step, rows);
    return [...rows];
}

function evaluateSelect(step: SelectStep, rows: readonly DataRow[]): DataRow[] {
    return rows.map((row) => {
        const out: Record<string, Value> = {};
        for (const col of step.columns) {
            out[col.name] = evalExpr(col.expr, row);
        }
        return out;
    });
}

// ---------------------------------------------------------------------------
// Dataset table parsing
// ---------------------------------------------------------------------------

/**
 * Parse a GFM table node into an array of row objects keyed by column name.
 *
 * Header cells with backtick-wrapped names like `` `first name` `` are
 * unwrapped to plain strings by `rowCells`.  Cell values that look like
 * substrate string literals (`"text"`) have their outer double-quotes
 * stripped so they compare correctly with evaluated string results.
 */
export function parseDatasetTable(
    table: import("mdast").Table,
): DataRow[] {
    const [headerRow, ...dataRows] = table.children;
    if (!headerRow) return [];

    const headers = rowCells(headerRow);

    return dataRows.map((row) => {
        const cells = rowCells(row);
        const record: Record<string, Value> = {};
        headers.forEach((h, j) => {
            record[h] = parseDatasetCellValue(cells[j] ?? "");
        });
        return record;
    });
}

/**
 * Parse a raw table-cell string with the substrate string-literal
 * convention: `"text"` → `text`.  Falls back to the shared
 * `parseCellValue` for booleans and numbers.
 */
export function parseDatasetCellValue(raw: string): Value {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
        return raw.slice(1, -1);
    }
    return parseCellValue(raw);
}

// ---------------------------------------------------------------------------
// MDAST helpers
// ---------------------------------------------------------------------------

function headingText(h: Heading): string {
    const parts: string[] = [];
    function walk(n: unknown): void {
        if (typeof n !== "object" || n === null) return;
        const obj = n as Record<string, unknown>;
        if (typeof obj["value"] === "string") parts.push(obj["value"] as string);
        const children = obj["children"];
        if (Array.isArray(children)) for (const c of children) walk(c);
    }
    walk(h);
    return parts.join("").trim();
}

function firstParagraph(item: ListItem): Paragraph | null {
    return (item.children.find((c) => c.type === "paragraph") as Paragraph) ?? null;
}

function firstNestedList(item: ListItem): List | null {
    return (item.children.find((c) => c.type === "list") as List) ?? null;
}

function firstInlineCode(para: Paragraph): string | null {
    for (const child of para.children) {
        if (child.type === "inlineCode") return (child as InlineCode).value;
    }
    return null;
}
