/**
 * Parse a `substrate:` YAML block into a typed `Module` AST.
 *
 * The walker never throws — every problem becomes a `ParseDiagnostic`.
 * A YAML-level syntax error returns `{ module: undefined, diagnostics }`;
 * semantic errors in individual nodes leave the rest of the module
 * intact so a single broken definition does not blank the viewer.
 */

import {
    parseDocument,
    LineCounter,
    isMap,
    isSeq,
    isScalar,
    type Document,
    type Node,
    type ParsedNode,
    type Scalar,
    type YAMLMap,
    type YAMLSeq,
} from "yaml";

import type {
    Apply,
    ApplyKind,
    IfExpr,
    Literal,
    MatchCase,
    MatchExpr,
    Module,
    OneOfType,
    ParseDiagnostic,
    ParseResult,
    SourceLocation,
    TypeDefinition,
    ValueDefinition,
    ValueExpression,
    Variable,
    Variant,
} from "./ast.js";
import { BINARY_OPS, NARY_OPS, UNARY_OPS } from "./ast.js";

// --- Public API ----------------------------------------------------------

export interface ParseContext {
    readonly file: string;
    readonly sectionId: string;
}

export function parseSubstrate(
    text: string,
    ctx: ParseContext,
): ParseResult {
    const lineCounter = new LineCounter();
    const doc: Document.Parsed = parseDocument(text, {
        lineCounter,
        prettyErrors: true,
        keepSourceTokens: false,
    });
    const diagnostics: ParseDiagnostic[] = [];

    for (const e of doc.errors) {
        diagnostics.push({
            severity: "error",
            message: e.message,
            ...(e.linePos?.[0]
                ? {
                    position: {
                        line: e.linePos[0].line,
                        col: e.linePos[0].col,
                    },
                }
                : {}),
        });
    }
    for (const w of doc.warnings) {
        diagnostics.push({
            severity: "warning",
            message: w.message,
            ...(w.linePos?.[0]
                ? {
                    position: {
                        line: w.linePos[0].line,
                        col: w.linePos[0].col,
                    },
                }
                : {}),
        });
    }

    const root = doc.contents;
    if (!root) {
        return { diagnostics };
    }
    if (!isMap(root)) {
        diagnostics.push({
            severity: "error",
            message: "expected top-level mapping",
            ...positionFromNode(root, lineCounter),
        });
        return { diagnostics };
    }

    const w: Walker = { ctx, lineCounter, diagnostics };
    const substrateNode = mapGet(root, "substrate");
    // Empty `substrate:` (no children) — return an empty module.
    if (
        substrateNode &&
        isScalar(substrateNode) &&
        (substrateNode.value === null || substrateNode.value === undefined)
    ) {
        return {
            module: { types: new Map(), values: new Map(), src: [] },
            diagnostics,
        };
    }
    const moduleRoot = substrateNode ?? root;
    if (!isMap(moduleRoot)) {
        diagnostics.push({
            severity: "error",
            message: "`substrate` must be a mapping",
            ...positionFromNode(moduleRoot, lineCounter),
        });
        return { diagnostics };
    }

    const module = parseModule(w, moduleRoot, []);
    return { module, diagnostics };
}

// --- Walker plumbing -----------------------------------------------------

interface Walker {
    readonly ctx: ParseContext;
    readonly lineCounter: LineCounter;
    readonly diagnostics: ParseDiagnostic[];
}

function diag(
    w: Walker,
    severity: ParseDiagnostic["severity"],
    message: string,
    node: Node | null | undefined,
    path: readonly (string | number)[],
): void {
    w.diagnostics.push({
        severity,
        message,
        ...(node ? positionFromNode(node, w.lineCounter) : {}),
        path,
    });
}

function positionFromNode(
    node: Node | null | undefined,
    lc: LineCounter,
): Pick<ParseDiagnostic, "position"> {
    const range = (node as { range?: [number, number, number] } | undefined)
        ?.range;
    if (!range) return {};
    const pos = lc.linePos(range[0]);
    return { position: { line: pos.line, col: pos.col } };
}

// --- Source location extraction -----------------------------------------

/**
 * Pull every `src:` entry off the mapping and convert each scalar (or
 * sequence of scalars) into a `SourceLocation`. The remaining entries
 * are returned for the caller to interpret. The returned `entries`
 * preserves order minus the `src` keys.
 */
function extractSrc(
    w: Walker,
    map: YAMLMap.Parsed,
    path: readonly (string | number)[],
): {
    src: readonly SourceLocation[];
    entries: readonly { key: string; value: ParsedNode }[];
} {
    const src: SourceLocation[] = [];
    const entries: { key: string; value: ParsedNode }[] = [];
    for (const pair of map.items) {
        const key = scalarKey(pair.key);
        if (key === null) {
            diag(w, "warning", "ignoring non-string mapping key", pair.key as Node, path);
            continue;
        }
        if (key === "src") {
            collectSrcInto(w, pair.value, src, [...path, "src"]);
            continue;
        }
        if (pair.value) entries.push({ key, value: pair.value });
    }
    return { src, entries };
}

function collectSrcInto(
    w: Walker,
    node: Node | null | undefined,
    out: SourceLocation[],
    path: readonly (string | number)[],
): void {
    if (!node) return;
    if (isScalar(node)) {
        const v = node.value;
        if (typeof v === "string" && v.trim().length > 0) {
            out.push({
                file: w.ctx.file,
                sectionId: w.ctx.sectionId,
                text: v,
            });
        }
        return;
    }
    if (isSeq(node)) {
        for (const item of node.items) {
            collectSrcInto(w, item as Node, out, path);
        }
        return;
    }
    diag(w, "warning", "`src` must be a string or list of strings", node, path);
}

// --- Module --------------------------------------------------------------

function parseModule(
    w: Walker,
    node: YAMLMap.Parsed,
    path: readonly (string | number)[],
): Module {
    const { src, entries } = extractSrc(w, node, path);
    const types = new Map<string, TypeDefinition>();
    const values = new Map<string, ValueDefinition>();
    let lastInterpretedAt: Date | undefined;

    for (const { key, value } of entries) {
        if (key === "last-interpreted-at") {
            const parsed = parseLastInterpretedAt(w, value, [...path, key]);
            if (parsed) lastInterpretedAt = parsed;
            continue;
        }
        if (key === "types") {
            if (!isMap(value)) {
                diag(w, "error", "`types` must be a mapping", value, [...path, "types"]);
                continue;
            }
            for (const pair of value.items) {
                const name = scalarKey(pair.key);
                if (!name) {
                    diag(w, "error", "type name must be a string", pair.key as Node, [...path, "types"]);
                    continue;
                }
                if (!pair.value || !isMap(pair.value)) {
                    diag(w, "error", `type '${name}' must be a mapping`, pair.value as Node, [...path, "types", name]);
                    continue;
                }
                const def = parseTypeDefinition(w, pair.value, [...path, "types", name]);
                if (def) types.set(name, def);
            }
        } else if (key === "values") {
            if (!isMap(value)) {
                diag(w, "error", "`values` must be a mapping", value, [...path, "values"]);
                continue;
            }
            for (const pair of value.items) {
                const name = scalarKey(pair.key);
                if (!name) {
                    diag(w, "error", "value name must be a string", pair.key as Node, [...path, "values"]);
                    continue;
                }
                if (!pair.value) {
                    diag(w, "error", `value '${name}' has no body`, null, [...path, "values", name]);
                    continue;
                }
                const def = parseValueDefinition(w, pair.value, [...path, "values", name]);
                if (def) values.set(name, def);
            }
        } else {
            diag(w, "warning", `unknown module key '${key}'`, value, [...path, key]);
        }
    }

    return lastInterpretedAt
        ? { types, values, src, lastInterpretedAt }
        : { types, values, src };
}

function parseLastInterpretedAt(
    w: Walker,
    node: Node | null | undefined,
    path: readonly (string | number)[],
): Date | undefined {
    if (!node) return undefined;
    if (!isScalar(node)) {
        diag(w, "error", "`last-interpreted-at` must be a timestamp string", node, path);
        return undefined;
    }
    const raw = node.value;
    if (raw instanceof Date) {
        return Number.isNaN(raw.getTime()) ? undefined : raw;
    }
    if (typeof raw !== "string" || raw.trim().length === 0) {
        diag(w, "error", "`last-interpreted-at` must be a timestamp string", node, path);
        return undefined;
    }
    const d = new Date(raw);
    if (Number.isNaN(d.getTime())) {
        diag(w, "error", `\`last-interpreted-at\` is not a valid timestamp: '${raw}'`, node, path);
        return undefined;
    }
    return d;
}

// --- Types ---------------------------------------------------------------

function parseTypeDefinition(
    w: Walker,
    node: YAMLMap.Parsed,
    path: readonly (string | number)[],
): TypeDefinition | null {
    const { src, entries } = extractSrc(w, node, path);
    const oneOfEntry = entries.find((e) => e.key === "one-of");
    if (!oneOfEntry) {
        diag(w, "error", "type definition must have `one-of`", node, path);
        return null;
    }
    if (!isSeq(oneOfEntry.value)) {
        diag(w, "error", "`one-of` must be a sequence", oneOfEntry.value, [...path, "one-of"]);
        return null;
    }
    const variants: Variant[] = [];
    oneOfEntry.value.items.forEach((item, i) => {
        const variant = parseVariant(w, item as ParsedNode, [...path, "one-of", i]);
        if (variant) variants.push(variant);
    });
    const def: OneOfType = { kind: "one-of", variants, src };
    return def;
}

function parseVariant(
    w: Walker,
    node: ParsedNode,
    path: readonly (string | number)[],
): Variant | null {
    if (isScalar(node)) {
        const name = String(node.value ?? "").trim();
        if (!name) {
            diag(w, "error", "variant must have a name", node, path);
            return null;
        }
        return { name, src: [] };
    }
    if (!isMap(node)) {
        diag(w, "error", "variant must be a name or a mapping", node, path);
        return null;
    }
    const { src, entries } = extractSrc(w, node, path);
    const tagEntry = entries.find((e) => e.key === "tag" || e.key === "name");
    let name: string | null = null;
    if (tagEntry && isScalar(tagEntry.value)) {
        name = String(tagEntry.value.value ?? "");
    } else if (entries.length > 0 && entries[0]) {
        // Fall back to the first non-src key as the variant name.
        name = entries[0].key;
    }
    if (!name) {
        diag(w, "error", "variant must have a `tag` or name", node, path);
        return null;
    }
    return { name, src };
}

// --- Values --------------------------------------------------------------

function parseValueDefinition(
    w: Walker,
    node: ParsedNode,
    path: readonly (string | number)[],
): ValueDefinition | null {
    // Two shapes accepted:
    //   <expr>                       → params: [], body: <expr>
    //   { params: [...], body: <expr>, src?: ... }
    if (isMap(node)) {
        const params: string[] = [];
        let bodyNode: ParsedNode | null = null;
        let bodySrc: readonly SourceLocation[] = [];
        let hasExplicitParams = false;
        let hasExplicitBody = false;
        for (const pair of node.items) {
            const key = scalarKey(pair.key);
            if (key === "params") {
                hasExplicitParams = true;
                if (isSeq(pair.value)) {
                    for (const p of pair.value.items) {
                        if (isScalar(p) && typeof p.value === "string") {
                            params.push(p.value);
                        } else {
                            diag(w, "error", "param must be a string", p as Node, [...path, "params"]);
                        }
                    }
                } else {
                    diag(w, "error", "`params` must be a sequence of strings", pair.value as Node, [...path, "params"]);
                }
            } else if (key === "body") {
                hasExplicitBody = true;
                bodyNode = pair.value as ParsedNode;
            }
        }
        if (hasExplicitBody || hasExplicitParams) {
            // Capture src at the value-def level.
            const { src } = extractSrc(w, node, path);
            bodySrc = src;
            const body = bodyNode
                ? parseExpression(w, bodyNode, [...path, "body"])
                : nullLiteral(bodySrc);
            return { params, body, src: bodySrc };
        }
    }
    // No explicit params/body — the node itself is the body.
    const body = parseExpression(w, node, path);
    return { params: [], body, src: body.src };
}

// --- Expressions ---------------------------------------------------------

function parseExpression(
    w: Walker,
    node: ParsedNode,
    path: readonly (string | number)[],
): ValueExpression {
    if (isScalar(node)) {
        return parseScalarExpression(node, []);
    }
    if (isSeq(node)) {
        // A bare sequence in expression position. Single-item sequences
        // unwrap (authors often wrap an expression in a list); longer
        // sequences are an error — we return the first item as a
        // best-effort fallback.
        if (node.items.length === 0) {
            diag(w, "error", "empty sequence in expression position", node, path);
            return nullLiteral([]);
        }
        if (node.items.length > 1) {
            diag(
                w,
                "warning",
                "sequence in expression position — using first item",
                node,
                path,
            );
        }
        const first = node.items[0] as ParsedNode;
        return parseExpression(w, first, [...path, 0]);
    }
    if (!isMap(node)) {
        diag(w, "error", "unexpected expression node", node, path);
        return nullLiteral([]);
    }
    return parseMappingExpression(w, node, path);
}

function parseScalarExpression(
    node: Scalar,
    src: readonly SourceLocation[],
): ValueExpression {
    const v = node.value;
    if (v === null || v === undefined) {
        return { kind: "literal-null", src };
    }
    if (typeof v === "boolean") {
        return { kind: "literal-boolean", value: v, src };
    }
    if (typeof v === "number") {
        return { kind: "literal-number", value: v, src };
    }
    if (typeof v === "string") {
        // Quoted strings → literal-string. Plain (unquoted) strings that
        // are bare identifiers → variable. The yaml package records
        // quote style in `node.type`.
        const quoted =
            node.type === "QUOTE_SINGLE" || node.type === "QUOTE_DOUBLE";
        if (!quoted && /^-?[\d,]+(\.\d+)?$/.test(v) && v.includes(",")) {
            const n = Number(v.replace(/,/g, ""));
            if (Number.isFinite(n)) {
                return { kind: "literal-number", value: n, src };
            }
        }
        if (!quoted && /^[A-Za-z_][A-Za-z0-9_-]*$/.test(v)) {
            return { kind: "variable", name: v, src };
        }
        return { kind: "literal-string", value: v, src };
    }
    // Fallback: stringify.
    return { kind: "literal-string", value: String(v), src };
}

function parseMappingExpression(
    w: Walker,
    node: YAMLMap.Parsed,
    path: readonly (string | number)[],
): ValueExpression {
    const { src, entries } = extractSrc(w, node, path);

    // Explicit 'lit: <value>' form for literals. This is optional — a plain scalar is also a literal — but it allows an author to be explicit about their intent and avoid the YAML parser's heuristics.
    const litEntry = entries.find((e) => e.key === "lit");
    if (litEntry) {
        if (isScalar(litEntry.value)) {
            return parseScalarExpression(litEntry.value, src);
        }
        diag(w, "error", "`lit` value must be a scalar", litEntry.value, [...path, "lit"]);
        return nullLiteral(src);
    }

    // Explicit `var: <name>` form.
    const varEntry = entries.find((e) => e.key === "var");
    if (varEntry) {
        if (isScalar(varEntry.value) && typeof varEntry.value.value === "string") {
            const v: Variable = {
                kind: "variable",
                name: varEntry.value.value,
                src,
            };
            return v;
        }
        diag(w, "error", "`var` must be a string", varEntry.value, [...path, "var"]);
        return nullLiteral(src);
    }

    // `if` / `then` / `else`.
    const ifEntry = entries.find((e) => e.key === "if");
    if (ifEntry) {
        return parseIf(w, entries, src, path);
    }

    // `match`.
    const matchEntry = entries.find((e) => e.key === "match");
    if (matchEntry) {
        return parseMatch(w, matchEntry.value, src, path);
    }

    // Operator key.
    const opEntry = findOperatorEntry(entries);
    if (opEntry) {
        return parseApply(w, opEntry.kind, opEntry.value, src, [...path, opEntry.raw]);
    }

    diag(
        w,
        "error",
        `unknown expression shape — keys: ${entries.map((e) => e.key).join(", ") || "(empty)"}`,
        node,
        path,
    );
    return nullLiteral(src);
}

function parseIf(
    w: Walker,
    entries: readonly { key: string; value: ParsedNode }[],
    src: readonly SourceLocation[],
    path: readonly (string | number)[],
): IfExpr {
    const cond = entries.find((e) => e.key === "if")?.value;
    const thenN = entries.find((e) => e.key === "then")?.value;
    const elseN = entries.find((e) => e.key === "else")?.value;
    if (!cond) {
        diag(w, "error", "`if` missing condition", null, path);
    }
    if (!thenN) diag(w, "error", "`if` missing `then`", null, path);
    if (!elseN) diag(w, "error", "`if` missing `else`", null, path);
    return {
        kind: "if",
        condition: cond
            ? parseExpression(w, cond, [...path, "if"])
            : nullLiteral([]),
        then: thenN
            ? parseExpression(w, thenN, [...path, "then"])
            : nullLiteral([]),
        else: elseN
            ? parseExpression(w, elseN, [...path, "else"])
            : nullLiteral([]),
        src,
    };
}

function parseMatch(
    w: Walker,
    matchNode: ParsedNode,
    src: readonly SourceLocation[],
    path: readonly (string | number)[],
): MatchExpr {
    if (!isMap(matchNode)) {
        diag(w, "error", "`match` must be a mapping", matchNode, [...path, "match"]);
        return { kind: "match", on: nullLiteral([]), cases: [], src };
    }
    const { src: innerSrc, entries } = extractSrc(w, matchNode, [...path, "match"]);
    const on = entries.find((e) => e.key === "on")?.value;
    const casesNode = entries.find((e) => e.key === "cases")?.value;
    const cases: MatchCase[] = [];
    if (casesNode && isSeq(casesNode)) {
        casesNode.items.forEach((item, i) => {
            const c = parseMatchCase(w, item as ParsedNode, [
                ...path,
                "match",
                "cases",
                i,
            ]);
            if (c) cases.push(c);
        });
    } else if (casesNode) {
        diag(w, "error", "`cases` must be a sequence", casesNode, [
            ...path,
            "match",
            "cases",
        ]);
    }
    return {
        kind: "match",
        on: on ? parseExpression(w, on, [...path, "match", "on"]) : nullLiteral([]),
        cases,
        src: [...src, ...innerSrc],
    };
}

function parseMatchCase(
    w: Walker,
    node: ParsedNode,
    path: readonly (string | number)[],
): MatchCase | null {
    if (!isMap(node)) {
        diag(w, "error", "match case must be a mapping", node, path);
        return null;
    }
    const { src, entries } = extractSrc(w, node, path);
    const when = entries.find((e) => e.key === "when")?.value;
    const then = entries.find((e) => e.key === "then")?.value;
    if (!when || !then) {
        diag(w, "error", "match case requires `when` and `then`", node, path);
    }
    return {
        when: when
            ? parseExpression(w, when, [...path, "when"])
            : nullLiteral([]),
        then: then
            ? parseExpression(w, then, [...path, "then"])
            : nullLiteral([]),
        src,
    };
}

// --- Apply ---------------------------------------------------------------

const OP_ALIASES: Record<string, ApplyKind> = {
    "all-of": "and",
    "any-of": "or",
    eq: "equals",
    neq: "not-equals",
    lt: "less-than",
    lte: "less-than-or-equal",
    gt: "greater-than",
    gte: "greater-than-or-equal",
};

function findOperatorEntry(
    entries: readonly { key: string; value: ParsedNode }[],
): { kind: ApplyKind; raw: string; value: ParsedNode } | null {
    for (const e of entries) {
        const resolved = resolveOpKey(e.key);
        if (resolved) return { kind: resolved, raw: e.key, value: e.value };
    }
    return null;
}

function resolveOpKey(key: string): ApplyKind | null {
    if (
        (BINARY_OPS as readonly string[]).includes(key) ||
        (UNARY_OPS as readonly string[]).includes(key) ||
        (NARY_OPS as readonly string[]).includes(key)
    ) {
        return key as ApplyKind;
    }
    return OP_ALIASES[key] ?? null;
}

function parseApply(
    w: Walker,
    kind: ApplyKind,
    value: ParsedNode,
    src: readonly SourceLocation[],
    path: readonly (string | number)[],
): ValueExpression {
    if ((UNARY_OPS as readonly string[]).includes(kind)) {
        const operand = parseExpression(w, value, [...path, 0]);
        return { kind, operand, src } as Apply;
    }
    if ((BINARY_OPS as readonly string[]).includes(kind)) {
        const pair = parseBinaryOperands(w, value, path);
        return { kind, left: pair.left, right: pair.right, src } as Apply;
    }
    // N-ary.
    const args = parseNaryOperands(w, value, path);
    return { kind, args, src } as Apply;
}

function parseBinaryOperands(
    w: Walker,
    value: ParsedNode,
    path: readonly (string | number)[],
): { left: ValueExpression; right: ValueExpression } {
    if (isSeq(value)) {
        if (value.items.length !== 2) {
            diag(
                w,
                "error",
                `binary operator expects 2 operands, got ${value.items.length}`,
                value,
                path,
            );
        }
        const left = value.items[0]
            ? parseExpression(w, value.items[0] as ParsedNode, [...path, 0])
            : nullLiteral([]);
        const right = value.items[1]
            ? parseExpression(w, value.items[1] as ParsedNode, [...path, 1])
            : nullLiteral([]);
        return { left, right };
    }
    if (isMap(value)) {
        const leftP = value.items.find((p) => scalarKey(p.key) === "left");
        const rightP = value.items.find((p) => scalarKey(p.key) === "right");
        if (!leftP || !rightP) {
            diag(
                w,
                "error",
                "binary operator mapping requires `left` and `right`",
                value,
                path,
            );
        }
        const left = leftP
            ? parseExpression(w, leftP.value as ParsedNode, [...path, "left"])
            : nullLiteral([]);
        const right = rightP
            ? parseExpression(w, rightP.value as ParsedNode, [...path, "right"])
            : nullLiteral([]);
        return { left, right };
    }
    diag(w, "error", "binary operator operands must be a sequence or mapping", value, path);
    return { left: nullLiteral([]), right: nullLiteral([]) };
}

function parseNaryOperands(
    w: Walker,
    value: ParsedNode,
    path: readonly (string | number)[],
): readonly ValueExpression[] {
    if (isSeq(value)) {
        return value.items.map((item, i) =>
            parseExpression(w, item as ParsedNode, [...path, i]),
        );
    }
    if (isMap(value)) {
        // Tolerate the YAML idiom of repeated keys collapsed to a
        // mapping with operator-keyed children (e.g. `all-of: { less-than:
        // [...], less-than: [...] }`). Treat each value as one operand
        // by re-parsing the mapping as if it were a single expression
        // per entry.
        const out: ValueExpression[] = [];
        for (const pair of value.items) {
            const k = scalarKey(pair.key);
            if (!k) continue;
            const op = resolveOpKey(k);
            if (op) {
                out.push(
                    parseApply(w, op, pair.value as ParsedNode, [], [...path, k]),
                );
            } else {
                diag(w, "warning", `unexpected key '${k}' in n-ary operands`, pair.value as Node, [...path, k]);
            }
        }
        return out;
    }
    // Single value → single-element list.
    return [parseExpression(w, value, [...path, 0])];
}

// --- Helpers -------------------------------------------------------------

function scalarKey(node: unknown): string | null {
    if (isScalar(node as Node)) {
        const v = (node as Scalar).value;
        if (typeof v === "string") return v;
        if (typeof v === "number" || typeof v === "boolean") return String(v);
    }
    return null;
}

function mapGet(node: YAMLMap, key: string): ParsedNode | null {
    for (const pair of node.items as YAMLMap.Parsed["items"]) {
        if (scalarKey(pair.key) === key) {
            return (pair.value as ParsedNode) ?? null;
        }
    }
    return null;
}

function nullLiteral(src: readonly SourceLocation[]): Literal {
    return { kind: "literal-null", src };
}

// Re-export YAMLSeq for type-only consumers that want the structural type.
export type { YAMLSeq };
