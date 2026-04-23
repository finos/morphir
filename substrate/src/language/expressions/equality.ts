/**
 * Equality type class — corresponds to `specs/language/expressions/equality.md`.
 *
 * Registers: Equal, Not Equal.
 */
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/equality.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "equal-operation",
        { arity: 2, evaluate: (args) => args[0] === args[1] },
    ],
    [
        "not-equal-operation",
        { arity: 2, evaluate: (args) => args[0] !== args[1] },
    ],
]);
