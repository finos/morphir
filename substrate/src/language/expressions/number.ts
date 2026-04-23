/**
 * Number type class — corresponds to `specs/language/expressions/number.md`.
 *
 * Registers: Addition, Subtraction, Multiplication, Division,
 * Negation, Absolute Value, Modulus.
 */
import type { OperationEvaluator } from "./index.js";

export const modulePath = "expressions/number.md";

export const operations: ReadonlyMap<string, OperationEvaluator> = new Map<string, OperationEvaluator>([
    [
        "addition-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) + (args[1] as number) },
    ],
    [
        "subtraction-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) - (args[1] as number) },
    ],
    [
        "multiplication-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) * (args[1] as number) },
    ],
    [
        "division-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) / (args[1] as number) },
    ],
    [
        "negation-operation",
        { arity: 1, evaluate: (args) => -(args[0] as number) },
    ],
    [
        "absolute-value-operation",
        { arity: 1, evaluate: (args) => Math.abs(args[0] as number) },
    ],
    [
        "modulus-operation",
        { arity: 2, evaluate: (args) => (args[0] as number) % (args[1] as number) },
    ],
]);
