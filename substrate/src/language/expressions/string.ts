/**
 * String type — corresponds to `specs/language/expressions/string.md`.
 *
 * Registers: Length, Concatenate, Contains.
 */
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/string.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "length-operation",
        { arity: 1, evaluate: (args) => (args[0] as string).length },
    ],
    [
        "concatenate-operation",
        { arity: 2, evaluate: (args) => String(args[0]) + String(args[1]) },
    ],
    [
        "contains-operation",
        {
            arity: 2,
            evaluate: (args) => (args[0] as string).includes(args[1] as string),
        },
    ],
]);
