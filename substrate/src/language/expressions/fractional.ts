/**
 * Fractional type class — corresponds to `specs/language/expressions/fractional.md`.
 *
 * Extends Number. Division returns fractional results.
 */
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/fractional.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "division-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) / (args[1] as number) },
    ],
]);
