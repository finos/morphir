/**
 * Literal parser registry — maps a type's spec anchor to a function that
 * parses a raw cell string into a Value.
 *
 * Each entry corresponds to the `## Literals` section (or the type's root
 * anchor) of an expression spec file. Registered by the same normalized
 * path format used for operation keys: `expressions/<file>.md#<anchor>`.
 *
 * See specs/backlog/spec-implementation-alignment.md decision 1.
 */
import type { Value } from "../ast.js";

export type LiteralParserFn = (raw: string) => Value | null;

/** Normalize a type-name string (from link text) to a known parser key. */
const TYPE_NAME_TO_KEY: ReadonlyMap<string, string> = new Map([
    ["boolean", "expressions/boolean.md#literals"],
    ["integer", "expressions/number.md#literals"],
    ["number", "expressions/number.md#literals"],
    ["decimal", "expressions/number.md#literals"],
    ["floating-point", "expressions/number.md#literals"],
    ["string", "expressions/string.md#literals"],
    ["date", "expressions/date.md#literals"],
    ["ordering relation", "expressions/ordering-relation.md"],
    ["ordering-relation", "expressions/ordering-relation.md"],
    ["collection", "expressions/collection.md"],
]);

/**
 * Resolve a link text (the visible label of a type link in an Inputs/Outputs
 * list item) to a literal parser key.
 */
export function typeNameToParserKey(linkText: string): string | null {
    return TYPE_NAME_TO_KEY.get(linkText.toLowerCase()) ?? null;
}

// ---------------------------------------------------------------------------
// Parser implementations
// ---------------------------------------------------------------------------

function parseBoolean(raw: string): Value | null {
    if (raw === "true") return true;
    if (raw === "false") return false;
    return null;
}

function parseNumber(raw: string): Value | null {
    const n = Number(raw);
    if (!Number.isNaN(n) && raw.trim() !== "") return n;
    return null;
}

function parseString(raw: string): Value | null {
    // Quoted form: "hello" → hello (spec convention for string literals)
    if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
        return raw.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, "\\");
    }
    // Bare string — pass through
    return raw;
}

function parseDate(raw: string): Value | null {
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;
    return null;
}

function parseOrderingRelation(raw: string): Value | null {
    if (raw === "Less" || raw === "Equal" || raw === "Greater") return raw;
    return null;
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

function parseCollection(raw: string): Value | null {
    // Accepts JSON array syntax: [], [1], [1, 2, 3], ["a", "b"], etc.
    try {
        const parsed = JSON.parse(raw) as unknown;
        if (Array.isArray(parsed)) return parsed as unknown as Value;
    } catch { /* fall through */ }
    return null;
}

const _registry = new Map<string, LiteralParserFn>([
    ["expressions/boolean.md#literals", parseBoolean],
    ["expressions/number.md#literals", parseNumber],
    ["expressions/string.md#literals", parseString],
    ["expressions/date.md#literals", parseDate],
    ["expressions/ordering-relation.md", parseOrderingRelation],
    ["expressions/collection.md", parseCollection],
]);

/** The full literal-parser registry (for inspection and testing). */
export function literalParserRegistry(): ReadonlyMap<string, LiteralParserFn> {
    return _registry;
}

/**
 * Parse a raw cell string using the literal parser registered for `key`.
 * Returns `null` when the key is unknown or the value fails to parse.
 */
export function parseLiteral(key: string, raw: string): Value | null {
    const parser = _registry.get(key);
    if (!parser) return null;
    return parser(raw);
}

/**
 * Heuristic fallback: try all known parsers in priority order.
 * Used when the column's type is not known from a signature.
 *
 * Order: boolean first (prevents "true" from becoming NaN), then number,
 * then string (always succeeds).
 */
export function parseCellHeuristic(raw: string): Value {
    const b = parseBoolean(raw);
    if (b !== null) return b;
    const n = parseNumber(raw);
    if (n !== null) return n;
    // String: strip surrounding double-quotes if present
    const s = parseString(raw);
    return s ?? raw;
}
