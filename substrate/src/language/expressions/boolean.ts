/**
 * Boolean expressions — corresponds to `specs/language/expressions/boolean.md`.
 *
 * Registers: NOT, AND, OR, XOR, IMPLIES, If-Then-Else.
 */
import type { Value } from "../ast.js";
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/boolean.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "not-operation",
        { arity: 1, evaluate: (args) => !(args[0] as boolean) },
    ],
    [
        "and-operation",
        { arity: 2, evaluate: (args) => (args[0] as boolean) && (args[1] as boolean) },
    ],
    [
        "or-operation",
        { arity: 2, evaluate: (args) => (args[0] as boolean) || (args[1] as boolean) },
    ],
    [
        "xor-operation",
        { arity: 2, evaluate: (args) => (args[0] as boolean) !== (args[1] as boolean) },
    ],
    [
        "implies-operation",
        { arity: 2, evaluate: (args) => !(args[0] as boolean) || (args[1] as boolean) },
    ],
    [
        "if-then-else-operation",
        { arity: 3, evaluate: (args) => (args[0] as boolean) ? args[1]! : args[2]! },
    ],
]);
