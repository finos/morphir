/**
 * Expression registry — indexes all operation evaluators by their
 * canonical spec path `{directory}/{file}#{anchor}`.
 *
 * This is the code-side counterpart of `specs/language.md` which
 * indexes all expression modules.
 */
import type { Value } from "../ast.js";

import * as boolean_ from "./boolean.js";
import * as number_ from "./number.js";
import * as equality from "./equality.js";
import * as ordering from "./ordering.js";
import * as string_ from "./string.js";
import * as fractional from "./fractional.js";
import * as date_ from "./date.js";
import * as collection from "./collection.js";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/** An evaluator for a single operation. */
export interface OperationEvaluator {
    readonly arity: number;
    readonly evaluate: (args: readonly Value[]) => Value;
}

// ---------------------------------------------------------------------------
// Registry construction
// ---------------------------------------------------------------------------

const registry = new Map<string, OperationEvaluator>();

function registerModule(
    modulePath: string,
    ops: ReadonlyMap<string, OperationEvaluator>,
): void {
    for (const [anchor, evaluator] of ops) {
        registry.set(`${modulePath}#${anchor}`, evaluator);
    }
}

registerModule(boolean_.modulePath, boolean_.operations);
registerModule(number_.modulePath, number_.operations);
registerModule(equality.modulePath, equality.operations);
registerModule(ordering.modulePath, ordering.operations);
registerModule(string_.modulePath, string_.operations);
registerModule(fractional.modulePath, fractional.operations);
registerModule(date_.modulePath, date_.operations);
registerModule(collection.modulePath, collection.operations);

// ---------------------------------------------------------------------------
// Lookup
// ---------------------------------------------------------------------------

/**
 * Normalise a markdown link URL to a registry key.
 *
 * Extracts the last two path segments before the anchor and combines
 * them with the anchor fragment:
 *
 *   `../language/expressions/number.md#addition-operation`
 *   → `expressions/number.md#addition-operation`
 */
export function normaliseOperationKey(url: string): string | null {
    const hashIdx = url.lastIndexOf("#");
    if (hashIdx === -1) return null;

    const anchor = url.slice(hashIdx + 1);
    const filePart = url.slice(0, hashIdx);
    const segments = filePart.split("/").filter((s) => s.length > 0);

    if (segments.length < 2) return null;

    const dir = segments[segments.length - 2]!;
    const file = segments[segments.length - 1]!;
    return `${dir}/${file}#${anchor}`;
}

/**
 * Resolve an operation evaluator from a markdown link URL.
 *
 * Returns undefined when the operation is not in the registry.
 */
export function resolveOperation(url: string): OperationEvaluator | undefined {
    const key = normaliseOperationKey(url);
    if (key === null) return undefined;
    return registry.get(key);
}

/** The full read-only registry for inspection and testing. */
export function allOperations(): ReadonlyMap<string, OperationEvaluator> {
    return registry;
}
