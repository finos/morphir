/**
 * Ordering type class — corresponds to `specs/language/expressions/ordering.md`.
 *
 * Registers: Compare, Less Than, Greater Than, Less Than or Equal,
 * Greater Than or Equal.
 */
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/ordering.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "compare-operation",
        {
            arity: 2,
            evaluate: (args) => {
                const a = args[0] as number;
                const b = args[1] as number;
                if (a < b) return "Less";
                if (a > b) return "Greater";
                return "Equal";
            },
        },
    ],
    [
        "less-than-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) < (args[1] as number) },
    ],
    [
        "greater-than-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) > (args[1] as number) },
    ],
    [
        "less-than-or-equal-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) <= (args[1] as number) },
    ],
    [
        "greater-than-or-equal-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) >= (args[1] as number) },
    ],
]);
